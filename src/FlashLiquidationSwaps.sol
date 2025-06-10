// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "./dependencies/ISwapRouter.sol";
import {TransferHelper} from "./dependencies/TransferHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract FlashLiquidationSwaps {
    ISwapRouter public immutable swapRouter;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = ISwapRouter(_swapRouter);
    }

    /**
     * @notice This function swaps a minimum possible amount of DAI for fixed amount WETH
     * @dev Calling address must approve this contract to spend DAI for this function to succeed will need to approve for slightly higher amount
     * @param amountOut -> exact amount of WETH to receive from the swap
     * @param amountInMaximum -> amount of DAI we want to spend to receive the specified amount of WETH
     * @return amountIn -> amount of DAI accualy spent in swap
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
