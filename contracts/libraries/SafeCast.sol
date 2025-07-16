// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  SafeCast
/// @notice Wrappers over Solidity’s built‑in casting operators that revert on overflow.
/// @dev    Only the widths actually used in a V3‑style DEX are included. Add more as needed.
library SafeCast {
    /// @notice Custom Errors for better gas optimizations
    error UintOverFlow();
    error IntOverFlow();
    error UintUnderFlow();

    function toUint160(uint256 _x) internal pure returns (uint160 y) {
        if (_x > type(uint160).max) revert UintOverFlow();
        y = uint160(_x);
    }

    function toUint128(uint256 _x) internal pure returns (uint128 y) {
        if (_x > type(uint128).max) revert UintOverFlow();
        y = uint128(_x);
    }

    function toUint96(uint256 _x) internal pure returns (uint96 y) {
        if (_x > type(uint96).max) revert UintOverFlow();
        y = uint96(_x);
    }

    function toUint32(uint256 _x) internal pure returns (uint32 y) {
        if (_x > type(uint32).max) revert UintOverFlow();
        y = uint32(_x);
    }

    function toInt24(int256 _x) internal pure returns (int24 y) {
        if (_x < type(int24).min || _x > type(int24).max) revert IntOverFlow();
        y = int24(_x);
    }

    function toInt128(int256 _x) internal pure returns (int128 y) {
        if (_x < type(int128).min || _x > type(int128).max) revert IntOverFlow();
        y = int128(_x);
    }

    /// @notice Casts uint256 to int256, reverting if the value > int256.max
    function toInt256(uint256 _x) internal pure returns (int256 y) {
        if (_x > uint256(type(int256).max)) revert IntOverFlow();
        y = int256(_x);
    }

    /// @notice Casts int256 to uint256, reverting if x < 0
    function toUint256(int256 _x) internal pure returns (uint256 y) {
        if (_x < 0) revert UintUnderFlow();
        y = uint256(_x);
    }
}
