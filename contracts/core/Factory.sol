// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFactory} from "./interfaces/IFactory.sol";
import {PoolDeployer} from "./PoolDeployer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title  Factory
/// @notice Deploys and tracks pools for SupaDAO DEX

contract Factory is IFactory, Ownable {
    /// @dev PoolDeployer address must be passed in constructor
    address public immutable poolDeployer;

    address[] public allPools;

    ///@dev custom error;
    error IdenticalTokens();
    error ZeroAddress();
    error ExistingPool();
    error FeeEnabled();
    error InvalidSpacing();

    /// @dev token0 => token1 => fee => pool address
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    mapping(uint24 => int24) public feeToTickSpacing;

    constructor(address _poolDeployer) Ownable(msg.sender) {
        poolDeployer = _poolDeployer;
    }

    /// @notice Sets tick spacing for a fee tier
    function enableFeeTier(uint24 fee, int24 tickSpacing) external onlyOwner {
        // Add proper access control here (e.g., onlyOwner)
        if (feeToTickSpacing[fee] != 0) revert FeeEnabled();
        if (tickSpacing < 0 || tickSpacing > 16384) revert InvalidSpacing();
        feeToTickSpacing[fee] = tickSpacing;
    }

    function createPool(address _tokenA, address _tokenB, uint24 _fee) external returns (address pool) {
        if (_tokenA == _tokenB) revert IdenticalTokens();
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPool[token0][token1][_fee] != address(0)) revert ExistingPool();
        int24 tickSpacing = feeToTickSpacing[_fee];
        pool = PoolDeployer(poolDeployer).deploy(token0, token1, _fee, address(this), tickSpacing);
        getPool[token0][token1][_fee] = pool;
        getPool[token1][token0][_fee] = pool;
        allPools.push(pool);

        emit PoolCreated(token0, token1, _fee, pool);
    }
}
