// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFactory} from "./interfaces/IFactory.sol";
import {PoolDeployer} from "./PoolDeployer.sol";

/// @title  Factory
/// @notice Deploys and tracks pools for SupaDAO DEX

contract Factory is IFactory {
    /// @dev PoolDeployer address must be passed in constructor
    address public immutable poolDeployer;

    ///@dev custom error;
    error IdenticalTokens();
    error ZeroAddress();
    error ExistingPool();

    /// @dev token0 => token1 => fee => pool address
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    constructor(address _poolDeployer) {
        poolDeployer = _poolDeployer;
    }

    function createPool(address _tokenA, address _tokenB, uint24 _fee) external returns (address pool) {
        if (_tokenA == _tokenB) revert IdenticalTokens();
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPool[token0][token1][_fee] != address(0)) revert ExistingPool();
        pool = PoolDeployer(poolDeployer).deploy(token0, token1, _fee, address(this));
        getPool[token0][token1][_fee] = pool;
        getPool[token1][token0][_fee] = pool;

        emit PoolCreated(token0, token1, _fee, pool);
    }
}
