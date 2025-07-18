// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFactory} from "../core/interfaces/IFactory.sol";
import {IPool} from "../core/interfaces/IPool.sol";

import {ImutableState} from "./ImutableStates.sol";
import {IPoolInitializer} from "../interfaces/IPoolInitializer.sol";

abstract contract PoolInitializer is IPoolInitializer, ImutableState {
    /// @inheritdoc IPoolInitializer
    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        override
        returns (address pool)
    {
        require(token0 < token1);
        pool = IFactory(factory).getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = IFactory(factory).createPool(token0, token1, fee);
            IPool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing,,,,,,) = IPool(pool).getSlot0();
            if (sqrtPriceX96Existing == 0) {
                IPool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}
