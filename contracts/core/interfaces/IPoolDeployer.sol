// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Lightweight interface to read deployer parameters
interface IPoolDeployer {
    struct Parameters {
        address token0;
        address token1;
        uint24 fee;
        address factory;
        int24 tickSpacing;
    }

    function parameters() external view returns (Parameters memory);
}
