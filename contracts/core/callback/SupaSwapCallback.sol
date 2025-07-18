// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISupaSwapCallback} from "../interfaces/callback/ISupaSwapCallback.sol";

/// @notice This contract handles mint and swap callbacks from SupaDEX pools
/// It should be inherited or used by routers, strategy contracts, etc.
abstract contract SupaSwapCallback is ISupaSwapCallback {
    address public immutable token0;
    address public immutable token1;
    address public immutable pool;

    constructor(address _token0, address _token1, address _pool) {
        token0 = _token0;
        token1 = _token1;
        pool = _pool;
    }

    /// @notice Called during swap() to supply only the input token to the pool
    function supaSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        require(msg.sender == pool, "SupaSwapCallback: unauthorized");

        if (amount0Delta > 0) {
            IERC20(token0).transfer(msg.sender, uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            IERC20(token1).transfer(msg.sender, uint256(amount1Delta));
        }
    }
}
