// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IPoolConfigurator} from "@aave/contracts/interfaces/IPoolConfigurator.sol";
import {ISwapRouter} from "../src/dependencies/iguana/ISwapRouter.sol";
import {IERC20} from "@aave/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IAaveOracle} from "@aave/contracts/interfaces/IAaveOracle.sol";
import {FlashLiquidations} from "../src/flashLiquidations.sol";
import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import {ConfiguratorInputTypes} from "@aave/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import {ILPManager} from "../src/dependencies/hanji/ILPManager.sol";

abstract contract TestBase is Test {
    FlashLiquidations public liquidation;
    IPoolAddressesProvider public constant AAVE_ADDRESSES_PROVIDER =
        IPoolAddressesProvider(0x5ccF60c7E10547c5389E9cBFf543E5D0Db9F4feC);
    IAaveOracle public constant AAVE_ORACLE =
        IAaveOracle(0xeCF313dE38aA85EF618D06D1A602bAa917D62525);
    IPoolConfigurator public constant POOL_CONFIGURATOR =
        IPoolConfigurator(0x30F6880Bb1cF780a49eB4Ef64E64585780AAe060);
    ISwapRouter public constant SWAP_ROUTER =
        ISwapRouter(0xE67B7D039b78DE25367EF5E69596075Bbd852BA9);
    IERC20 public constant USDC =
        IERC20(0x796Ea11Fa2dD751eD01b53C372fFDB4AAa8f00F9);
    IERC20 public constant WETH =
        IERC20(0xfc24f770F94edBca6D6f885E12d4317320BcB401);
    IERC20 public constant WXTZ =
        IERC20(0xc9B53AB2679f573e480d01e0f49e2B5CFB7a3EAb);
    IPool public constant POOL =
        IPool(0x3bD16D195786fb2F509f2E2D7F69920262EF114D);

    address public user = makeAddr("user");
    address public hWXTZ = 0x1BeD8FC148864Fec86eb18472f36093350770Bd6;
    address public wXTZVault = 0x4f2210992209Ad0aB0c8644547Bf0379B96Ed1F4;
    ILPManager public constant LP_MANAGER =
        ILPManager(0x4f2210992209Ad0aB0c8644547Bf0379B96Ed1F4);
    address public admin = 0x669bd328f6C494949Ed9fB2dc8021557A6Dd005f;
    uint256 public mainnetFork;

    function setUp() public virtual {
        mainnetFork = vm.createFork("https://node.mainnet.etherlink.com");
        vm.selectFork(mainnetFork);

        liquidation = new FlashLiquidations(
            AAVE_ADDRESSES_PROVIDER,
            SWAP_ROUTER
        );

        liquidation.setHAssetToVault(hWXTZ, wXTZVault);

        ConfiguratorInputTypes.InitReserveInput[]
            memory input = new ConfiguratorInputTypes.InitReserveInput[](1);
        input[0] = ConfiguratorInputTypes.InitReserveInput({
            aTokenImpl: 0x27325bFfA20C818B2DA8bC595Fa1529EB16B9276,
            stableDebtTokenImpl: 0xd7C0eE879125Ee8ee12706B25F5A8D2C61F6eF79,
            variableDebtTokenImpl: 0x281a30fF8531E34B0DB84DeA273fb63e285DA6D9,
            underlyingAssetDecimals: 18,
            interestRateStrategyAddress: 0xC731CcacC0B42800765832887627b1dD7Be85a63,
            underlyingAsset: hWXTZ,
            treasury: admin,
            incentivesController: 0xd938be2C5797E8D275ABf2Eff7465785792B26AA,
            aTokenName: "Superlend hWXTZ",
            aTokenSymbol: "slhWXTZ",
            variableDebtTokenName: "Superlend hWXTZ Variable Debt",
            variableDebtTokenSymbol: "svWXTZ",
            stableDebtTokenName: "Superlend hWXTZ Stable Debt",
            stableDebtTokenSymbol: "ssWXTZ",
            params: ""
        });

        vm.startPrank(admin);
        // init hAsset
        POOL_CONFIGURATOR.initReserves(input);

        // configure reserve as collateral
        POOL_CONFIGURATOR.configureReserveAsCollateral(
            hWXTZ,
            7000,
            7500,
            10500
        );

        address[] memory assets = new address[](1);
        assets[0] = hWXTZ;
        address[] memory sources = new address[](1);
        sources[0] = 0x202f479AB9848c36bA731A342320ff4Bd01dF229;
        AAVE_ORACLE.setAssetSources(assets, sources);

        // set supply cap
        POOL_CONFIGURATOR.setSupplyCap(hWXTZ, 1000);
        vm.stopPrank();
    }
}
