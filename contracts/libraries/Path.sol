// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BytesLib} from "./BytesLib.sol";

library Path {
    using BytesLib for bytes;
    /// @dev Path is encoded as: tokenA (20 bytes) + fee (3 bytes) + tokenB (20 bytes) [+ fee + tokenC + ...]

    uint256 private constant ADDR_SIZE = 20;
    uint256 private constant FEE_SIZE = 3;
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + FEE_SIZE;
    uint256 private constant POP_OFFSET = NEXT_OFFSET;
    uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET;

    /// @notice Returns true if the path contains multiple pools
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
    }

    /// @notice Decodes the first pool in path
    function decodeFirstPool(bytes memory path) internal pure returns (address tokenA, address tokenB, uint24 fee) {
        tokenA = path.toAddress(0);
        fee = path.toUint24(ADDR_SIZE);
        tokenB = path.toAddress(NEXT_OFFSET);
    }

    function getFirstToken(bytes memory path) internal pure returns (address) {
        return path.toAddress(0);
    }

    function getSecondToken(bytes memory path) internal pure returns (address) {
        return path.toAddress(NEXT_OFFSET);
    }

    function getFee(bytes memory path) internal pure returns (uint24) {
        return path.toUint24(ADDR_SIZE);
    }

    /// @notice Skips the first pool in the path and returns the rest
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(NEXT_OFFSET, path.length - NEXT_OFFSET);
    }

    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(0, POP_OFFSET);
    }

    /// @notice Returns the number of pools in the path
    function numPools(bytes memory path) internal pure returns (uint256) {
        return (path.length - ADDR_SIZE) / NEXT_OFFSET;
    }

    function decodeLastPool(bytes memory path) internal pure returns (address tokenOut, address tokenIn, uint24 fee) {
        require(path.length >= 43, "Path too short");
        uint256 len = path.length;
        assembly {
            tokenIn := shr(96, mload(add(path, sub(len, 20))))
            fee := shr(232, mload(add(path, sub(len, 23))))
            tokenOut := shr(96, mload(add(path, sub(len, 43))))
        }
    }

    function skipLastToken(bytes memory path) internal pure returns (bytes memory result) {
        require(path.length >= 43, "skipLastToken: invalid path length");

        uint256 newLength = path.length - 23;

        assembly {
            // Allocate memory for the result
            result := mload(0x40)
            // Set length of new bytes array
            mstore(result, newLength)

            // Calculate the start of data (path + 32)
            let src := add(path, 32)
            let dst := add(result, 32)

            // Copy 32-byte chunks
            for { let i := 0 } lt(i, newLength) { i := add(i, 32) } { mstore(add(dst, i), mload(add(src, i))) }

            // Update free memory pointer
            mstore(0x40, add(dst, and(add(newLength, 31), not(31))))
        }
    }
}
