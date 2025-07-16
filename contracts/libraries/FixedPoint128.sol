// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  FixedPoint128
/// @notice Contains the Q128.128 fixed point constant used in Uniswap V3
library FixedPoint128 {
    /// @dev 2^128 = 340282366920938463463374607431768211456
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
}
