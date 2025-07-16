// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BitMath
/// @notice Efficient bit-level utilities to find MSB/LSB in uints

library BitMath {
    error ZeroInput();

    /// @notice Returns the index of the most significant bit (highest set bit)
    /// @dev Reverts if x == 0
    function mostSignificantBit(uint256 _x) internal pure returns (uint8 r) {
        if (_x == 0) revert ZeroInput();

        assembly {
            let msb := 0
            if gt(_x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
                _x := shr(128, _x)
                msb := add(msb, 128)
            }
            if gt(_x, 0xFFFFFFFFFFFFFFFF) {
                _x := shr(64, _x)
                msb := add(msb, 64)
            }
            if gt(_x, 0xFFFFFFFF) {
                _x := shr(32, _x)
                msb := add(msb, 32)
            }
            if gt(_x, 0xFFFF) {
                _x := shr(16, _x)
                msb := add(msb, 16)
            }
            if gt(_x, 0xFF) {
                _x := shr(8, _x)
                msb := add(msb, 8)
            }
            if gt(_x, 0xF) {
                _x := shr(4, _x)
                msb := add(msb, 4)
            }
            if gt(_x, 0x3) {
                _x := shr(2, _x)
                msb := add(msb, 2)
            }
            if gt(_x, 0x1) { msb := add(msb, 1) }
            r := msb
        }
    }

    /// @notice Returns the index of the least significant bit (lowest set bit)
    /// @dev Reverts if x == 0
    function leastSignificantBit(uint256 _x) internal pure returns (uint8 r) {
        if (_x == 0) revert ZeroInput();

        assembly {
            let lsb := 0
            if iszero(and(_x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) {
                _x := shr(128, _x)
                lsb := add(lsb, 128)
            }
            if iszero(and(_x, 0xFFFFFFFFFFFFFFFF)) {
                _x := shr(64, _x)
                lsb := add(lsb, 64)
            }
            if iszero(and(_x, 0xFFFFFFFF)) {
                _x := shr(32, _x)
                lsb := add(lsb, 32)
            }
            if iszero(and(_x, 0xFFFF)) {
                _x := shr(16, _x)
                lsb := add(lsb, 16)
            }
            if iszero(and(_x, 0xFF)) {
                _x := shr(8, _x)
                lsb := add(lsb, 8)
            }
            if iszero(and(_x, 0xF)) {
                _x := shr(4, _x)
                lsb := add(lsb, 4)
            }
            if iszero(and(_x, 0x3)) {
                _x := shr(2, _x)
                lsb := add(lsb, 2)
            }
            if iszero(and(_x, 0x1)) { lsb := add(lsb, 1) }
            r := lsb
        }
    }
}
