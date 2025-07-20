// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFactory} from "./interfaces/IFactory.sol";
import {PoolDeployer} from "./PoolDeployer.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title  Factory
/// @notice Deploys and tracks pools for SupaDAO DEX

contract Factory is IFactory, Ownable, PoolDeployer, NoDelegateCall {
    address[] public allPools;

    ///@dev custom error;
    error IdenticalTokens();
    error ZeroAddress();
    error ExistingPool();
    error FeeAlreadyEnabled();
    error InvalidSpacing();
    error NotOwner();
    error FeeToHigh();

    /// @dev token0 => token1 => fee => pool address
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    mapping(uint24 => int24) public override feeToTickSpacing;

    constructor() Ownable(msg.sender) {
        // Initialize default fee tiers
        feeToTickSpacing[500] = 10;
        emit FeeEnabled(500, 10);
        feeToTickSpacing[3000] = 60;
        emit FeeEnabled(3000, 60);
        feeToTickSpacing[10000] = 200;
        emit FeeEnabled(10000, 200);
    }

    /// @notice Sets tick spacing for a fee tier
    function enableFeeTier(uint24 fee, int24 tickSpacing) external override onlyOwner {
        if (msg.sender != owner()) revert NotOwner();
        if (fee < 1 || fee > 1000000) revert FeeToHigh();
        // Add proper access control here (e.g., onlyOwner)
        if (feeToTickSpacing[fee] != 0) revert FeeAlreadyEnabled();
        if (tickSpacing < 0 || tickSpacing > 16384) revert InvalidSpacing();
        feeToTickSpacing[fee] = tickSpacing;
    }

    function createPool(address _tokenA, address _tokenB, uint24 _fee)
        external
        override
        noDelegateCall
        returns (address pool)
    {
        if (_tokenA == _tokenB) revert IdenticalTokens();
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPool[token0][token1][_fee] != address(0)) revert ExistingPool();
        int24 tickSpacing = feeToTickSpacing[_fee];
        pool = deploy(token0, token1, _fee, address(this), tickSpacing);
        getPool[token0][token1][_fee] = pool;
        getPool[token1][token0][_fee] = pool;
        allPools.push(pool);

        emit PoolCreated(token0, token1, _fee, pool);
    }

    function owner() public view virtual override(IFactory, Ownable) returns (address) {
        return super.owner();
    }
}
