// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "./interfaces/IPool.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {Tick} from "../libraries/Tick.sol";
import {TickBitmap} from "../libraries/TickBitmap.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {IPoolDeployer} from "./interfaces/IPoolDeployer.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {Position} from "../libraries/Position.sol";
import {PoolOracle} from "./PoolOracle.sol";
import {IFlashTokenManager} from "./interfaces/manager/IFlashTokenManager.sol";
import {ILiquidityManager} from "./interfaces/manager/ILiquidityManager.sol";
import {ISwapManager} from "./interfaces/manager/ISwapManager.sol";
import {FlashTokenManager} from "./manager/FlashTokenManager.sol";
import {LiquidityManager} from "./manager/LiquidityManager.sol";
import {SwapManager} from "./manager/SwapManager.sol";

/// @title  SupaSwap Pool
/// @notice Handles swaps, liquidity, and fees for a single token pair and fee tier
contract Pool is IPool, NoDelegateCall {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    //----------Managers----------//
    IFlashTokenManager private immutable flashTokenManager;
    ILiquidityManager private immutable liquidityManager;
    ISwapManager private immutable swapManager;

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
    PoolOracle private immutable poolOracle;

    //----------Errors----------//
    error AlreadyInitialized();
    error NotFactory();
    error NotPool();
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

    modifier onlyPool() {
        if (msg.sender != address(this)) revert NotPool();
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
        flashTokenManager = IFlashTokenManager(address(new FlashTokenManager(address(this), token0, token1, fee)));
        liquidityManager =
            ILiquidityManager(address(new LiquidityManager(address(this), token0, token1, address(poolOracle))));
        swapManager = ISwapManager(address(new SwapManager(address(this), token0, token1, fee, address(poolOracle))));
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
        return liquidityManager.mint(_recipient, _tickLower, _tickUpper, _liquidity, _data);
    }

    function collect(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _amount0, uint128 _amount1)
        external
        override
        lock
        returns (uint128 amount0, uint128 amount1)
    {
        return liquidityManager.collect(_recipient, _tickLower, _tickUpper, _amount0, _amount1);
    }

    function burn(int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        override
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        return liquidityManager.burn(_tickLower, _tickUpper, _liquidity);
    }

    function swap(
        address _recipient,
        bool _zeroForOne,
        int256 _amount,
        uint160 _sqrtPriceLimitX96,
        bytes calldata _data
    ) external override returns (int256 amount0, int256 amount1) {
        return swapManager.swap(_recipient, _zeroForOne, _amount, _sqrtPriceLimitX96, _data);
    }

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data)
        external
        override
        lock
        noDelegateCall
    {
        flashTokenManager.flash(recipient, amount0, amount1, data);
    }

    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock onlyFactory {
        flashTokenManager.setFeeProtocol(feeProtocol0, feeProtocol1);
    }

    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        override
        lock
        onlyFactory
        returns (uint128 amount0, uint128 amount1)
    {
        return flashTokenManager.collectProtocol(recipient, amount0Requested, amount1Requested);
    }

    /// @dev Collect helpler function to update state variable from Flash TokenManager
    function addProtocolFeesCollected0(uint128 amount) external override onlyPool {
        protocolFeesCollected0 += amount;
    }

    function addProtocolFeesCollected1(uint128 amount) external override onlyPool {
        protocolFeesCollected1 += amount;
    }

    function setFeeGrowthGlobal0X128(uint256 _feeGrowthGlobal0X128) external override onlyPool {
        feeGrowthGlobal0X128 = _feeGrowthGlobal0X128;
    }

    function setFeeGrowthGlobal1X128(uint256 _feeGrowthGlobal1X128) external override onlyPool {
        feeGrowthGlobal1X128 = _feeGrowthGlobal1X128;
    }

    function setSlot0FeeProtocol(uint8 feeProtocol) external override onlyPool {
        require(feeProtocol >= 0 && feeProtocol <= 15, "Invalid fee protocol");
        slot0.feeProtocol = feeProtocol + (slot0.feeProtocol & 0xF0);
    }

    function subProtocolFeesCollected0(uint128 amount) external override onlyPool {
        require(amount <= protocolFeesCollected0, "Insufficient protocol fees collected");
        protocolFeesCollected0 -= amount;
    }

    function subProtocolFeesCollected1(uint128 amount) external override onlyPool {
        require(amount <= protocolFeesCollected1, "Insufficient protocol fees collected");
        protocolFeesCollected1 -= amount;
    }

    ///@dev End function for Flash token helper.

    /// @dev Helper function for Liquidity Manager
    function getPosition(address owner, int24 tickLower, int24 tickUpper)
        external
        view
        onlyPool
        returns (Position.Info memory position)
    {
        return positions.get(owner, tickLower, tickUpper);
    }

    function setSlot0(
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    ) external override onlyPool {
        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: observationIndex,
            observationCardinality: observationCardinality,
            observationCardinalityNext: observationCardinalityNext,
            feeProtocol: feeProtocol,
            unlocked: unlocked
        });
    }

    function setLiquidity(uint128 _liquidity) external override onlyPool {
        liquidity = _liquidity;
    }

    function updateTick(int24 tick, int128 liquidityDelta) external override onlyPool returns (bool flipped) {
        uint32 time = uint32(block.timestamp);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = poolOracle.observeSingle(
            time, 0, slot0.tick, slot0.observationIndex, liquidity, slot0.observationCardinality
        );
        flipped = _ticks.update(
            tick,
            slot0.tick,
            liquidityDelta,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128,
            secondsPerLiquidityCumulativeX128,
            tickCumulative,
            time,
            false,
            maxLiquidityPerTick
        );
    }

    function tickBitmapFlipTick(int24 tick) external override onlyPool {
        tickBitmap.flipTick(tick, tickSpacing);
    }

    function getFeeGrowthInside(int24 tickLower, int24 tickUpper)
        external
        view
        override
        onlyPool
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        (feeGrowthInside0X128, feeGrowthInside1X128) =
            _ticks.getFeeGrowthInside(tickLower, tickUpper, slot0.tick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
    }

    function updatePosition(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) external override onlyPool {
        Position.Info storage position = positions.get(owner, tickLower, tickUpper);
        position.update(int128(liquidityDelta), feeGrowthInside0X128, feeGrowthInside1X128);
    }

    function clearTick(int24 tick) external override onlyPool {
        _ticks.clear(tick);
    }

    ///@dev end of Liquidity Manager helpers

    //@dev Helper functions for SwapManager
    function nextInitializedTick(int24 _tick, int24 _tickSpacing, bool _zeroForOne)
        external
        view
        override
        onlyPool
        returns (int24 tickNext, bool initialized)
    {
        (tickNext, initialized) = tickBitmap.nextInitializedTickWithinOneWord(_tick, _tickSpacing, _zeroForOne);
    }

    function crossTick(
        int24 _tickNext,
        uint256 _feeGrowthGlobalX128,
        uint160 _secondsPerLiquidityCumulativeX128,
        int56 _tickCumulative,
        uint32 _blockTime,
        bool zeroForOne
    ) external override onlyPool returns (int128 liquidityNet) {
        liquidityNet = _ticks.cross(
            _tickNext,
            (zeroForOne ? _feeGrowthGlobalX128 : feeGrowthGlobal0X128),
            (zeroForOne ? feeGrowthGlobal1X128 : _feeGrowthGlobalX128),
            _secondsPerLiquidityCumulativeX128,
            _tickCumulative,
            _blockTime
        );
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
