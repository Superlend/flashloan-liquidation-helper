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
     * @notice This function executes the operation after receiving assets in form of Flash loan
     * @dev Must be ensured that contract can return debt + premium
     * @param asset -> the address of flash-borrowed asset
     * @param amount -> the amount of the flash-borrowed asset
     * @param premium -> fee for flashloan
     * @param params -> The byte-encoded params passed when init flashloan
     * @return true if execution of operation seccess, else false
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
     * @notice Executes the operation of liquidating the debt position after it swaps collateral asset back to asset borrowed via flashloan
     * @dev Pool contract must be approved for operations
     * @param collateralAsset -> Address of asset received from the liquidation
     * @param borrowedAsset -> Address of the asset borrowed via flashloan
     * @param user -> address of the user being liquidated
     * @param debtToCover -> amount of the debt to be liauidated
     * @param poolFee1 -> fee connected to pool
     * @param poolFee2 -> fee connected to pool
     * @param pathToken -> token which in case needs to be swap between two other tokens from the pool
     * @param usePath -> decicion whether to use single or multihop swap
     * @param flashBorrowedAmount -> amount that was borrowed via flashloan
     * @param premium -> fee for taking out flashloan
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
        // Approval for router to spend `amountInMaximum` of colateral
        // In prod the max amount should be spend based on oracles or other data sources to acheive better swap
        DataTypes.LiquidationCallLocalVars memory variables;

        // Initial collateral balance
        variables.initCollateralBalance = IERC20(collateralAsset).balanceOf(
            address(this)
        );

        // Check whether the initial balance of tokens was borrowed
        if (collateralAsset != borrowedAsset) {
            variables.initFlashBorrowedBalance = IERC20(borrowedAsset)
                .balanceOf(address(this));
            variables.borrowedAssetLeftovers =
                variables.initFlashBorrowedBalance -
                flashBorrowedAmount;
        }

        // Calculate the amount which will be send back to Aave pool
        variables.flashLoanDebt = flashBorrowedAmount + premium;

        // Approve the pool to liquidate debt position
        require(
            IERC20(borrowedAsset).approve(address(POOL), debtToCover),
            "FlashLiquidations: Error while approving"
        );

        // Liquidating the debt possition
        POOL.liquidationCall(
            collateralAsset,
            borrowedAsset,
            user,
            debtToCover,
            false
        );

        // Compare initial collateral balance with collateral balance after liquidation
        uint256 collateralBalanceAfter = IERC20(collateralAsset).balanceOf(
            address(this)
        );
        variables.diffCollateralBalance =
            collateralBalanceAfter -
            variables.initCollateralBalance;

        // Calculate the swap and necessary collateral tokens to repay flashLoan
        if (collateralAsset != borrowedAsset) {
            uint256 flashBorrowedAssetAfter = IERC20(borrowedAsset).balanceOf(
                address(this)
            );
            variables.diffFlashBorrowedBalance =
                flashBorrowedAssetAfter -
                variables.borrowedAssetLeftovers;
            uint256 amountOut = variables.flashLoanDebt -
                variables.diffFlashBorrowedBalance;

            // if collateral asset is hAsset => get wich asset it is => withdraw this asset from hanji vault => This underlying asset is the collateral asset now.

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

            // Check for tokens to transfer to contract owner
            variables.remainingTokens =
                variables.diffCollateralBalance -
                variables.soldAmount;
        } else {
            variables.remainingTokens =
                variables.diffCollateralBalance -
                premium;
        }

        // Approve for flash loan repayment
        IERC20(borrowedAsset).approve(address(POOL), variables.flashLoanDebt);
    }

    /**
     * @notice executeLiquidation func initialize a flashLoanSimple and passes the parameters needed to liquidate a position than transfers the collateral received to the owner of contract
     * @param tokenAddress -> address of flash loaned token
     * @param _amount -> amount of flash loaned token
     * @param colToken -> address of collateral token received from liquidating the position
     * @param user -> address of the user whose position is being liquidated
     * @param poolFee1 -> fee associated with Pool
     * @param poolFee2 -> fee associated with Pool
     * @param pathToken -> token needed to be swap between tokens
     * @param usePath -> bool to decide between single and multihop swap
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

        // Init flashLoanSimple
        POOL.flashLoanSimple(
            receiverAddress,
            asset,
            amount,
            params,
            referralCode
        );

        // Transfering remaining collateral token after liquidation with flashloan being repaid
        DataTypes.LiquidationParams memory decodedParams = _decodeParams(
            params
        );

        // Transfer remaining debt and collateral to msg.sender
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
