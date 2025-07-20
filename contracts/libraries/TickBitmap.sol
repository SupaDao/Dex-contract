// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title TickBitmap
/// @notice Efficient mapping and navigation of initialized ticks using bit-level operations
library TickBitmap {
    /// @notice Returns the position of a tick in the bitmap (word and bit positions)
    function position(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8); // Divide by 256
        bitPos = uint8(uint24(tick % 256)); // Mod 256
    }

    /// @notice Flips the bit at a given tick position (toggle initialize/uninitialize)
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        require(tick % tickSpacing == 0); // ensure that the tick is spaced
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    /// @notice Returns true if the tick is initialized (bit is set)
    function isInitialized(mapping(int16 => uint256) storage self, int24 tick) internal view returns (bool) {
        (int16 wordPos, uint8 bitPos) = position(tick);
        return (self[wordPos] & (1 << bitPos)) != 0;
    }

    /// @notice Finds the next initialized tick within one word in the given direction
    /// @dev Assumes that `tick` is a multiple of tick spacing
    /// @param tick The current tick
    /// @param lte Whether to search for a tick <= the current tick (or > if false)
    /// @param tickSpacing The spacing between initialized ticks
    /// @return next The next initialized tick
    /// @return initialized Whether the tick is initialized
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;
        (int16 wordPos, uint8 bitPos) = position(compressed);

        uint256 mask;
        uint256 word = self[wordPos];

        if (lte) {
            // Search left
            mask = (1 << bitPos) - 1 | (1 << bitPos);
            uint256 masked = word & mask;

            initialized = masked != 0;
            if (initialized) {
                uint8 msb = _mostSignificantBit(masked);
                next = (int24(wordPos) << 8 | int24(int8(msb))) * tickSpacing;
            } else {
                next = (int24(wordPos) << 8 | 0) * tickSpacing;
            }
        } else {
            // Search right
            mask = ~((1 << (bitPos + 1)) - 1);
            uint256 masked = word & mask;

            initialized = masked != 0;
            if (initialized) {
                uint8 lsb = _leastSignificantBit(masked);
                next = (int24(wordPos) << 8 | int24(int8(lsb))) * tickSpacing;
            } else {
                next = (int24(wordPos + 1) << 8) * tickSpacing;
            }
        }
    }

    /// @notice Returns index of the least significant set bit (bit scan forward)
    function _leastSignificantBit(uint256 x) private pure returns (uint8 r) {
        require(x > 0);
        r = 0;
        while ((x & 1) == 0) {
            x >>= 1;
            r++;
        }
    }

    /// @notice Returns index of the most significant set bit (bit scan reverse)
    function _mostSignificantBit(uint256 x) private pure returns (uint8 r) {
        require(x > 0);
        for (uint8 i = 255; i > 0; i--) {
            if ((x >> i) & 1 == 1) {
                r = i;
                break;
            }
        }
        if (x & 1 == 1 && r == 0) {
            r = 0;
        }
    }
} // end TickBitmap
