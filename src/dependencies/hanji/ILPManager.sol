// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILPManager {
    struct TokenInfo {
        address tokenAddress;
        bool isActive;
        uint16 targetWeight;
        uint16 lowerBoundWeight;
        uint16 upperBoundWeight;
        uint8 decimals;
        uint24 oracleConfRel;
        bytes32 oraclePriceId;
    }

    function removeLiquidity(
        uint8 tokenId,
        uint256 burnLP,
        uint256 minUsdValue,
        uint256 minTokenGet,
        uint256 expires,
        bytes[] calldata priceUpdateData
    ) external payable returns (uint256);

    function addLiquidity(
        uint8 tokenId,
        uint256 amount,
        uint256 minUsdValue,
        uint256 minLPMinted,
        uint256 expires,
        bytes[] calldata priceUpdateData
    ) external returns (uint256);

    function tokens(uint256 tokenId) external view returns (TokenInfo memory);
}
