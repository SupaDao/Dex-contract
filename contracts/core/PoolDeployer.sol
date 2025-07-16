// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "./interfaces/IPool.sol";
import {Pool} from "./Pool.sol";

contract PoolDeployer {
    /// @notice Structs
    struct Parameters {
        address token0;
        address token1;
        uint24 fee;
        address factory;
    }

    /// @dev Temporary parameters accessible by deployed Pool in its constructor
    Parameters public parameters;

    /// @notice Deploys a new Pool contract
    /// @param _token0 The first token in the pair
    /// @param _token1 The second token
    /// @param _fee The fee for this pool
    /// @param _factory The factory deploying it
    function deploy(address _token0, address _token1, uint24 _fee, address _factory) external returns (address pool) {
        parameters = Parameters({token0: _token0, token1: _token1, fee: _fee, factory: _factory});

        pool = address(new Pool{salt: keccak256(abi.encode(_token0, _token1, _fee))}());

        delete parameters;
    }
}
