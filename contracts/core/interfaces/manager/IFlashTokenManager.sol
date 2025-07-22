// SPDX-License-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFlashTokenManager {
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;
    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        returns (uint128 amount0, uint128 amount1);
}
