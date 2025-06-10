// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DataTypes
 * @notice Library containing data structures used across the flash liquidation system
 * @dev Defines the core data structures for handling liquidation parameters and local variables
 */
library DataTypes {
    /**
     * @notice Parameters used for liquidation operations and fund transfers
     * @param collateralAsset The address of the collateral asset
     * @param borrowedAsset The address of the borrowed asset
     * @param user The address of the user to liquidate
     * @param debtToCover The amount of debt to cover
     * @param poolFee1 The fee tier for the first pool in the swap path
     * @param poolFee2 The fee tier for the second pool in the swap path
     * @param pathToken The intermediate token for multi-hop swaps
     * @param usePath Whether to use a multi-hop swap path
     */
    struct LiquidationParams {
        address collateralAsset;
        address borrowedAsset;
        address user;
        uint256 debtToCover;
        uint24 poolFee1;
        uint24 poolFee2;
        address pathToken;
        bool usePath;
    }

    /**
     * @notice Local variables used during liquidation and swap operations
     * @param initFlashBorrowedBalance Initial balance of flash-borrowed tokens
     * @param diffFlashBorrowedBalance Difference in flash-borrowed token balance
     * @param initCollateralBalance Initial balance of collateral tokens
     * @param diffCollateralBalance Difference in collateral token balance
     * @param flashLoanDebt Total amount to repay for flash loan (principal + premium)
     * @param soldAmount Amount of collateral tokens sold in swap
     * @param remainingTokens Remaining tokens after liquidation and swaps
     * @param borrowedAssetLeftovers Leftover borrowed tokens after liquidation
     */
    struct LiquidationCallLocalVars {
        uint256 initFlashBorrowedBalance;
        uint256 diffFlashBorrowedBalance;
        uint256 initCollateralBalance;
        uint256 diffCollateralBalance;
        uint256 flashLoanDebt;
        uint256 soldAmount;
        uint256 remainingTokens;
        uint256 borrowedAssetLeftovers;
    }
}
