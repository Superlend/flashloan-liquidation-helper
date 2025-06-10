// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FlashLoanSimpleReceiverBase} from "@aave/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISwapRouter} from "./dependencies/ISwapRouter.sol";
import {TransferHelper} from "./dependencies/TransferHelper.sol";
import {DataTypes} from "./DataTypes.sol";
import {FlashLiquidationEncoding} from "./FlashLiquidationEncoding.sol";
import {FlashLiquidationSwaps} from "./FlashLiquidationSwaps.sol";

/**
 * @title FlashLiquidations
 * @notice Main contract for executing flash loan-based liquidations on Aave V3
 * @dev This contract combines flash loan functionality with liquidation and token swapping capabilities
 * It allows liquidators to execute liquidations using flash loans, optimizing capital efficiency
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
        _executeLiquidation(
            decodedParams.collateralAsset,
            decodedParams.borrowedAsset,
            decodedParams.user,
            decodedParams.debtToCover,
            decodedParams.poolFee1,
            decodedParams.poolFee2,
            decodedParams.pathToken,
            decodedParams.usePath,
            amount,
            premium
        );
        return true;
    }

    /**
     * @notice Internal function to execute the liquidation and token swaps
     * @dev Handles the core liquidation logic including token approvals, liquidation call, and token swaps
     * @param collateralAsset The address of the collateral asset received from liquidation
     * @param borrowedAsset The address of the asset borrowed via flash loan
     * @param user The address of the user being liquidated
     * @param debtToCover The amount of debt to be liquidated
     * @param poolFee1 The fee tier for the first pool in the swap path
     * @param poolFee2 The fee tier for the second pool in the swap path (if using multi-hop)
     * @param pathToken The intermediate token for multi-hop swaps
     * @param usePath Whether to use a multi-hop swap path
     * @param flashBorrowedAmount The amount borrowed via flash loan
     * @param premium The flash loan premium to be repaid
     */
    function _executeLiquidation(
        address collateralAsset,
        address borrowedAsset,
        address user,
        uint256 debtToCover,
        uint24 poolFee1,
        uint24 poolFee2,
        address pathToken,
        bool usePath,
        uint256 flashBorrowedAmount,
        uint256 premium
    ) internal {
        DataTypes.LiquidationCallLocalVars memory variables;

        variables.initCollateralBalance = IERC20(collateralAsset).balanceOf(
            address(this)
        );

        if (collateralAsset != borrowedAsset) {
            variables.initFlashBorrowedBalance = IERC20(borrowedAsset)
                .balanceOf(address(this));
            variables.borrowedAssetLeftovers =
                variables.initFlashBorrowedBalance -
                flashBorrowedAmount;
        }

        variables.flashLoanDebt = flashBorrowedAmount + premium;

        require(
            IERC20(borrowedAsset).approve(address(POOL), debtToCover),
            "FlashLiquidations: Error while approving"
        );

        POOL.liquidationCall(
            collateralAsset,
            borrowedAsset,
            user,
            debtToCover,
            false
        );

        uint256 collateralBalanceAfter = IERC20(collateralAsset).balanceOf(
            address(this)
        );
        variables.diffCollateralBalance =
            collateralBalanceAfter -
            variables.initCollateralBalance;

        if (collateralAsset != borrowedAsset) {
            uint256 flashBorrowedAssetAfter = IERC20(borrowedAsset).balanceOf(
                address(this)
            );
            variables.diffFlashBorrowedBalance =
                flashBorrowedAssetAfter -
                variables.borrowedAssetLeftovers;
            uint256 amountOut = variables.flashLoanDebt -
                variables.diffFlashBorrowedBalance;

            variables.soldAmount = _executeSwap(
                collateralAsset,
                borrowedAsset,
                amountOut,
                variables.diffCollateralBalance,
                poolFee1,
                poolFee2,
                pathToken,
                usePath
            );

            variables.remainingTokens =
                variables.diffCollateralBalance -
                variables.soldAmount;
        } else {
            variables.remainingTokens =
                variables.diffCollateralBalance -
                premium;
        }

        IERC20(borrowedAsset).approve(address(POOL), variables.flashLoanDebt);
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

        uint256 allBalance = IERC20(decodedParams.collateralAsset).balanceOf(
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

        IERC20(decodedParams.collateralAsset).transfer(msg.sender, allBalance);
    }
}
