// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFactory {
    event PoolCreated(address indexed _token0, address indexed _token1, uint24 _fee, address _pool);

    function getPool(address _tokenA, address _tokenB, uint24 _fee) external view returns (address pool);
    function createPool(address _tokenA, address _tokenB, uint24 _fee) external returns (address pool);
}
