// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISupaSwapFlashCallback} from "../interfaces/callback/ISupaSwapFlashCallback.sol";

abstract contract SupaSwapFlashCallback is ISupaSwapFlashCallback {
    address public immutable pool;

    constructor(address _pool) {
        pool = _pool;
    }

    /// @notice Called during swap() to supply only the input token to the pool
    function supaSwapFlashCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(msg.sender == pool, "Unauthorized callback");
        (address tokenIn, address tokenOut) = abi.decode(data, (address, address));

        // Determine which token to pay and the amount
        // Positive delta means the contract owes the pool, negative means the pool owes the contract
        if (amount0Delta > 0) {
            IERC20(tokenIn).transfer(pool, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(tokenOut).transfer(pool, uint256(amount1Delta));
        }
    }
}
