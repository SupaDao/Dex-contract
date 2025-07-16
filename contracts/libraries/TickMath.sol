// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  Tick ↔ sqrtPrice helper
/// @notice Math that converts between ticks and sqrtPriceX96 (Q64.96)
/// @dev    Ported from Uniswap V3 core; gas‑tight and branch‑balanced.

library TickMath {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick
    uint160 internal constant MIN_SQRT_RATIO = 4295128739; // getSqrtRatioAtTick(MIN_TICK)
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @notice Custom errors
    error InvalidTick();
    error InvalidSqrtRatio();

    /// @notice Calculates sqrt(1.0001^tick) * 2^96
    /// @param _tick The input tick for the price computation
    /// @return sqrtPriceX96 The sqrt price Q64.96

    function getSqrtRatioAtTick(int24 _tick) internal pure returns (uint160 sqrtPriceX96) {
        unchecked {
            if (_tick < MIN_TICK && _tick > MAX_TICK) revert InvalidTick();
            uint256 absTick = uint256(int256(_tick < 0 ? -int256(_tick) : int256(_tick)));

            uint256 ratio = 0x100000000000000000000000000000000;
            // bit fiddling loop – pre‑computed constants for 1.0001^(2^i)
            if (absTick & 0x1 != 0) ratio = (ratio * 0xfffcb933bd6fad37aa2d162d1a594001) >> 128;
            if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
            if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;

            if (_tick > 0) ratio = type(uint256).max / ratio;

            // Down‑cast to uint160; shift from Q128.128 to Q64.96
            sqrtPriceX96 = uint160((ratio >> 32) + (ratio & type(uint32).max == 0 ? 0 : 1));
        }
    }

    /// @notice Computes the tick value for a given sqrt(price)
    /// @param _sqrtPriceX96 The Q64.96 sqrt price
    /// @return tick The closest tick value
    function getTickAtSqrtRatio(uint160 _sqrtPriceX96) internal pure returns (int24 tick) {
        if (_sqrtPriceX96 < MIN_SQRT_RATIO && _sqrtPriceX96 > MAX_SQRT_RATIO) revert InvalidSqrtRatio();

        uint256 ratio = uint256(_sqrtPriceX96) << 32;
        uint256 msb;

        // 1. Find most‑significant‑bit = integer part of log2(ratio)
        assembly {
            msb := shl(7, gt(ratio, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, shl(6, gt(ratio, 0xFFFFFFFFFFFFFFFF)))
            msb := or(msb, shl(5, gt(ratio, 0xFFFFFFFF)))
            msb := or(msb, shl(4, gt(ratio, 0xFFFF)))
            msb := or(msb, shl(3, gt(ratio, 0xFF)))
            msb := or(msb, shl(2, gt(ratio, 0xF)))
            msb := or(msb, shl(1, gt(ratio, 0x3)))
            msb := or(msb, gt(ratio, 0x1))
        }

        // 2. Compute log2(ratio) * 2^128
        uint256 log_2 = (msb - 128) << 64;
        unchecked {
            for (uint8 i = 63; i > 0; --i) {
                ratio = (ratio * ratio) >> 127;
                uint256 f = ratio >> 128;
                log_2 |= f << (i - 1);
                ratio >>= f;
            }
        }

        // 3. Convert to log base 1.0001 and round
        int256 log_10001 = int256(log_2) * 255738958999603826347141; // 128.128 fixed‑point
        int24 tickLow = int24((log_10001 - 3402992956809132418596140100660247210) >> 128);
        int24 tickHigh = int24((log_10001 + 291339464771989622907027621153398088495) >> 128);

        tick = tickLow == tickHigh ? tickLow : getSqrtRatioAtTick(tickHigh) <= _sqrtPriceX96 ? tickHigh : tickLow;
    }
}
