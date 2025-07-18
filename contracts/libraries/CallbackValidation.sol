// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "../core/interfaces/IPool.sol";
import {PoolAddress} from "./PoolAddress.sol";

library CallbackValidation {
    /// @notice Returns the address of a valid Uniswap V3 Pool
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @return pool The V3 pool contract address
    function verifyCallback(address factory, address tokenA, address tokenB, uint24 fee)
        internal
        view
        returns (IPool pool)
    {
        return verifyCallback(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee));
    }

    /// @notice Returns the address of a valid Uniswap V3 Pool
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param poolKey The identifying key of the V3 pool
    /// @return pool The V3 pool contract address
    function verifyCallback(address factory, PoolAddress.PoolKey memory poolKey) internal view returns (IPool pool) {
        pool = IPool(PoolAddress.computeAddress(factory, poolKey.token0, poolKey.token1, poolKey.fee));
        require(msg.sender == address(pool));
    }
}
