// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "./interfaces/IPool.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {LowGasSafeMath} from "../libraries/LowGasSafeMath.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {Tick} from "../libraries/Tick.sol";
import {TickBitmap} from "../libraries/TickBitmap.sol";
import {Oracle} from "../libraries/Oracle.sol";
import {FullMath} from "../libraries/FullMath.sol";
import {FixedPoint128} from "../libraries/FixedPoint128.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {LiquidityMath} from "../libraries/LiquidityMath.sol";
import {SqrtPriceMath} from "../libraries/SqrtPriceMath.sol";
import {SwapMath} from "../libraries/SwapMath.sol";
import {IPoolDeployer} from "./interfaces/IPoolDeployer.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {ISupaSwapCallback} from "./interfaces/callback/ISupaSwapCallback.sol";
import {ISupaSwapMintCallback} from "./interfaces/callback/ISupaSwapMintCallback.sol";
import {ISupaSwapFlashCallback} from "./interfaces/callback/ISupaSwapFlashCallback.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {Position} from "../libraries/Position.sol";
import {FeeMath} from "../libraries/FeeMath.sol";
import {PoolOracle} from "./PoolOracle.sol";

/// @title  SupaSwap Pool
/// @notice Handles swaps, liquidity, and fees for a single token pair and fee tier
contract Pool is IPool, NoDelegateCall {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    //----------State Variables----------//
    address public immutable override factory;
    address public immutable override token0;
    address public immutable override token1;
    uint24 public immutable override fee;
    int24 public immutable override tickSpacing;
    uint128 public immutable override maxLiquidityPerTick;
    uint128 public override liquidity;
    Slot0 public override slot0;
    mapping(int24 => Tick.Info) public _ticks;
    uint256 public override feeGrowthGlobal0X128;
    uint256 public override feeGrowthGlobal1X128;
    uint256 public override protocolFeesCollected0;
    uint256 public override protocolFeesCollected1;
    mapping(int16 => uint256) public override tickBitmap;
    mapping(bytes32 => Position.Info) public override positions;
    PoolOracle public immutable poolOracle;
    SwapState private swapState; // Moved to storage to reduce stack usage

    //----------Structs----------//
    struct SwapCache {
        uint8 feeProtocol;
        uint128 liquidityStart;
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool computedLatestObservation;
    }

    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

    //----------Errors----------//
    error AlreadyInitialized();
    error NotFactory();
    error ZeroAmount();
    error InvalidTick();
    error Locked();
    error InsufficientLiquidity();
    error InvalidSqrtPriceLimit();

    //----------Modifiers----------//
    modifier onlyFactory() {
        if (msg.sender != IFactory(factory).owner()) revert NotFactory();
        _;
    }

    modifier lock() {
        if (slot0.unlocked == false) revert Locked();
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    //----------Constructor----------//
    constructor() {
        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IPoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;
        poolOracle = new PoolOracle(address(this));
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    //----------Internal Functions----------//
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper || tickLower < TickMath.MIN_TICK || tickUpper > TickMath.MAX_TICK) {
            revert InvalidTick();
        }
    }

    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function _initializeSwapCacheAndState(Slot0 memory slot0Start, bool _zeroForOne, uint128 _liquidity)
        internal
        returns (SwapCache memory cache)
    {
        cache = SwapCache({
            feeProtocol: _zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
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
            feeGrowthGlobalX128: _zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            protocolFee: 0,
            liquidity: _liquidity
        });
    }

    function _getNextTick(int24 _currentTick, int24 _tickSpacing, bool zeroForOne)
        internal
        view
        returns (int24 tickNext, bool initialized)
    {
        (tickNext, initialized) = tickBitmap.nextInitializedTickWithinOneWord(_currentTick, _tickSpacing, zeroForOne);
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
            (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = poolOracle.observeSingle(
                cache.blockTimestamp,
                0,
                slot0Start.tick,
                slot0Start.observationIndex,
                cache.liquidityStart,
                slot0Start.observationCardinality
            );
            cache.computedLatestObservation = true;
        }
        int128 liquidityNet = _ticks.cross(
            tickNext,
            (zeroForOne ? swapState.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
            (zeroForOne ? feeGrowthGlobal1X128 : swapState.feeGrowthGlobalX128),
            cache.secondsPerLiquidityCumulativeX128,
            cache.tickCumulative,
            cache.blockTimestamp
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

        (int24 tickNext, bool initialized) = _getNextTick(swapState.tick, tickSpacing, zeroForOne);
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

    function _modifyPosition(ModifyPositionParams memory params)
        private
        noDelegateCall
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        checkTicks(params.tickLower, params.tickUpper);
        Slot0 memory _slot0 = slot0;
        position = _updatePosition(params.owner, params.tickLower, params.tickUpper, params.liquidityDelta, _slot0.tick);

        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                uint128 liquidityBefore = liquidity;
                (slot0.observationIndex, slot0.observationCardinality) = poolOracle.write(
                    _slot0.observationIndex,
                    uint32(block.timestamp),
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );
                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(params.tickUpper), params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower), _slot0.sqrtPriceX96, params.liquidityDelta
                );
                liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
            } else {
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    function _updatePosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta, int24 tick)
        private
        returns (Position.Info storage position)
    {
        position = positions.get(owner, tickLower, tickUpper);
        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128;

        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            uint32 time = uint32(block.timestamp);
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = poolOracle.observeSingle(
                time, 0, slot0.tick, slot0.observationIndex, liquidity, slot0.observationCardinality
            );
            flippedLower = _ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                false,
                maxLiquidityPerTick
            );
            flippedUpper = _ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                true,
                maxLiquidityPerTick
            );
            if (flippedLower) tickBitmap.flipTick(tickLower, tickSpacing);
            if (flippedUpper) tickBitmap.flipTick(tickUpper, tickSpacing);
        }

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            _ticks.getFeeGrowthInside(tickLower, tickUpper, tick, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128);
        position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        if (liquidityDelta < 0) {
            if (flippedLower) _ticks.clear(tickLower);
            if (flippedUpper) _ticks.clear(tickUpper);
        }
    }

    //----------External Functions----------//
    function initialize(uint160 _sqrtPriceX96) external override onlyFactory lock {
        if (slot0.sqrtPriceX96 != 0) revert AlreadyInitialized();
        int24 tick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);
        (uint16 cardinality, uint16 cardinalityNext) = poolOracle.initialize(uint32(block.timestamp));
        slot0 = Slot0({
            sqrtPriceX96: _sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });
        emit Initialize(_sqrtPriceX96, tick);
    }

    function mint(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _liquidity, bytes calldata _data)
        external
        override
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        if (_liquidity == 0) revert ZeroAmount();
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: _recipient,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: int256(uint256(_liquidity)).toInt128()
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        ISupaSwapMintCallback(msg.sender).supaSwapMintCallback(amount0, amount1, _data);
        if (amount0 > 0 && balance0Before.add(amount0) > balance0()) revert("M0");
        if (amount1 > 0 && balance1Before.add(amount1) > balance1()) revert("M1");

        emit Mint(msg.sender, _recipient, _tickLower, _tickUpper, _liquidity, amount0, amount1);
    }

    function collect(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _amount0, uint128 _amount1)
        external
        override
        lock
        returns (uint128 amount0, uint128 amount1)
    {
        Position.Info storage position = positions.get(msg.sender, _tickLower, _tickUpper);
        amount0 = _amount0 > position.tokensOwed0 ? position.tokensOwed0 : _amount0;
        amount1 = _amount1 > position.tokensOwed1 ? position.tokensOwed1 : _amount1;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(token0, _recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, _recipient, amount1);
        }

        emit Collect(msg.sender, _recipient, _tickLower, _tickUpper, amount0, amount1);
    }

    function burn(int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        override
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        if (_liquidity == 0) revert ZeroAmount();
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: -int256(uint256(_liquidity)).toInt128()
            })
        );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) =
                (position.tokensOwed0 + uint128(amount0), position.tokensOwed1 + uint128(amount1));
        }

        emit Burn(msg.sender, _tickLower, _tickUpper, _liquidity, amount0, amount1);
    }

    function swap(
        address _recipient,
        bool _zeroForOne,
        int256 _amount,
        uint160 _sqrtPriceLimitX96,
        bytes calldata _data
    ) external override returns (int256 amount0, int256 amount1) {
        if (_amount == 0) revert ZeroAmount();
        Slot0 memory slot0Start = slot0;

        if (_zeroForOne) {
            if (_sqrtPriceLimitX96 >= slot0Start.sqrtPriceX96 || _sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
                revert InvalidSqrtPriceLimit();
            }
        } else {
            if (_sqrtPriceLimitX96 <= slot0Start.sqrtPriceX96 || _sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) {
                revert InvalidSqrtPriceLimit();
            }
        }

        slot0.unlocked = false;

        SwapCache memory cache = _initializeSwapCacheAndState(slot0Start, _zeroForOne, liquidity);
        swapState.amountSpecifiedRemaining = _amount;
        bool exactInput = _amount > 0;

        bool priceReached;
        while (!priceReached) {
            (priceReached, cache) =
                _processSwapStep(_sqrtPriceLimitX96, _zeroForOne, exactInput, cache.feeProtocol, slot0Start);
        }

        if (swapState.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = poolOracle.write(
                slot0Start.observationIndex,
                cache.blockTimestamp,
                slot0Start.tick,
                cache.liquidityStart,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext
            );
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) =
                (swapState.sqrtPriceX96, swapState.tick, observationIndex, observationCardinality);
        } else {
            slot0.sqrtPriceX96 = swapState.sqrtPriceX96;
        }

        if (cache.liquidityStart != swapState.liquidity) liquidity = swapState.liquidity;

        if (_zeroForOne) {
            feeGrowthGlobal0X128 = swapState.feeGrowthGlobalX128;
            if (swapState.protocolFee > 0) protocolFeesCollected0 += swapState.protocolFee;
        } else {
            feeGrowthGlobal1X128 = swapState.feeGrowthGlobalX128;
            if (swapState.protocolFee > 0) protocolFeesCollected1 += swapState.protocolFee;
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

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data)
        external
        override
        lock
        noDelegateCall
    {
        uint128 _liquidity = liquidity;
        if (_liquidity == 0) revert InsufficientLiquidity();

        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();

        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        ISupaSwapFlashCallback(msg.sender).supaSwapFlashCallback(int256(fee0), int256(fee1), data);

        uint256 balance0After = balance0();
        uint256 balance1After = balance1();

        if (balance0Before.add(fee0) > balance0After) revert("F0");
        if (balance1Before.add(fee1) > balance1After) revert("F1");

        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        if (paid0 > 0) {
            uint8 feeProtocol0 = slot0.feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
            if (fees0 > 0) {
                protocolFeesCollected0 += uint128(fees0);
                feeGrowthGlobal0X128 += FullMath.mulDiv(paid0 - fees0, FixedPoint128.Q128, _liquidity);
            }
        }
        if (paid1 > 0) {
            uint8 feeProtocol1 = slot0.feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
            if (fees1 > 0) {
                protocolFeesCollected1 += uint128(fees1);
                feeGrowthGlobal1X128 += FullMath.mulDiv(paid1 - fees1, FixedPoint128.Q128, _liquidity);
            }
        }

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock onlyFactory {
        require(
            (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10))
                && (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10))
        );
        uint8 feeProtocolOld = slot0.feeProtocol;
        slot0.feeProtocol = feeProtocol0 + (feeProtocol1 << 4);
        emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        override
        lock
        onlyFactory
        returns (uint128 amount0, uint128 amount1)
    {
        amount0 =
            amount0Requested > uint128(protocolFeesCollected0) ? uint128(protocolFeesCollected0) : amount0Requested;
        amount1 =
            amount1Requested > uint128(protocolFeesCollected1) ? uint128(protocolFeesCollected1) : amount1Requested;

        if (amount0 > 0) {
            if (amount0 == protocolFeesCollected0) amount0--;
            protocolFeesCollected0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            if (amount1 == protocolFeesCollected1) amount1--;
            protocolFeesCollected1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }

    function setObservationCardinalityNext(uint16 observationCardinalityNext) external {
        slot0.observationCardinalityNext = observationCardinalityNext;
    }

    function tokens() external view override returns (address tokenA, address tokenB) {
        return (token0, token1);
    }

    function getSlot0()
        external
        view
        override
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        Slot0 memory _slot0 = slot0;
        return (
            _slot0.sqrtPriceX96,
            _slot0.tick,
            _slot0.observationIndex,
            _slot0.observationCardinality,
            _slot0.observationCardinalityNext,
            _slot0.feeProtocol,
            _slot0.unlocked
        );
    }

    function getLiquidity() external view override returns (uint128) {
        return liquidity;
    }

    function getPositions(bytes32 key)
        external
        view
        override
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position.Info storage pos = positions[key];
        return (
            pos.liquidity, pos.feeGrowthInside0LastX128, pos.feeGrowthInside1LastX128, pos.tokensOwed0, pos.tokensOwed1
        );
    }

    function getTickSpacing() external view override returns (int24) {
        return tickSpacing;
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external override lock {
        require(msg.sender == address(poolOracle), "Only pool oracle");
        poolOracle.increaseObservationCardinalityNext(observationCardinalityNext);
    }

    function observations(uint256 index)
        external
        view
        override
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        )
    {
        return poolOracle.observations(index);
    }

    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside)
    {
        return poolOracle.snapshotCumulativesInside(tickLower, tickUpper, address(this));
    }

    function observe(uint32[] memory secondsAgos)
        external
        view
        override
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128)
    {
        return poolOracle.observe(secondsAgos);
    }

    function ticks(int24 tick)
        external
        view
        override
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {
        Tick.Info storage tickInfo = _ticks[tick];
        return (
            tickInfo.liquidityGross,
            tickInfo.liquidityNet,
            tickInfo.feeGrowthOutside0X128,
            tickInfo.feeGrowthOutside1X128,
            tickInfo.tickCumulativeOutside,
            tickInfo.secondsPerLiquidityOutsideX128,
            tickInfo.secondsOutside,
            tickInfo.initialized
        );
    }
}
