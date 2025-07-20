// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Oracle} from "../libraries/Oracle.sol";
import {Tick} from "../libraries/Tick.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {Pool} from "./Pool.sol";

/// @title SupaSwap Pool Oracle
/// @notice Handles oracle-related functionality for the Pool contract
contract PoolOracle is NoDelegateCall {
    using Oracle for Oracle.Observation[65535];

    Oracle.Observation[65535] public observations;
    address public immutable pool;

    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    error NotPool();

    //----------Events----------//
    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew
    );

    modifier onlyPool() {
        if (msg.sender != pool) revert NotPool();
        _;
    }

    constructor(address _pool) {
        pool = _pool;
    }

    function initialize(uint32 time) external onlyPool returns (uint16 cardinality, uint16 cardinalityNext) {
        return observations.initialize(time);
    }

    function write(
        uint16 observationIndex,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) external onlyPool returns (uint16, uint16) {
        return observations.write(observationIndex, blockTimestamp, tick, liquidity, cardinality, cardinalityNext);
    }

    function observeSingle(
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) external view onlyPool noDelegateCall returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) {
        return observations.observeSingle(time, secondsAgo, tick, index, liquidity, cardinality);
    }

    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper, address poolAddress)
        external
        view
        onlyPool
        returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside)
    {
        if (msg.sender != poolAddress) {
            revert("Only pool or pool address");
        }
        if (tickLower >= tickUpper || tickLower < TickMath.MIN_TICK || tickUpper > TickMath.MAX_TICK) {
            revert("Invalid tick");
        }
        (
            int56 tickCumulativeOutsideLower,
            uint160 secondsPerLiquidityOutsideX128Lower,
            uint32 secondsOutsideLower,
            bool initializedLower,
            int56 tickCumulativeOutsideUpper,
            uint160 secondsPerLiquidityOutsideX128Upper,
            uint32 secondsOutsideUpper,
            bool initializedUpper
        ) = getTickData(tickLower, tickUpper, poolAddress);
        require(initializedLower && initializedUpper, "Uninitialized ticks");

        (Slot0 memory _slot0, uint128 liquidity) = _getSlot0AndLiquidity();

        if (_slot0.tick < tickLower) {
            return (
                tickCumulativeOutsideLower - tickCumulativeOutsideUpper,
                secondsPerLiquidityOutsideX128Lower - secondsPerLiquidityOutsideX128Upper,
                secondsOutsideLower - secondsOutsideUpper
            );
        } else if (_slot0.tick < tickUpper) {
            uint32 time = uint32(block.timestamp);
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                time, 0, _slot0.tick, _slot0.observationIndex, liquidity, _slot0.observationCardinality
            );
            return (
                tickCumulative - tickCumulativeOutsideLower - tickCumulativeOutsideUpper,
                secondsPerLiquidityCumulativeX128 - secondsPerLiquidityOutsideX128Lower
                    - secondsPerLiquidityOutsideX128Upper,
                time - secondsOutsideLower - secondsOutsideUpper
            );
        } else {
            return (
                tickCumulativeOutsideUpper - tickCumulativeOutsideLower,
                secondsPerLiquidityOutsideX128Upper - secondsPerLiquidityOutsideX128Lower,
                secondsOutsideUpper - secondsOutsideLower
            );
        }
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        onlyPool
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        (, int24 tick, uint16 observationIndex, uint16 observationCardinality,,,) = Pool(pool).slot0();
        uint128 liquidity = Pool(pool).getLiquidity();
        return observations.observe(
            uint32(block.timestamp), secondsAgos, tick, observationIndex, liquidity, observationCardinality
        );
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external onlyPool {
        (,,, uint16 observationCardinalityNextOld,,,) = Pool(pool).slot0();
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);
        Pool(pool).setObservationCardinalityNext(observationCardinalityNextNew);
        if (observationCardinalityNextOld != observationCardinalityNextNew) {
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
        }
    }

    function _getSlot0AndLiquidity() private view returns (Slot0 memory _slot0, uint128 liquidity) {
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) = Pool(pool).slot0();

        _slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: observationIndex,
            observationCardinality: observationCardinality,
            observationCardinalityNext: observationCardinalityNext,
            feeProtocol: feeProtocol,
            unlocked: unlocked
        });

        liquidity = Pool(pool).getLiquidity();
    }

    function getTickData(int24 tickLower, int24 tickUpper, address poolAddress)
        private
        view
        returns (
            int56 tickCumulativeOutsideLower,
            uint160 secondsPerLiquidityOutsideX128Lower,
            uint32 secondsOutsideLower,
            bool initializedLower,
            int56 tickCumulativeOutsideUpper,
            uint160 secondsPerLiquidityOutsideX128Upper,
            uint32 secondsOutsideUpper,
            bool initializedUpper
        )
    {
        Pool poolContract = Pool(poolAddress);
        (,,,, tickCumulativeOutsideLower, secondsPerLiquidityOutsideX128Lower, secondsOutsideLower, initializedLower) =
            poolContract.ticks(tickLower);
        (,,,, tickCumulativeOutsideUpper, secondsPerLiquidityOutsideX128Upper, secondsOutsideUpper, initializedUpper) =
            poolContract.ticks(tickUpper);
    }
}
