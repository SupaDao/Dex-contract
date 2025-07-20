// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISupaSwapFlashCallback {
    /// @notice Called during a flash loan to pay back the borrowed amount plus fees
    /// @param amount0Delta The amount of token0 borrowed (can be negative if pool owes)
    /// @param amount1Delta The amount of token1 borrowed (can be negative if pool owes)
    /// @param data Additional data passed to the callback
    function supaSwapFlashCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}
