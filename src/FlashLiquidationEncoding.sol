// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "./DataTypes.sol";

abstract contract FlashLiquidationEncoding {
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
     * @notice This func decodes the params obtained from myFlashLoan function
     * @param params -> params encoded in bytes form passed when initialize the flashloan
     * @return LiquidationParams memory struct
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
