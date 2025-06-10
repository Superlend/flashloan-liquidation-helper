// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "./dependencies/iguana/ISwapRouter.sol";
import {TransferHelper} from "./dependencies/iguana/TransferHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FlashLiquidationStorage} from "./FlashLiquidationStorage.sol";
import {ILPManager} from "./dependencies/hanji/ILPManager.sol";

/**
 * @title FlashLiquidationSwaps
 * @notice Abstract contract handling token swaps and hAsset operations for liquidation
 * @dev Provides functionality to execute both single-hop and multi-hop swaps using Uniswap V3
 * Includes support for handling hAssets (Hanji protocol assets) through vault interactions
 */
abstract contract FlashLiquidationSwaps is FlashLiquidationStorage {
    constructor(
        ISwapRouter __swapRouter
    ) FlashLiquidationStorage(__swapRouter) {}

    /**
     * @notice Executes a token swap with exact output amount
     * @dev Supports both single-hop and multi-hop swaps through Uniswap V3
     * @param tokenIn The address of the input token
     * @param tokenOut The address of the output token
     * @param amountOut The exact amount of output tokens to receive
     * @param amountInMaximum The maximum amount of input tokens to spend
     * @param poolFee1 The fee tier for the first pool in the swap path
     * @param poolFee2 The fee tier for the second pool in the swap path (if using multi-hop)
     * @param pathToken The intermediate token for multi-hop swaps
     * @param usePath Whether to use a multi-hop swap path
     * @return amountIn The actual amount of input tokens spent in the swap
     */
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint24 poolFee1,
        uint24 poolFee2,
        address pathToken,
        bool usePath
    ) internal returns (uint256 amountIn) {
        TransferHelper.safeApprove(
            tokenIn,
            address(swapRouter()),
            amountInMaximum
        );
        require(
            IERC20(tokenIn).allowance(address(this), address(swapRouter())) ==
                amountInMaximum,
            "FlashLiquidations: error while approving"
        );

        if (usePath == false) {
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
                .ExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: poolFee1,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: amountInMaximum,
                    sqrtPriceLimitX96: 0
                });

            amountIn = swapRouter().exactOutputSingle(params);
        } else {
            ISwapRouter.ExactOutputParams memory params = ISwapRouter
                .ExactOutputParams({
                    path: abi.encodePacked(
                        tokenOut,
                        poolFee2,
                        pathToken,
                        poolFee1,
                        tokenIn
                    ),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: amountInMaximum
                });

            amountIn = swapRouter().exactOutput(params);
        }

        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter()), 0);
        }

        return amountIn;
    }

    /**
     * @notice Validates if an asset is an hAsset and retrieves its underlying token address
     * @dev Checks if the asset has an associated vault and retrieves token information
     * @param collateral The address of the collateral asset to validate
     * @return The underlying token address and token ID if it's an hAsset, otherwise returns the original address
     */
    function _validateHAssetAndGetTokenAddress(
        address collateral
    ) internal view returns (address, uint8) {
        address vault = hAssetToVault(collateral);
        if (vault != address(0)) {
            ILPManager.TokenInfo memory tokenInfo = ILPManager(vault).tokens(0);
            return (tokenInfo.tokenAddress, 0);
        }
        return (collateral, 0);
    }

    /**
     * @notice Validates and withdraws hAssets from their respective vaults
     * @dev If the collateral is an hAsset, withdraws liquidity from the Hanji vault
     * @param collateral The address of the collateral asset
     * @param amount The amount of collateral to process
     * @return The underlying token address and the amount after withdrawal (if applicable)
     */
    function _validateAndWithdrawHAsset(
        address collateral,
        uint256 amount
    ) internal returns (address, uint256) {
        (
            address tokenAddress,
            uint8 tokenId
        ) = _validateHAssetAndGetTokenAddress(collateral);
        address vault = hAssetToVault(collateral);

        if (tokenAddress != collateral) {
            TransferHelper.safeApprove(collateral, vault, amount);

            uint256 removedAmount = ILPManager(vault).removeLiquidity(
                tokenId,
                amount,
                0,
                0,
                block.timestamp,
                new bytes[](0)
            );

            return (tokenAddress, removedAmount);
        } else {
            return (collateral, amount);
        }
    }
}
