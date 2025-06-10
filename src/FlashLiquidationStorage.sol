// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "./dependencies/iguana/ISwapRouter.sol";

contract FlashLiquidationStorage {
    ISwapRouter private _swapRouter;
    mapping(address => address) private _hAssetToVault;

    constructor(ISwapRouter __swapRouter) {
        _setSwapRouter(__swapRouter);
    }

    function _setSwapRouter(ISwapRouter __swapRouter) internal {
        _swapRouter = __swapRouter;
    }

    function _setHAssetToVault(address hAsset, address vault) internal {
        _hAssetToVault[hAsset] = vault;
    }

    function swapRouter() public view returns (ISwapRouter) {
        return _swapRouter;
    }

    function hAssetToVault(address hAsset) public view returns (address) {
        return _hAssetToVault[hAsset];
    }
}
