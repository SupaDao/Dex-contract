// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFactory} from "../core/interfaces/IFactory.sol";
import {ISupaSwapMintCallback} from "../core/interfaces/callback/ISupaSwapMintCallback.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {PoolAddress} from "../libraries/PoolAddress.sol";
import {LiquidityMath} from "../libraries/LiquidityMath.sol";
import {ImutableState} from "./ImutableStates.sol";
import {Payment} from "./Payment.sol";
import {CallbackValidation} from "../libraries/CallbackValidation.sol";
import {IPool} from "../core/interfaces/IPool.sol";

abstract contract LiquidityManagement is ISupaSwapMintCallback, ImutableState, Payment {
    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    error SlipageCheck();

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    function supaSwapMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        if (amount0Owed > 0) pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }

    function addLiquidity(AddLiquidityParams memory params)
        internal
        returns (uint128 liquidity, uint256 amount0, uint256 amount1, IPool pool)
    {
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee});

        pool = IPool(PoolAddress.computeAddress(factory, poolKey.token0, poolKey.token1, poolKey.fee));

        // compute the liquidity amount
        {
            (uint160 sqrtPriceX96,,,,,,) = pool.getSlot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

            liquidity = LiquidityMath.getLiquidityForAmounts(
                sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, params.amount0Desired, params.amount1Desired
            );
        }

        (amount0, amount1) = pool.mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
        );
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert SlipageCheck();
    }
}
