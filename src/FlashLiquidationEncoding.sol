// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "./DataTypes.sol";

/**
 * @title FlashLiquidationEncoding
 * @notice Abstract contract handling parameter encoding and decoding for flash loan operations
 * @dev Provides functionality to encode liquidation parameters for flash loan callbacks and decode them back
 */
abstract contract FlashLiquidationEncoding {
    /**
     * @notice Encodes liquidation parameters into bytes for flash loan callback
     * @dev Used to pass liquidation parameters through the flash loan callback
     * @param collateralAsset The address of the collateral asset
     * @param borrowedAsset The address of the borrowed asset
     * @param user The address of the user to liquidate
     * @param amount The amount of debt to cover
     * @param poolFee1 The fee tier for the first pool in the swap path
     * @param poolFee2 The fee tier for the second pool in the swap path
     * @param pathToken The intermediate token for multi-hop swaps
     * @param usePath Whether to use a multi-hop swap path
     * @return bytes The encoded parameters
     */
    function _encodeParams(
        address collateralAsset,
        address borrowedAsset,
        address user,
        uint256 amount,
        uint24 poolFee1,
        uint24 poolFee2,
        address pathToken,
        bool usePath
    ) internal pure returns (bytes memory) {
        bytes memory params = abi.encode(
            collateralAsset,
            borrowedAsset,
            user,
            amount,
            poolFee1,
            poolFee2,
            pathToken,
            usePath
        );

        return params;
    }

    /**
     * @notice Decodes the parameters from the flash loan callback
     * @dev Converts the encoded bytes back into a LiquidationParams struct
     * @param params The encoded parameters from the flash loan callback
     * @return LiquidationParams The decoded parameters struct
     */
    function _decodeParams(
        bytes memory params
    ) internal pure returns (DataTypes.LiquidationParams memory) {
        (
            address collateralAsset,
            address borrowedAsset,
            address user,
            uint256 debtToCover,
            uint24 poolFee1,
            uint24 poolFee2,
            address pathToken,
            bool usePath
        ) = abi.decode(
                params,
                (
                    address,
                    address,
                    address,
                    uint256,
                    uint24,
                    uint24,
                    address,
                    bool
                )
            );

        return
            DataTypes.LiquidationParams(
                collateralAsset,
                borrowedAsset,
                user,
                debtToCover,
                poolFee1,
                poolFee2,
                pathToken,
                usePath
            );
    }
}
