// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FlashLoanSimpleReceiverBase} from "@aave/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISwapRouter} from "./dependencies/iguana/ISwapRouter.sol";
import {TransferHelper} from "./dependencies/iguana/TransferHelper.sol";
import {DataTypes} from "./DataTypes.sol";
import {FlashLiquidationEncoding} from "./FlashLiquidationEncoding.sol";
import {FlashLiquidationSwaps} from "./FlashLiquidationSwaps.sol";

/**
 * @title FlashLiquidations
 * @notice Main contract for executing flash loan-based liquidations on Aave V3 with support for hAsset handling
 * @dev This contract combines flash loan functionality with liquidation and token swapping capabilities
 * It allows liquidators to execute liquidations using flash loans, optimizing capital efficiency
 * Supports both regular assets and hAssets (Hanji protocol assets) for collateral
 */
contract FlashLiquidations is
    FlashLoanSimpleReceiverBase,
    Ownable,
    FlashLiquidationEncoding,
    FlashLiquidationSwaps
{
    constructor(
        IPoolAddressesProvider _addressProvider,
        ISwapRouter _swapRouter
    )
        FlashLoanSimpleReceiverBase(_addressProvider)
        Ownable(msg.sender)
        FlashLiquidationSwaps(_swapRouter)
    {}

    /**
     * @notice Executes the flash loan operation and subsequent liquidation
     * @dev This is the callback function called by Aave's lending pool after the flash loan
     * @param asset The address of the flash-borrowed asset
     * @param amount The amount of the flash-borrowed asset
     * @param premium The fee for the flash loan
     * @param params The encoded parameters containing liquidation details
     * @return bool True if the operation was successful
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata params
    ) external override returns (bool) {
        require(
            msg.sender == address(POOL),
            "FlashLiquidations: Caller must be lending pool"
        );

        DataTypes.LiquidationParams memory decodedParams = _decodeParams(
            params
        );

        require(
            asset == decodedParams.borrowedAsset,
            "FlashLiquidations: Wrong params passed - asset not the same"
        );
        _executeLiquidation(decodedParams, amount, premium);
        return true;
    }

    /**
     * @notice Initiates a flash loan-based liquidation
     * @dev This is the main entry point for executing liquidations
     * @param tokenAddress The address of the token to flash loan
     * @param _amount The amount of tokens to flash loan
     * @param colToken The address of the collateral token
     * @param user The address of the user to liquidate
     * @param poolFee1 The fee tier for the first pool in the swap path
     * @param poolFee2 The fee tier for the second pool in the swap path (if using multi-hop)
     * @param pathToken The intermediate token for multi-hop swaps
     * @param usePath Whether to use a multi-hop swap path
     */
    function executeLiquidation(
        address tokenAddress,
        uint256 _amount,
        address colToken,
        address user,
        uint24 poolFee1,
        uint24 poolFee2,
        address pathToken,
        bool usePath
    ) external {
        address receiverAddress = address(this);
        address asset = tokenAddress;
        uint256 amount = _amount;
        uint16 referralCode = 0;

        bytes memory params = _encodeParams(
            colToken,
            asset,
            user,
            amount,
            poolFee1,
            poolFee2,
            pathToken,
            usePath
        );

        POOL.flashLoanSimple(
            receiverAddress,
            asset,
            amount,
            params,
            referralCode
        );

        DataTypes.LiquidationParams memory decodedParams = _decodeParams(
            params
        );

        (
            address formattedCollateralAsset,

        ) = _validateHAssetAndGetTokenAddress(decodedParams.collateralAsset);

        uint256 allBalance = IERC20(formattedCollateralAsset).balanceOf(
            address(this)
        );
        uint256 debtTokensRemaining = IERC20(decodedParams.borrowedAsset)
            .balanceOf(address(this));

        if (debtTokensRemaining > 0) {
            IERC20(decodedParams.borrowedAsset).transfer(
                msg.sender,
                debtTokensRemaining
            );
        }

        IERC20(formattedCollateralAsset).transfer(msg.sender, allBalance);
    }

    /**
     * @notice Sets the vault address for a given hAsset
     * @dev Only the owner can set the vault address
     * @param hAsset The address of the hAsset
     * @param vault The address of the vault
     */
    function setHAssetToVault(
        address hAsset,
        address vault
    ) external onlyOwner {
        _setHAssetToVault(hAsset, vault);
    }

    /**
     * @notice Sets the swap router
     * @dev Only the owner can set the swap router
     * @param __swapRouter The address of the swap router
     */
    function setSwapRouter(ISwapRouter __swapRouter) external onlyOwner {
        _setSwapRouter(__swapRouter);
    }

    /**
     * @notice Internal function to execute the liquidation and token swaps
     * @dev Handles the core liquidation logic including token approvals, liquidation call, and token swaps
     * Supports hAsset handling by validating and withdrawing from Hanji vaults when necessary
     * @param params The encoded parameters containing liquidation details
     * @param flashBorrowedAmount The amount borrowed via flash loan
     * @param premium The flash loan premium to be repaid
     */
    function _executeLiquidation(
        DataTypes.LiquidationParams memory params,
        uint256 flashBorrowedAmount,
        uint256 premium
    ) internal {
        DataTypes.LiquidationCallLocalVars
            memory variables = _populateLiquidationCallLocalVars(
                params,
                flashBorrowedAmount,
                premium
            );

        require(
            IERC20(params.borrowedAsset).approve(
                address(POOL),
                params.debtToCover
            ),
            "FlashLiquidations: Error while approving"
        );

        POOL.liquidationCall(
            params.collateralAsset,
            params.borrowedAsset,
            params.user,
            params.debtToCover,
            false
        );

        variables.diffCollateralBalance =
            IERC20(params.collateralAsset).balanceOf(address(this)) -
            variables.initCollateralBalance;

        if (params.collateralAsset != params.borrowedAsset) {
            uint256 flashBorrowedAssetAfter = IERC20(params.borrowedAsset)
                .balanceOf(address(this));
            variables.diffFlashBorrowedBalance =
                flashBorrowedAssetAfter -
                variables.borrowedAssetLeftovers;
            uint256 amountOut = variables.flashLoanDebt -
                variables.diffFlashBorrowedBalance;

            (
                address formattedCollateralAsset,
                uint256 formattedCollateralAmount
            ) = _validateAndWithdrawHAsset(
                    params.collateralAsset,
                    variables.diffCollateralBalance
                );

            variables.soldAmount = _executeSwap(
                formattedCollateralAsset,
                params.borrowedAsset,
                amountOut,
                formattedCollateralAmount,
                params.poolFee1,
                params.poolFee2,
                params.pathToken,
                params.usePath
            );

            variables.remainingTokens =
                variables.diffCollateralBalance -
                variables.soldAmount;
        } else {
            variables.remainingTokens =
                variables.diffCollateralBalance -
                premium;
        }

        IERC20(params.borrowedAsset).approve(
            address(POOL),
            variables.flashLoanDebt
        );
    }

    /**
     * @notice Populates the local variables needed for liquidation operations
     * @dev Initializes balances and calculates flash loan debt
     * @param params The liquidation parameters
     * @param flashBorrowedAmount The amount borrowed via flash loan
     * @param premium The flash loan premium
     * @return variables The populated LiquidationCallLocalVars struct
     */
    function _populateLiquidationCallLocalVars(
        DataTypes.LiquidationParams memory params,
        uint256 flashBorrowedAmount,
        uint256 premium
    )
        internal
        view
        returns (DataTypes.LiquidationCallLocalVars memory variables)
    {
        variables.initCollateralBalance = IERC20(params.collateralAsset)
            .balanceOf(address(this));

        if (params.collateralAsset != params.borrowedAsset) {
            variables.initFlashBorrowedBalance = IERC20(params.borrowedAsset)
                .balanceOf(address(this));
            variables.borrowedAssetLeftovers =
                variables.initFlashBorrowedBalance -
                flashBorrowedAmount;
        }

        variables.flashLoanDebt = flashBorrowedAmount + premium;
    }
}
