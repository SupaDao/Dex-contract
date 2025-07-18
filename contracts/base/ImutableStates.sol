// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IImmutableState} from "../interfaces/IImmutableState.sol";

abstract contract ImutableState is IImmutableState {
    address public immutable override factory;
    address public immutable override WETH9;

    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
    }
}
