// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "./dependencies/iguana/ISwapRouter.sol";

/**
 * @title FlashLiquidationStorage
 * @notice Storage contract for flash liquidation system
 * @dev Manages storage for swap router and hAsset vault mappings
 */
abstract contract FlashLiquidationStorage {
    ISwapRouter private _swapRouter;
    mapping(address => address) private _hAssetToVault;

    constructor(ISwapRouter __swapRouter) {
        _swapRouter = __swapRouter;
    }

    /**
     * @notice Returns the current swap router address
     * @return The address of the swap router
     */
    function swapRouter() public view returns (ISwapRouter) {
        return _swapRouter;
    }

    /**
     * @notice Returns the vault address for a given hAsset
     * @param hAsset The address of the hAsset
     * @return The address of the associated vault
     */
    function hAssetToVault(address hAsset) public view returns (address) {
        return _hAssetToVault[hAsset];
    }

    /**
     * @notice Internal function to set the swap router
     * @param __swapRouter The new swap router address
     */
    function _setSwapRouter(ISwapRouter __swapRouter) internal {
        _swapRouter = __swapRouter;
    }

    /**
     * @notice Internal function to set the vault address for an hAsset
     * @param hAsset The address of the hAsset
     * @param vault The address of the vault
     */
    function _setHAssetToVault(address hAsset, address vault) internal {
        _hAssetToVault[hAsset] = vault;
    }
}
