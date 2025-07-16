// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FullMath} from "./FullMath.sol";
import {FixedPoint128} from "./FixedPoint128.sol";

/// @title  OracleMath
/// @notice Math used for updating oracle observations in a TWAP-enabled AMM
library OracleMath {
    /// @notice Custom Errors
    error ZeroLiquidity();

    /// @notice Computes the cumulative tick and secondsPerLiquidity values for the current timestamp
    /// @param _blockTimestamp Current block.timestamp
    /// @param _lastTimestamp Timestamp of the last observation
    /// @param _tick The current pool tick
    /// @param _liquidity Pool liquidity at this moment (uint128)
    /// @return tickCumulative New cumulative tick value
    /// @return secondsPerLiquidityCumulativeX128 New cumulative liquidity metric

    function computeCumulatives(uint32 _blockTimestamp, uint32 _lastTimestamp, int24 _tick, uint128 _liquidity)
        internal
        pure
        returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128)
    {
        unchecked {
            uint32 delta = _blockTimestamp - _lastTimestamp;

            tickCumulative = int56(int256(_tick)) * int56(uint56(delta));

            if (_liquidity == 0) revert ZeroLiquidity();
            secondsPerLiquidityCumulativeX128 = uint160(FullMath.mulDiv(delta, FixedPoint128.Q128, _liquidity));
        }
    }
}
