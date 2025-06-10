// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FlashLiquidations} from "../src/flashLiquidations.sol";
import {TestBase} from "./TestBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AaveOracle} from "@aave/contracts/misc/AaveOracle.sol";

contract LiquidationTest is TestBase {
    function setUp() public override {
        super.setUp();

        // create a deposit position
        deal(address(WXTZ), user, 200 ether);

        vm.startPrank(user);
        // 1. deposit wxtz to vault
        WXTZ.approve(address(LP_MANAGER), type(uint256).max);
        uint256 tokensMinted = LP_MANAGER.addLiquidity(
            0,
            100 ether,
            0,
            0,
            block.timestamp,
            new bytes[](0)
        );

        vm.warp(block.timestamp + 35);

        // 2. supply hWXTZ to pool
        IERC20(hWXTZ).approve(address(POOL), type(uint256).max);
        POOL.supply(hWXTZ, tokensMinted, user, 0);
        POOL.borrow(address(USDC), 40 * 10 ** 6, 2, 0, user);
        vm.stopPrank();
    }

    function test_liquidation() public {
        (, , , , , uint256 healthFactorBefore) = POOL.getUserAccountData(user);
        console.log("Health factor before:", healthFactorBefore);

        // convert this position to unhealthy
        vm.mockCall(
            address(AAVE_ORACLE),
            abi.encodeWithSelector(
                AaveOracle.getAssetPrice.selector,
                address(hWXTZ)
            ),
            abi.encode(0.1 * 1e8) // 0.1$ per hWXTZ
        );

        // Check new health factor
        (, , , , , uint256 healthFactorAfter) = POOL.getUserAccountData(user);
        console.log("Health factor after:", healthFactorAfter);

        assertTrue(healthFactorAfter < 1e18, "Position should be liquidatable");

        // Execute flash loan liquidation
        uint256 debtToCover = 40 * 1e6;

        liquidation.executeLiquidation(
            address(USDC), // token to flash loan
            debtToCover, // amount to flash loan
            address(hWXTZ), // collateral token
            user, // user to liquidate
            500, // pool fee 1
            0, // pool fee 2
            address(WXTZ), // path token (not used in this case)
            false // use path
        );

        // Verify liquidation was successful
        (, , , , , uint256 healthFactorFinal) = POOL.getUserAccountData(user);
        console.log("Health factor after liquidation:", healthFactorFinal);

        // Check liquidator received collateral
        uint256 liquidatorWxtzBalance = WXTZ.balanceOf(address(this));
        console.log("Liquidator WXTZ balance:", liquidatorWxtzBalance);
        assertTrue(
            liquidatorWxtzBalance > 0,
            "Liquidator should have received WXTZ"
        );
    }
}
