// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "./interfaces/IPool.sol";
import {IPoolDeployer} from "./interfaces/IPoolDeployer.sol";
import {Pool} from "./Pool.sol";

contract PoolDeployer is IPoolDeployer {
    /// @dev Temporary parameters accessible by deployed Pool in its constructor
    Parameters public _parameters;

    /// @notice Deploys a new Pool contract
    /// @param _token0 The first token in the pair
    /// @param _token1 The second token
    /// @param _fee The fee for this pool
    /// @param _factory The factory deploying it
    function deploy(
        address _token0,
        address _token1,
        uint24 _fee,
        address _factory,
        int24 _tickSpacing,
        address _protocolFees,
        address _emergencyPause
    ) internal returns (address pool) {
        _parameters =
            Parameters({token0: _token0, token1: _token1, fee: _fee, factory: _factory, tickSpacing: _tickSpacing});

        pool = address(new Pool{salt: keccak256(abi.encode(_token0, _token1, _fee))}(_protocolFees, _emergencyPause));

        delete _parameters;
    }

    /// @inheritdoc IPoolDeployer
    function parameters()
        external
        view
        override
        returns (address factory, address token0, address token1, uint24 fee, int24 tickSpacing)
    {
        factory = _parameters.factory;
        token0 = _parameters.token0;
        token1 = _parameters.token1;
        fee = _parameters.fee;
        tickSpacing = _parameters.tickSpacing;
    }
}
