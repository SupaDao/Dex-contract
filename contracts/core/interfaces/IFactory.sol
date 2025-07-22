// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFactory {
    event PoolCreated(address indexed _token0, address indexed _token1, uint24 _fee, address _pool);
    event FeeEnabled(uint24 indexed fee, int24 indexed tickSpacing);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    function getPool(address _tokenA, address _tokenB, uint24 _fee) external view returns (address pool);
    function createPool(address _tokenA, address _tokenB, uint24 _fee) external returns (address pool);
    function enableFeeTier(uint24 fee, int24 tickSpacing) external;
    function feeToTickSpacing(uint24 fee) external view returns (int24 tickSpacing);
    function owner() external view returns (address);
    function setOwner(address _owner) external;
}
