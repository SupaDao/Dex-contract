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
import {ProtocolFees} from "../governance/ProtocolFees.sol";
import {EmergencyPause} from "../governance/EmergencyPause.sol";

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
    using Oracle for Oracle.Observation[65535];

    //----------State Variables----------//
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint128 public immutable maxLiquidityPerTick;

    uint128 public liquidity;

    Slot0 public slot0;

    mapping(int24 => Tick.Info) public ticks;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    uint256 public protocolFeesCollected0;
    uint256 public protocolFeesCollected1;
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) public positions;
    Oracle.Observation[65535] public observations;
    ProtocolFees public immutable protocolFees;
    EmergencyPause public immutable emergencyPause;

    // ───────────── Events & Errors ─────────────
    error AlreadyInitialized();
    error NotFactory();
    error ZeroAmount();
    error InvalidTick();
    error Locked();
    error InsufficientLiquidity();
    error InvalidSqrtPriceLimit();

    // ───────────── Modifiers ─────────────//
    modifier onlyFactory() {
        if (msg.sender != IFactory(factory).owner()) revert NotFactory();
        _;
    }

    modifier notPaused() {
        require(!emergencyPause.isPoolPaused(address(this)), "Pool paused");
        _;
    }

    modifier lock() {
        if (slot0.unlocked == false) revert Locked();
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    // ───────────── Constructor ─────────────//
    constructor(address _protocolFees, address _emergencyPause) {
        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IPoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;
        protocolFees = ProtocolFees(_protocolFees);
        emergencyPause = EmergencyPause(_emergencyPause);
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper || tickLower < TickMath.MIN_TICK || tickUpper > TickMath.MAX_TICK) {
            revert InvalidTick();
        }
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
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

    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        override
        noDelegateCall
        notPaused
        returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside)
    {
        checkTicks(tickLower, tickUpper);

        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;

        {
            Tick.Info storage lower = ticks[tickLower];
            Tick.Info storage upper = ticks[tickUpper];
            bool initializedLower;
            (tickCumulativeLower, secondsPerLiquidityOutsideLowerX128, secondsOutsideLower, initializedLower) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );
            require(initializedLower);

            bool initializedUpper;
            (tickCumulativeUpper, secondsPerLiquidityOutsideUpperX128, secondsOutsideUpper, initializedUpper) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
            require(initializedUpper);
        }

        Slot0 memory _slot0 = slot0;

        if (_slot0.tick < tickLower) {
            return (
                tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128,
                secondsOutsideLower - secondsOutsideUpper
            );
        } else if (_slot0.tick < tickUpper) {
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                time, 0, _slot0.tick, _slot0.observationIndex, liquidity, _slot0.observationCardinality
            );
            return (
                tickCumulative - tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityCumulativeX128 - secondsPerLiquidityOutsideLowerX128
                    - secondsPerLiquidityOutsideUpperX128,
                time - secondsOutsideLower - secondsOutsideUpper
            );
        } else {
            return (
                tickCumulativeUpper - tickCumulativeLower,
                secondsPerLiquidityOutsideUpperX128 - secondsPerLiquidityOutsideLowerX128,
                secondsOutsideUpper - secondsOutsideLower
            );
        }
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        noDelegateCall
        notPaused
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return observations.observe(
            _blockTimestamp(), secondsAgos, slot0.tick, slot0.observationIndex, liquidity, slot0.observationCardinality
        );
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext)
        external
        notPaused
        lock
        noDelegateCall
    {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);
        slot0.observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew) {
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
        }
    }

    function initialize(uint160 _sqrtPriceX96) external notPaused onlyFactory lock {
        if (slot0.sqrtPriceX96 != 0) revert AlreadyInitialized();
        int24 tick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);
        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());
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

    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
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

                (slot0.observationIndex, slot0.observationCardinality) = observations.write(
                    _slot0.observationIndex,
                    _blockTimestamp(),
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
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                time, 0, slot0.tick, slot0.observationIndex, liquidity, slot0.observationCardinality
            );

            flippedLower = ticks.update(
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
            flippedUpper = ticks.update(
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

            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing);
            }
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }
        }

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            ticks.getFeeGrowthInside(tickLower, tickUpper, tick, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128);

        position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    function mint(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _liquidity, bytes calldata _data)
        external
        override
        notPaused
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        if (_liquidity == 0) revert ZeroAmount();
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: _recipient,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: int256(int128(_liquidity)).toInt128()
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        // Apply liquidity fee
        (, uint24 liquidityFee, address feeRecipient) = protocolFees.getFees();
        uint256 liquidityFee0 = liquidityFee > 0 ? FullMath.mulDiv(amount0, liquidityFee, 10000) : 0;
        uint256 liquidityFee1 = liquidityFee > 0 ? FullMath.mulDiv(amount1, liquidityFee, 10000) : 0;
        if (liquidityFee0 > 0) {
            protocolFeesCollected0 += liquidityFee0;
            if (feeRecipient != address(0)) {
                TransferHelper.safeTransfer(token0, feeRecipient, liquidityFee0);
            }
        }
        if (liquidityFee1 > 0) {
            protocolFeesCollected1 += liquidityFee1;
            if (feeRecipient != address(0)) {
                TransferHelper.safeTransfer(token1, feeRecipient, liquidityFee1);
            }
        }

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > liquidityFee0) balance0Before = balance0();
        if (amount1 > liquidityFee1) balance1Before = balance1();
        ISupaSwapMintCallback(msg.sender).supaSwapMintCallback(amount0 - liquidityFee0, amount1 - liquidityFee1, _data);
        if (amount0 > liquidityFee0) {
            if (balance0Before.add(amount0 - liquidityFee0) > balance0()) revert("M0");
        }
        if (amount1 > liquidityFee1) {
            if (balance1Before.add(amount1 - liquidityFee1) > balance1()) revert("M1");
        }

        emit Mint(msg.sender, _recipient, _tickLower, _tickUpper, _liquidity, amount0, amount1);
    }

    function collect(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _amount0, uint128 _amount1)
        external
        override
        notPaused
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
        notPaused
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        if (_liquidity == 0) revert ZeroAmount();
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: -int256(int128(_liquidity)).toInt128()
            })
        );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        // Apply liquidity fee on burn
        (, uint24 liquidityFee, address feeRecipient) = protocolFees.getFees();
        uint256 liquidityFee0 = liquidityFee > 0 ? FullMath.mulDiv(amount0, liquidityFee, 10000) : 0;
        uint256 liquidityFee1 = liquidityFee > 0 ? FullMath.mulDiv(amount1, liquidityFee, 10000) : 0;
        if (liquidityFee0 > 0) {
            protocolFeesCollected0 += liquidityFee0;
            if (feeRecipient != address(0)) {
                TransferHelper.safeTransfer(token0, feeRecipient, liquidityFee0);
            }
        }
        if (liquidityFee1 > 0) {
            protocolFeesCollected1 += liquidityFee1;
            if (feeRecipient != address(0)) {
                TransferHelper.safeTransfer(token1, feeRecipient, liquidityFee1);
            }
        }

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0 - liquidityFee0),
                position.tokensOwed1 + uint128(amount1 - liquidityFee1)
            );
        }

        emit Burn(msg.sender, _tickLower, _tickUpper, _liquidity, amount0, amount1);
    }

    struct SwapCache {
        uint8 feeProtocol;
        uint128 liquidityStart;
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool computedLatestObservation;
    }

    function swap(
        address _recipient,
        bool _zeroForOne,
        int256 _amount,
        uint160 _sqrtPriceLimitX96,
        bytes calldata _data
    ) external override lock notPaused returns (int256 amount0, int256 amount1) {
        if (_amount == 0) revert ZeroAmount();

        Slot0 memory slot0Start = slot0;

        if (_zeroForOne) {
            if (_sqrtPriceLimitX96 >= slot0.sqrtPriceX96 || _sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
                revert InvalidSqrtPriceLimit();
            }
        } else {
            if (_sqrtPriceLimitX96 <= slot0.sqrtPriceX96 || _sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) {
                revert InvalidSqrtPriceLimit();
            }
        }

        SwapCache memory cache = SwapCache({
            liquidityStart: liquidity,
            blockTimestamp: _blockTimestamp(),
            feeProtocol: _zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
            secondsPerLiquidityCumulativeX128: 0,
            tickCumulative: 0,
            computedLatestObservation: false
        });

        bool exactInput = _amount > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: _amount,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: _zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            protocolFee: 0,
            liquidity: cache.liquidityStart
        });

        // Fetch protocol swap fee
        (uint24 swapFee,, address feeRecipient) = protocolFees.getFees();

        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != _sqrtPriceLimitX96) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) =
                tickBitmap.nextInitializedTickWithinOneWord(state.tick, tickSpacing, _zeroForOne);

            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (_zeroForOne ? step.sqrtPriceNextX96 < _sqrtPriceLimitX96 : step.sqrtPriceNextX96 > _sqrtPriceLimitX96)
                    ? _sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                fee + swapFee // Include protocol swap fee
            );

            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

            if (cache.feeProtocol > 0) {
                uint256 delta = step.feeAmount / cache.feeProtocol;
                step.feeAmount -= delta;
                state.protocolFee += uint128(delta);
            }

            // Apply protocol swap fee
            uint256 protocolSwapFeeAmount = swapFee > 0 ? FullMath.mulDiv(step.amountIn, swapFee, 10000) : 0;
            if (protocolSwapFeeAmount > 0) {
                if (_zeroForOne) {
                    protocolFeesCollected0 += protocolSwapFeeAmount;
                    if (feeRecipient != address(0)) {
                        TransferHelper.safeTransfer(token0, feeRecipient, protocolSwapFeeAmount);
                    }
                } else {
                    protocolFeesCollected1 += protocolSwapFeeAmount;
                    if (feeRecipient != address(0)) {
                        TransferHelper.safeTransfer(token1, feeRecipient, protocolSwapFeeAmount);
                    }
                }
            }

            if (state.liquidity > 0) {
                state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
            }

            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                            cache.blockTimestamp,
                            0,
                            slot0Start.tick,
                            slot0Start.observationIndex,
                            cache.liquidityStart,
                            slot0Start.observationCardinality
                        );
                        cache.computedLatestObservation = true;
                    }
                    int128 liquidityNet = ticks.cross(
                        step.tickNext,
                        (_zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                        (_zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128),
                        cache.secondsPerLiquidityCumulativeX128,
                        cache.tickCumulative,
                        cache.blockTimestamp
                    );
                    if (_zeroForOne) liquidityNet = -liquidityNet;

                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }

                state.tick = _zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        if (state.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = observations.write(
                slot0Start.observationIndex,
                cache.blockTimestamp,
                slot0Start.tick,
                cache.liquidityStart,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext
            );
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) =
                (state.sqrtPriceX96, state.tick, observationIndex, observationCardinality);
        } else {
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;

        if (_zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFeesCollected0 += state.protocolFee;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFeesCollected1 += state.protocolFee;
        }

        (amount0, amount1) = _zeroForOne == exactInput
            ? (_amount - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, _amount - state.amountSpecifiedRemaining);

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

        emit Swap(msg.sender, _recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
    }

    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock notPaused onlyFactory {
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
        notPaused
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

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data)
        external
        override
        notPaused
        lock
        noDelegateCall
    {
        uint128 _liquidity = liquidity;
        require(_liquidity > 0, "L");

        (uint24 swapFee,, address feeRecipient) = protocolFees.getFees();
        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee + swapFee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee + swapFee, 1e6);
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();

        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        ISupaSwapFlashCallback(msg.sender).supaSwapFlashCallback(int256(fee0), int256(fee1), data);

        uint256 balance0After = balance0();
        uint256 balance1After = balance1();

        require(balance0Before.add(fee0) <= balance0After, "F0");
        require(balance1Before.add(fee1) <= balance1After, "F1");

        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        if (paid0 > 0) {
            uint8 feeProtocol0 = slot0.feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
            if (uint128(fees0) > 0) {
                protocolFeesCollected0 += uint128(fees0);
                if (feeRecipient != address(0)) {
                    TransferHelper.safeTransfer(token0, feeRecipient, fees0);
                }
            }
            feeGrowthGlobal0X128 += FullMath.mulDiv(paid0 - fees0, FixedPoint128.Q128, _liquidity);
        }
        if (paid1 > 0) {
            uint8 feeProtocol1 = slot0.feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
            if (uint128(fees1) > 0) {
                protocolFeesCollected1 += uint128(fees1);
                if (feeRecipient != address(0)) {
                    TransferHelper.safeTransfer(token1, feeRecipient, fees1);
                }
            }
            feeGrowthGlobal1X128 += FullMath.mulDiv(paid1 - fees1, FixedPoint128.Q128, _liquidity);
        }

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
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
        sqrtPriceX96 = slot0.sqrtPriceX96;
        tick = slot0.tick;
        observationIndex = slot0.observationIndex;
        observationCardinality = slot0.observationCardinality;
        observationCardinalityNext = slot0.observationCardinalityNext;
        feeProtocol = slot0.feeProtocol;
        unlocked = slot0.unlocked;
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
        Position.Info memory pos = positions[key];
        _liquidity = pos.liquidity;
        feeGrowthInside0LastX128 = pos.feeGrowthInside0LastX128;
        feeGrowthInside1LastX128 = pos.feeGrowthInside1LastX128;
        tokensOwed0 = pos.tokensOwed0;
        tokensOwed1 = pos.tokensOwed1;
    }

    function getTickSpacing() external view override returns (int24) {
        return tickSpacing;
    }
}
