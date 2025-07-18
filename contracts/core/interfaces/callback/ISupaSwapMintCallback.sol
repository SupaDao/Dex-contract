// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISupaSwapMintCallback {
    function supaSwapMintCallback(uint256 amount0Delta, uint256 amount1Delta, bytes calldata data) external;
}
