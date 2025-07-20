// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LowGasSafeMath} from "./LowGasSafeMath.sol";
import {SafeCast} from "./SafeCast.sol";
import {LiquidityMath} from "./LiquidityMath.sol";
import {TickMath} from "./TickMath.sol";

library Tick {
    using LowGasSafeMath for int256;
    using SafeCast for int256;

    struct Info {
        uint128 liquidityGross; // total liquidity at the tick
        int128 liquidityNet; // net liquidity added/removed when crossing
        uint256 feeGrowthOutside0X128; // fee growth outside this tick for token0
        uint256 feeGrowthOutside1X128; // fee growth outside this tick for token1
        int56 tickCumulativeOutside; // cumulative tick value outside this tick
        uint160 secondsPerLiquidityOutsideX128; // seconds per unit of liquidity outside
        uint32 secondsOutside; // total seconds spent outside this tick
        bool initialized; // true if tick is initialized (liquidityGross != 0)
    }

    /// @notice Updates the tick with liquidity changes
    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped) {
        Tick.Info storage info = self[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        require(liquidityGrossAfter <= maxLiquidity, "LO");

        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
            if (tick <= tickCurrent) {
                info.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
                info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128;
                info.tickCumulativeOutside = tickCumulative;
                info.secondsOutside = time;
            }
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;

        // when the lower (upper) tick is crossed left to right (right to left), liquidity must be added (removed)
        info.liquidityNet = upper
            ? int256(info.liquidityNet).sub(liquidityDelta).toInt128()
            : int256(info.liquidityNet).add(liquidityDelta).toInt128();
    }

    /// @notice Handles crossing a tick (during swap)
    function cross(
        mapping(int24 => Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time
    ) internal returns (int128 liquidityNet) {
        Info storage info = self[tick];
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
        info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128 - info.secondsPerLiquidityOutsideX128;
        info.tickCumulativeOutside = tickCumulative - info.tickCumulativeOutside;
        info.secondsOutside = time - info.secondsOutside;
        liquidityNet = info.liquidityNet;
    }

    /// @notice Clears tick data
    function clear(mapping(int24 => Info) storage self, int24 tick) internal {
        delete self[tick];
    }

    /// @notice Computes the fee growth inside a tick range
    function getFeeGrowthInside(
        mapping(int24 => Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];

        uint256 feeGrowthBelow0X128 =
            tickCurrent >= tickLower ? lower.feeGrowthOutside0X128 : feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;

        uint256 feeGrowthBelow1X128 =
            tickCurrent >= tickLower ? lower.feeGrowthOutside1X128 : feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;

        uint256 feeGrowthAbove0X128 =
            tickCurrent < tickUpper ? upper.feeGrowthOutside0X128 : feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;

        uint256 feeGrowthAbove1X128 =
            tickCurrent < tickUpper ? upper.feeGrowthOutside1X128 : feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    /// @notice Calculates the maximum liquidity per tick based on tick spacing
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        return type(uint128).max / numTicks;
    }
}
