// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LowGasSafeMath} from "../../libraries/LowGasSafeMath.sol";
import {SafeCast} from "../../libraries/SafeCast.sol";
import {TickMath} from "../../libraries/TickMath.sol";
import {SwapMath} from "../../libraries/SwapMath.sol";
import {FullMath} from "../../libraries/FullMath.sol";
import {FixedPoint128} from "../../libraries/FixedPoint128.sol";
import {TransferHelper} from "../../libraries/TransferHelper.sol";
import {LiquidityMath} from "../../libraries/LiquidityMath.sol";
import {ISupaSwapCallback} from "../interfaces/callback/ISupaSwapCallback.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IERC20Minimal} from "../../interfaces/IERC20Minimal.sol";
import {PoolOracle} from "../PoolOracle.sol";
import {ISwapManager} from "../interfaces/manager/ISwapManager.sol";

contract SwapManager is ISwapManager {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    address public immutable pool;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    address public immutable poolOracle;

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    struct SwapCache {
        uint8 feeProtocol;
        uint128 liquidityStart;
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool computedLatestObservation;
    }

    struct SwapState {
        int256 amountSpecifiedRemaining;
        int256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        uint256 feeGrowthGlobalX128;
        uint128 protocolFee;
        uint128 liquidity;
    }

    struct StepComputations {
        uint160 sqrtPriceStartX96;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }

    SwapState private swapState;

    error ZeroAmount();
    error InvalidSqrtPriceLimit();

    constructor(address _pool, address _token0, address _token1, uint24 _fee, address _poolOracle) {
        pool = _pool;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        poolOracle = _poolOracle;
    }

    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, pool));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, pool));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function _initializeSwapCacheAndState(Slot0 memory slot0Start, bool _zeroForOne, uint128 _liquidity)
        internal
        returns (SwapCache memory cache)
    {
        (,,,,, uint8 feeProtocol,) = IPool(pool).getSlot0();
        uint256 feeGrowthGlobal = _zeroForOne ? IPool(pool).feeGrowthGlobal0X128() : IPool(pool).feeGrowthGlobal1X128();
        cache = SwapCache({
            feeProtocol: _zeroForOne ? (feeProtocol % 16) : (feeProtocol >> 4),
            liquidityStart: _liquidity,
            blockTimestamp: uint32(block.timestamp),
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0,
            computedLatestObservation: false
        });

        swapState = SwapState({
            amountSpecifiedRemaining: 0,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: feeGrowthGlobal,
            protocolFee: 0,
            liquidity: _liquidity
        });
    }

    function _getNextTick(int24 _currentTick, int24 _tickSpacing, bool zeroForOne)
        internal
        returns (int24 tickNext, bool initialized)
    {
        (tickNext, initialized) = IPool(pool).nextInitializedTick(_currentTick, _tickSpacing, zeroForOne);
        if (tickNext < TickMath.MIN_TICK) tickNext = TickMath.MIN_TICK;
        else if (tickNext > TickMath.MAX_TICK) tickNext = TickMath.MAX_TICK;
    }

    function _computeSwapStep(uint160 sqrtPriceLimitX96, bool zeroForOne, int24 tickNext)
        internal
        returns (StepComputations memory step)
    {
        step.sqrtPriceStartX96 = swapState.sqrtPriceX96;
        step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(tickNext);

        (swapState.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
            swapState.sqrtPriceX96,
            (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                ? sqrtPriceLimitX96
                : step.sqrtPriceNextX96,
            swapState.liquidity,
            swapState.amountSpecifiedRemaining,
            fee
        );
    }

    function _updateSwapState(StepComputations memory step, bool exactInput, uint8 feeProtocol) internal {
        if (exactInput) {
            swapState.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
            swapState.amountCalculated = swapState.amountCalculated.sub(step.amountOut.toInt256());
        } else {
            swapState.amountSpecifiedRemaining += step.amountOut.toInt256();
            swapState.amountCalculated = swapState.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
        }

        if (feeProtocol > 0) {
            uint256 delta = step.feeAmount / feeProtocol;
            step.feeAmount -= delta;
            swapState.protocolFee += uint128(delta);
        }

        if (swapState.liquidity > 0) {
            swapState.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, swapState.liquidity);
        }
    }

    function _handleTickCross(SwapCache memory cache, int24 tickNext, bool zeroForOne, Slot0 memory slot0Start)
        internal
        returns (SwapCache memory)
    {
        if (!cache.computedLatestObservation) {
            (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = PoolOracle(poolOracle).observeSingle(
                cache.blockTimestamp,
                0,
                slot0Start.tick,
                slot0Start.observationIndex,
                cache.liquidityStart,
                slot0Start.observationCardinality
            );
            cache.computedLatestObservation = true;
        }
        int128 liquidityNet = IPool(pool).crossTick(
            tickNext,
            swapState.feeGrowthGlobalX128,
            cache.secondsPerLiquidityCumulativeX128,
            cache.tickCumulative,
            cache.blockTimestamp,
            zeroForOne
        );
        if (zeroForOne) liquidityNet = -liquidityNet;
        swapState.liquidity = LiquidityMath.addDelta(swapState.liquidity, liquidityNet);
        return cache;
    }

    function _processSwapStep(
        uint160 sqrtPriceLimitX96,
        bool zeroForOne,
        bool exactInput,
        uint8 feeProtocol,
        Slot0 memory slot0Start
    ) internal returns (bool priceReached, SwapCache memory cache) {
        if (swapState.amountSpecifiedRemaining == 0 || swapState.sqrtPriceX96 == sqrtPriceLimitX96) {
            priceReached = true;
            return (priceReached, cache);
        }

        (int24 tickNext, bool initialized) = _getNextTick(swapState.tick, IPool(pool).getTickSpacing(), zeroForOne);
        StepComputations memory step = _computeSwapStep(sqrtPriceLimitX96, zeroForOne, tickNext);
        _updateSwapState(step, exactInput, feeProtocol);

        if (swapState.sqrtPriceX96 == step.sqrtPriceNextX96 && initialized) {
            cache = _handleTickCross(cache, tickNext, zeroForOne, slot0Start);
            swapState.tick = zeroForOne ? tickNext - 1 : tickNext;
        } else if (swapState.sqrtPriceX96 != step.sqrtPriceStartX96) {
            swapState.tick = TickMath.getTickAtSqrtRatio(swapState.sqrtPriceX96);
        }

        priceReached = false;
        return (priceReached, cache);
    }

    function swap(
        address _recipient,
        bool _zeroForOne,
        int256 _amount,
        uint160 _sqrtPriceLimitX96,
        bytes calldata _data
    ) external returns (int256 amount0, int256 amount1) {
        if (_amount == 0) revert ZeroAmount();
        Slot0 memory slot0Start = _getSlot0();

        if (_zeroForOne) {
            if (_sqrtPriceLimitX96 >= slot0Start.sqrtPriceX96 || _sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
                revert InvalidSqrtPriceLimit();
            }
        } else {
            if (_sqrtPriceLimitX96 <= slot0Start.sqrtPriceX96 || _sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) {
                revert InvalidSqrtPriceLimit();
            }
        }

        SwapCache memory cache = _initializeSwapCacheAndState(slot0Start, _zeroForOne, IPool(pool).getLiquidity());
        swapState.amountSpecifiedRemaining = _amount;
        bool exactInput = _amount > 0;

        bool priceReached;
        while (!priceReached) {
            (priceReached, cache) =
                _processSwapStep(_sqrtPriceLimitX96, _zeroForOne, exactInput, cache.feeProtocol, slot0Start);
        }

        if (swapState.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = PoolOracle(poolOracle).write(
                slot0Start.observationIndex,
                cache.blockTimestamp,
                slot0Start.tick,
                cache.liquidityStart,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext
            );
            IPool(pool).setSlot0(
                swapState.sqrtPriceX96,
                swapState.tick,
                observationIndex,
                observationCardinality,
                slot0Start.observationCardinalityNext,
                slot0Start.feeProtocol,
                slot0Start.unlocked
            );
        } else {
            IPool(pool).setSlot0(
                swapState.sqrtPriceX96,
                slot0Start.tick,
                slot0Start.observationIndex,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext,
                slot0Start.feeProtocol,
                slot0Start.unlocked
            );
        }

        if (cache.liquidityStart != swapState.liquidity) IPool(pool).setLiquidity(swapState.liquidity);

        if (_zeroForOne) {
            IPool(pool).setFeeGrowthGlobal0X128(swapState.feeGrowthGlobalX128);
            if (swapState.protocolFee > 0) IPool(pool).addProtocolFeesCollected0(swapState.protocolFee);
        } else {
            IPool(pool).setFeeGrowthGlobal1X128(swapState.feeGrowthGlobalX128);
            if (swapState.protocolFee > 0) IPool(pool).addProtocolFeesCollected1(swapState.protocolFee);
        }

        (amount0, amount1) = _zeroForOne == exactInput
            ? (_amount - swapState.amountSpecifiedRemaining, swapState.amountCalculated)
            : (swapState.amountCalculated, _amount - swapState.amountSpecifiedRemaining);

        if (_zeroForOne) {
            if (amount1 < 0) TransferHelper.safeTransfer(token1, _recipient, uint256(-amount1));
            uint256 balance0Before = balance0();
            ISupaSwapCallback(msg.sender).supaSwapCallback(amount0, amount1, _data);
            require(balance0Before.add(uint256(amount0)) <= balance0(), "IIA");
        } else {
            if (amount0 < 0) TransferHelper.safeTransfer(token0, _recipient, uint256(-amount0));
            uint256 balance1Before = balance1();
            ISupaSwapCallback(msg.sender).supaSwapCallback(amount0, amount1, _data);
            require(balance1Before.add(uint256(amount1)) <= balance1(), "IIA");
        }

        emit Swap(msg.sender, _recipient, amount0, amount1, swapState.sqrtPriceX96, swapState.liquidity, swapState.tick);
    }

    ///@dev Helper functions to avoid --via-ir errors
    function _getSlot0() private view returns (Slot0 memory) {
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) = IPool(pool).getSlot0();
        return Slot0(
            sqrtPriceX96,
            tick,
            observationIndex,
            observationCardinality,
            observationCardinalityNext,
            feeProtocol,
            unlocked
        );
    }
}
