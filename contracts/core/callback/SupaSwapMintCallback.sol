// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISupaSwapMintCallback} from "../interfaces/callback/ISupaSwapMintCallback.sol";

/// @notice This contract handles mint and swap callbacks from SupaDEX pools
/// It should be inherited or used by routers, strategy contracts, etc.
abstract contract SupaSwapMintCallback is ISupaSwapMintCallback {
    address public immutable pool;

    constructor(address _pool) {
        pool = _pool;
    }

    /// @notice Called during mint() to supply token0 and token1 to the pool
    function supaSwapMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        require(msg.sender == pool, "SupaSwapCallback: unauthorized");

        (address token0, address token1) = abi.decode(data, (address, address));

        if (amount0Owed > 0) {
            IERC20(token0).transfer(msg.sender, amount0Owed);
        }

        if (amount1Owed > 0) {
            IERC20(token1).transfer(msg.sender, amount1Owed);
        }
    }
}
