// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "./interfaces/IPool.sol";
import {ISupaSwapCallback} from "./interfaces/callback/ISupaSwapCallback.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {FixedPoint128} from "../libraries/FixedPoint128.sol";
import {LiquidityMath} from "../libraries/LiquidityMath.sol";
import {FeeMath} from "../libraries/FeeMath.sol";
import {OracleMath} from "../libraries/OracleMath.sol";
import {FullMath} from "../libraries/FullMath.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {IPoolDeployer} from "./interfaces/IPoolDeployer.sol";
import {TickBitmap} from "../libraries/TickBitmap.sol";
import {Tick} from "../libraries/Tick.sol";
import {SwapMath} from "../libraries/SwapMath.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {ISupaSwapMintCallback} from "./interfaces/callback/ISupaSwapMintCallback.sol";

/// @title  SupaSwap Pool
/// @notice Handles swaps, liquidity, and fees for a single token pair and fee tier
contract Pool is IPool {
    using SafeCast for uint256;
    using SafeCast for int256;

    //----------State Variables----------//
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;

    /// @notice Total liquidity in range
    uint128 public liquidity;

    /// @notice Packed slot containing price, tick, and oracle configs
    Slot0 public slot0;

    uint256 public balance0;
    uint256 public balance1;
    mapping(int24 => Tick.Info) public ticks;

    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    uint256 public protocolFeesCollected0;
    uint256 public protocolFeesCollected1;

    uint256 public tickCumulative;
    uint160 public secondsPerLiquidityCumulativeX128;
    uint32 public lastUpdateTimestamp;
    mapping(int16 => uint256) public tickBitmap;

    uint24 internal constant FEE_UNITS = 1000;
    uint24 internal constant PROTOCOL_FEE_UNITS = 10000;
    uint24 internal constant AMM_FEE = 3; // 0.3%
    uint24 internal constant PROTOCOL_FEE = 1;

    /// @notice Oracle state and position mapping (to be added in next steps)
    /// @dev Will store liquidity per LP position and oracle observations
    mapping(bytes32 => Position) public positions;
    Observation[] public observations;

    // ───────────── Events & Errors ─────────────
    error AlreadyInitialized();
    error NotFactory();
    error ZeroAmount();
    error InvalidTick();
    error Locked();
    error InsufficientLiquidity();
    error InvalidSqrtPriceLimit();

    event Initialize(uint160 sqrtPriceX96, int24 tick);

    // ───────────── Constructor ─────────────//

    constructor() {
        IPoolDeployer.Parameters memory params = IPoolDeployer(msg.sender).parameters();
        factory = params.factory;
        token0 = params.token0;
        token1 = params.token1;
        fee = params.fee;
        tickSpacing = params.tickSpacing;
    }

    // ───────────── Modifiers ─────────────//
    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    modifier lock() {
        if (slot0.unlocked == false) revert Locked();
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    /// @notice Initializes the pool with the starting price
    /// @param _sqrtPriceX96 The initial sqrt(token1/token0) Q64.96
    function initialize(uint160 _sqrtPriceX96) external onlyFactory lock {
        if (slot0.sqrtPriceX96 != 0) revert AlreadyInitialized();
        int24 tick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);
        observations.push(
            Observation({
                blockTimestamp: uint32(block.timestamp),
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 0,
                initialized: true
            })
        );
        slot0 = Slot0({
            sqrtPriceX96: _sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: 1,
            observationCardinalityNext: 1,
            feeProtocol: 0,
            unlocked: true
        });
        lastUpdateTimestamp = uint32(block.timestamp);
        tickCumulative = 0;
        secondsPerLiquidityCumulativeX128 = 0;
        emit Initialize(_sqrtPriceX96, tick);
    }

    function mint(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _liquidity, bytes calldata _data)
        external
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        if (_liquidity == 0) revert ZeroAmount();
        if (_tickLower >= _tickUpper) revert InvalidTick();

        uint160 sqrtPriceX96 = slot0.sqrtPriceX96;
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickUpper);

        (amount0, amount1) = _calculateLiquidityAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, _liquidity);

        uint256 fee0 = (amount0 * 1) / 10000;
        uint256 fee1 = (amount1 * 1) / 10000;
        amount0 += fee0;
        amount1 += fee1;

        transferTokens(msg.sender, amount0, amount1);

        balance0 += amount0;
        balance1 += amount1;
        liquidity += _liquidity;
        ISupaSwapMintCallback(msg.sender).supaSwapMintCallback(amount0, amount1, _data);

        bytes32 key = getPositionKey(_recipient, _tickLower, _tickUpper);

        updatePosition(key, _liquidity, feeGrowthGlobal0X128, feeGrowthGlobal1X128);

        updateTick(
            _tickLower,
            slot0.tick,
            int128(_liquidity),
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            int56(int256(tickCumulative)),
            secondsPerLiquidityCumulativeX128,
            uint32(block.timestamp),
            false
        );
        updateTick(
            _tickUpper,
            slot0.tick,
            -int128(_liquidity),
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            int56(int256(tickCumulative)),
            secondsPerLiquidityCumulativeX128,
            uint32(block.timestamp),
            true
        );

        writeObservation();

        emit Mint(msg.sender, _recipient, _tickLower, _tickUpper, _liquidity, amount0, amount1);
    }

    function burn(int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        if (_liquidity == 0) revert ZeroAmount();
        if (_tickLower >= _tickUpper) revert InvalidTick();

        bytes32 key = getPositionKey(msg.sender, _tickLower, _tickUpper);
        Position storage pos = positions[key];

        if (pos.liquidity < _liquidity) revert InsufficientLiquidity();
        // Update lower tick
        updateTick(
            _tickLower,
            slot0.tick,
            -int128(_liquidity),
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            int56(int256(tickCumulative)),
            secondsPerLiquidityCumulativeX128,
            uint32(block.timestamp),
            false
        );
        updateTick(
            _tickUpper,
            slot0.tick,
            int128(_liquidity),
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            int56(int256(tickCumulative)),
            secondsPerLiquidityCumulativeX128,
            uint32(block.timestamp),
            true
        );

        updateBurnPosition(pos, _liquidity);

        // 4. Calculate token0/token1 from liquidity removed (mocked for now)
        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) =
            (TickMath.getSqrtRatioAtTick(_tickLower), TickMath.getSqrtRatioAtTick(_tickUpper));
        (amount0, amount1) = _calculateLiquidityAmounts(slot0.sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, _liquidity);

        // 5. Apply 0.01% fee
        uint256 fee0 = (amount0 * 1) / 10000;
        uint256 fee1 = (amount1 * 1) / 10000;
        amount0 -= fee0;
        amount1 -= fee1;

        // 6. Decrease global liquidity
        liquidity -= _liquidity;

        // 7. Update pool token balances
        balance0 -= amount0;
        balance1 -= amount1;

        // Tokens are NOT transferred here — LP must call `collect()`
        writeObservation();

        emit Burn(msg.sender, _tickLower, _tickUpper, _liquidity, amount0, amount1);
    }

    function collect(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _amount0, uint128 _amount1)
        external
        returns (uint128 amount0, uint128 amount1)
    {
        bytes32 key = getPositionKey(msg.sender, _tickLower, _tickUpper);
        Position storage pos = positions[key];

        uint128 owed0 = pos.tokensOwed0;
        uint128 owed1 = pos.tokensOwed1;

        amount0 = _amount0 > owed0 ? owed0 : _amount0;
        amount1 = _amount1 > owed1 ? owed1 : _amount1;

        pos.tokensOwed0 -= amount0;
        pos.tokensOwed1 -= amount1;

        if (amount0 > 0) {
            balance0 -= amount0;
            TransferHelper.safeTransfer(token0, _recipient, amount0);
        }

        if (amount1 > 0) {
            balance1 -= amount1;
            TransferHelper.safeTransfer(token1, _recipient, amount1);
        }

        emit Collect(msg.sender, _recipient, _tickLower, _tickUpper, amount0, amount1);
    }

    function swap(
        address _recipient,
        bool _zeroForOne,
        int256 _amount,
        uint160 _sqrtPriceLimitX96,
        bytes calldata _data
    ) external lock returns (int256 amount0, int256 amount1) {
        if (_amount == 0) revert ZeroAmount();

        if (_zeroForOne) {
            if (_sqrtPriceLimitX96 >= slot0.sqrtPriceX96 || _sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
                revert InvalidSqrtPriceLimit();
            }
        } else {
            if (_sqrtPriceLimitX96 <= slot0.sqrtPriceX96 || _sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) {
                revert InvalidSqrtPriceLimit();
            }
        }

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: _amount,
            amountCalculated: 0,
            sqrtPriceX96: slot0.sqrtPriceX96,
            tick: slot0.tick,
            feeGrowthGlobalX128: _zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            protocolFee: 0,
            liquidity: liquidity
        });

        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != _sqrtPriceLimitX96) {
            StepComputations memory step;

            (step.tickNext, step.initialized) =
                TickBitmap.nextInitializedTickWithinOneWord(tickBitmap, state.tick, _zeroForOne, tickSpacing);
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            if (_zeroForOne && step.sqrtPriceNextX96 < _sqrtPriceLimitX96) {
                step.sqrtPriceNextX96 = _sqrtPriceLimitX96;
            } else if (!_zeroForOne && step.sqrtPriceNextX96 > _sqrtPriceLimitX96) {
                step.sqrtPriceNextX96 = _sqrtPriceLimitX96;
            }

            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96, step.sqrtPriceNextX96, state.liquidity, state.amountSpecifiedRemaining, AMM_FEE
            );
            uint256 feeDelta = (step.feeAmount * FixedPoint128.Q128) / state.liquidity;
            if (_zeroForOne) {
                feeGrowthGlobal0X128 += feeDelta;
            } else {
                feeGrowthGlobal1X128 += feeDelta;
            }

            state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
            state.amountCalculated += _zeroForOne ? -step.amountOut.toInt256() : step.amountOut.toInt256();

            uint256 protocolFee = (step.feeAmount * PROTOCOL_FEE) / PROTOCOL_FEE_UNITS;
            if (_zeroForOne) {
                protocolFeesCollected0 += protocolFee;
                balance0 += step.amountIn + step.feeAmount;
                balance1 -= step.amountOut;
            } else {
                protocolFeesCollected1 += protocolFee;
                balance1 += step.amountIn + step.feeAmount;
                balance0 -= step.amountOut;
            }

            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityDelta = Tick.cross(
                        ticks,
                        step.tickNext,
                        feeGrowthGlobal0X128,
                        feeGrowthGlobal1X128,
                        int56(int256(tickCumulative)),
                        secondsPerLiquidityCumulativeX128,
                        uint32(block.timestamp - lastUpdateTimestamp)
                    );

                    state.liquidity = _zeroForOne
                        ? state.liquidity - uint128(-liquidityDelta)
                        : state.liquidity + uint128(liquidityDelta);
                }
                state.tick = _zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }

            tickCumulative += uint256(int256(state.tick));
            secondsPerLiquidityCumulativeX128 +=
                uint160((block.timestamp - lastUpdateTimestamp) << 128 / state.liquidity);
            lastUpdateTimestamp = uint32(block.timestamp);
        }

        // Update global slot0 state
        (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);

        // Callback
        amount0 = _zeroForOne ? int256(_amount - state.amountSpecifiedRemaining) : -state.amountCalculated;
        amount1 = _zeroForOne ? -state.amountCalculated : int256(_amount - state.amountSpecifiedRemaining);

        ISupaSwapCallback(msg.sender).supaSwapCallback(amount0, amount1, _data);

        // Settlement (same as before)
        if (amount0 > 0) {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), uint256(amount0));
        } else if (amount0 < 0) {
            TransferHelper.safeTransfer(token0, _recipient, uint256(-amount0));
        }

        if (amount1 > 0) {
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), uint256(amount1));
        } else if (amount1 < 0) {
            TransferHelper.safeTransfer(token1, _recipient, uint256(-amount1));
        }

        emit Swap(msg.sender, _recipient, amount0, amount1, slot0.sqrtPriceX96, liquidity, slot0.tick);
    }

    /// @notice Observe the cumulative tick and secondsPerLiquidity for past timestamps
    /// @param secondsAgos Array of seconds ago to query (e.g., [0, 30] for 30s TWAP)
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        require(secondsAgos.length > 0, "Empty");

        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);

        uint32 currentTime = uint32(block.timestamp);
        // Observation memory latest = observations[slot0.observationIndex];

        for (uint256 i = 0; i < secondsAgos.length; i++) {
            uint32 target = currentTime - secondsAgos[i];

            if (secondsAgos[i] == 0) {
                // Latest observation
                tickCumulatives[i] = int56(int256(tickCumulative));
                secondsPerLiquidityCumulativeX128s[i] = secondsPerLiquidityCumulativeX128;
            } else {
                (Observation memory beforeOrAt, Observation memory atOrAfter) = getSurroundingObservations(target);

                // Linear interpolation
                uint32 delta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
                uint32 targetDelta = target - beforeOrAt.blockTimestamp;

                int56 tickDelta = atOrAfter.tickCumulative - beforeOrAt.tickCumulative;
                uint160 secDelta =
                    atOrAfter.secondsPerLiquidityCumulativeX128 - beforeOrAt.secondsPerLiquidityCumulativeX128;

                tickCumulatives[i] =
                    beforeOrAt.tickCumulative + (tickDelta * int56(uint56(targetDelta)) / int56(uint56(delta)));
                secondsPerLiquidityCumulativeX128s[i] =
                    beforeOrAt.secondsPerLiquidityCumulativeX128 + (secDelta * targetDelta / delta);
            }
        }
    }

    ///@notice Helper functions
    /// @notice Hashes position key using owner, tickLower, and tickUpper
    function getPositionKey(address _owner, int24 _tickLower, int24 _tickUpper) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_owner, _tickLower, _tickUpper));
    }

    function getSurroundingObservations(uint32 target)
        internal
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint16 cardinality = slot0.observationCardinality;
        uint16 index = slot0.observationIndex;
        uint16 i = index;

        // Loop backwards from the most recent
        for (uint16 j = 0; j < cardinality; j++) {
            Observation memory obs = observations[i];

            if (obs.initialized && obs.blockTimestamp <= target) {
                beforeOrAt = obs;
                uint16 next = (i + 1) % cardinality;
                atOrAfter = observations[next].initialized ? observations[next] : obs;
                return (beforeOrAt, atOrAfter);
            }

            i = (i == 0) ? cardinality - 1 : i - 1;
        }

        revert("Observation not found");
    }

    function writeObservation() internal {
        uint16 index = slot0.observationIndex;
        uint16 cardinality = slot0.observationCardinality;
        uint32 blockTs = uint32(block.timestamp);

        // Get previous
        Observation memory last = observations[index];

        if (last.blockTimestamp == blockTs) {
            return; // Already written
        }

        // Compute deltas
        int56 tickCumul = int56(int256(tickCumulative));
        uint160 secPerLiqX128 = secondsPerLiquidityCumulativeX128;

        // Increment index and overwrite oldest
        uint16 nextIndex = (index + 1) % cardinality;
        observations[nextIndex] = Observation({
            blockTimestamp: blockTs,
            tickCumulative: tickCumul,
            secondsPerLiquidityCumulativeX128: secPerLiqX128,
            initialized: true
        });

        slot0.observationIndex = nextIndex;
    }

    /// @notice Grows the observation array size (ring buffer)
    /// @param newCardinalityNext New desired size
    function increaseObservationCardinalityNext(uint16 newCardinalityNext) external {
        require(newCardinalityNext > slot0.observationCardinalityNext, "Must increase");
        slot0.observationCardinalityNext = newCardinalityNext;

        // uint16 current = uint16(observations.length);
        while (observations.length < newCardinalityNext) {
            observations.push();
        }
        slot0.observationCardinality = newCardinalityNext;
    }

    function _calculateLiquidityAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 _liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        return LiquidityMath.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, _liquidity);
    }

    function updateBurnPosition(Position memory pos, uint128 _liquidity) internal view {
        uint256 deltaFee0 = feeGrowthGlobal0X128 - pos.feeGrowthInside0LastX128;
        uint256 deltaFee1 = feeGrowthGlobal1X128 - pos.feeGrowthInside1LastX128;

        uint128 feeOwed0 = uint128(FullMath.mulDiv(deltaFee0, _liquidity, FixedPoint128.Q128));
        uint128 feeOwed1 = uint128(FullMath.mulDiv(deltaFee1, _liquidity, FixedPoint128.Q128));

        // 3. Update position
        pos.liquidity -= _liquidity;
        pos.feeGrowthInside0LastX128 = feeGrowthGlobal0X128;
        pos.feeGrowthInside1LastX128 = feeGrowthGlobal1X128;
        pos.tokensOwed0 += feeOwed0;
        pos.tokensOwed1 += feeOwed1;
    }

    function updatePosition(
        bytes32 _key,
        uint128 _liquidityAmount,
        uint256 _feeGrowthGlobal0X128,
        uint256 _feeGrowthGlobal1X128
    ) internal returns (uint128 owed0, uint128 owed1) {
        Position storage pos = positions[_key];
        if (pos.liquidity > 0) {
            uint256 delta0 = _feeGrowthGlobal0X128 - pos.feeGrowthInside0LastX128;
            uint256 delta1 = _feeGrowthGlobal1X128 - pos.feeGrowthInside1LastX128;
            owed0 = uint128(FullMath.mulDiv(delta0, pos.liquidity, FixedPoint128.Q128));
            owed1 = uint128(FullMath.mulDiv(delta1, pos.liquidity, FixedPoint128.Q128));
            pos.tokensOwed0 += owed0;
            pos.tokensOwed1 += owed1;
        }
        pos.liquidity += _liquidityAmount;
        pos.feeGrowthInside0LastX128 = _feeGrowthGlobal0X128;
        pos.feeGrowthInside1LastX128 = _feeGrowthGlobal1X128;
    }

    function updateTick(
        int24 _tick,
        int24 _currentTick,
        int128 _liquidityDelta,
        uint256 _feeGrowthGlobal0X128,
        uint256 _feeGrowthGlobal1X128,
        int56 _tickCumul,
        uint160 _secPerLiqX128,
        uint32 _timestamp,
        bool _upper
    ) internal returns (bool flipped) {
        flipped = Tick.update(
            ticks,
            _tick,
            _currentTick,
            _liquidityDelta,
            _feeGrowthGlobal0X128,
            _feeGrowthGlobal1X128,
            _tickCumul,
            _secPerLiqX128,
            _timestamp,
            _upper
        );
        if (flipped) {
            TickBitmap.flipTick(tickBitmap, tickSpacing);
        }
    }

    function transferTokens(address sender, uint256 amount0, uint256 amount1) internal {
        if (amount0 > 0) TransferHelper.safeTransferFrom(token0, sender, address(this), amount0);
        if (amount1 > 0) TransferHelper.safeTransferFrom(token1, sender, address(this), amount1);
    }

    function collectProtocolFees(address to) external onlyFactory {
        TransferHelper.safeTransfer(token0, to, protocolFeesCollected0);
        TransferHelper.safeTransfer(token1, to, protocolFeesCollected1);
        protocolFeesCollected0 = 0;
        protocolFeesCollected1 = 0;
    }

    function tokens() external view returns (address tokenA, address tokenB) {
        return (token0, token1);
    }

    function getSlot0()
        external
        view
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

    function getLiquidity() external view returns (uint128) {
        return liquidity;
    }

    function getPositions(bytes32 key)
        external
        view
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory pos = positions[key];
        _liquidity = pos.liquidity;
        feeGrowthInside0LastX128 = pos.feeGrowthInside0LastX128;
        feeGrowthInside1LastX128 = pos.feeGrowthInside1LastX128;
        tokensOwed0 = pos.tokensOwed0;
        tokensOwed1 = pos.tokensOwed1;
    }
}
