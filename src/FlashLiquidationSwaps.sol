// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "./dependencies/ISwapRouter.sol";
import {TransferHelper} from "./dependencies/TransferHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FlashLiquidationSwaps
 * @notice Abstract contract handling token swaps for liquidation operations
 * @dev Provides functionality to execute both single-hop and multi-hop swaps using Uniswap V3
 */
abstract contract FlashLiquidationSwaps {
    ISwapRouter public immutable swapRouter;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = ISwapRouter(_swapRouter);
    }

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
            address(swapRouter),
            amountInMaximum
        );
        require(
            IERC20(tokenIn).allowance(address(this), address(swapRouter)) ==
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

            amountIn = swapRouter.exactOutputSingle(params);
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

            amountIn = swapRouter.exactOutput(params);
        }

        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
        }

        return amountIn;
    }
}
