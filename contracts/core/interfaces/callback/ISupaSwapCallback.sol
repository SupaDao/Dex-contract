// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Callback interface to be implemented by swap initiators
interface ISupaSwapCallback {
    function supaSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}
