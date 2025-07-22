// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LowGasSafeMath} from "../../libraries/LowGasSafeMath.sol";
import {SafeCast} from "../../libraries/SafeCast.sol";
import {TickMath} from "../../libraries/TickMath.sol";
import {SqrtPriceMath} from "../../libraries/SqrtPriceMath.sol";
import {LiquidityMath} from "../../libraries/LiquidityMath.sol";
import {Position} from "../../libraries/Position.sol";
import {TransferHelper} from "../../libraries/TransferHelper.sol";
import {ISupaSwapMintCallback} from "../interfaces/callback/ISupaSwapMintCallback.sol";
import {IPool} from "../interfaces/IPool.sol";
import {NoDelegateCall} from "../NoDelegateCall.sol";
import {PoolOracle} from "../PoolOracle.sol";
import {IERC20Minimal} from "../../interfaces/IERC20Minimal.sol";
import {ILiquidityManager} from "../interfaces/manager/ILiquidityManager.sol";

contract LiquidityManager is NoDelegateCall, ILiquidityManager {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    address public immutable pool;
    address public immutable token0;
    address public immutable token1;
    address public immutable poolOracle;

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Collect(
        address indexed sender,
        address indexed recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0,
        uint128 amount1
    );
    event Burn(
        address indexed sender,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    error ZeroAmount();
    error InvalidTick();

    constructor(address _pool, address _token0, address _token1, address _poolOracle) {
        pool = _pool;
        token0 = _token0;
        token1 = _token1;
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

    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper || tickLower < TickMath.MIN_TICK || tickUpper > TickMath.MAX_TICK) {
            revert InvalidTick();
        }
    }

    function _modifyPosition(ModifyPositionParams memory params)
        private
        noDelegateCall
        returns (Position.Info memory position, int256 amount0, int256 amount1)
    {
        checkTicks(params.tickLower, params.tickUpper);
        Slot0 memory _slot0 = _getSlot0();
        position = _updatePosition(params.owner, params.tickLower, params.tickUpper, params.liquidityDelta);

        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                uint128 liquidityBefore = IPool(pool).getLiquidity();
                (uint16 observationIndex, uint16 observationCardinality) = PoolOracle(poolOracle).write(
                    _slot0.observationIndex,
                    uint32(block.timestamp),
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );
                IPool(pool).setSlot0(
                    _slot0.sqrtPriceX96,
                    _slot0.tick,
                    observationIndex,
                    observationCardinality,
                    _slot0.observationCardinalityNext,
                    _slot0.feeProtocol,
                    _slot0.unlocked
                );
                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(params.tickUpper), params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower), _slot0.sqrtPriceX96, params.liquidityDelta
                );
                IPool(pool).setLiquidity(LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta));
            } else {
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    function _updatePosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta)
        private
        returns (Position.Info memory position)
    {
        position = IPool(pool).getPosition(owner, tickLower, tickUpper);
        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            flippedLower = IPool(pool).updateTick(tickLower, liquidityDelta);
            flippedUpper = IPool(pool).updateTick(tickUpper, liquidityDelta);
            if (flippedLower) IPool(pool).tickBitmapFlipTick(tickLower);
            if (flippedUpper) IPool(pool).tickBitmapFlipTick(tickUpper);
        }

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            IPool(pool).getFeeGrowthInside(tickLower, tickUpper);
        IPool(pool).updatePosition(
            owner, tickLower, tickUpper, uint128(liquidityDelta), feeGrowthInside0X128, feeGrowthInside1X128
        );

        if (liquidityDelta < 0) {
            if (flippedLower) IPool(pool).clearTick(tickLower);
            if (flippedUpper) IPool(pool).clearTick(tickUpper);
        }
    }

    function mint(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _liquidity, bytes calldata _data)
        external
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
        returns (uint128 amount0, uint128 amount1)
    {
        Position.Info memory position = IPool(pool).getPosition(msg.sender, _tickLower, _tickUpper);
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
        returns (uint256 amount0, uint256 amount1)
    {
        if (_liquidity == 0) revert ZeroAmount();
        (Position.Info memory position, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: -int256(uint256(_liquidity)).toInt128()
            })
        );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) =
                (position.tokensOwed0 + uint128(amount0), position.tokensOwed1 + uint128(amount1));
        }

        emit Burn(msg.sender, _tickLower, _tickUpper, _liquidity, amount0, amount1);
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
