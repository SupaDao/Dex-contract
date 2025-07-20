// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "../core/interfaces/IPool.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {SqrtPriceMath} from "../libraries/SqrtPriceMath.sol";
import {AmountMath} from "../libraries/AmountMath.sol";
import {ISupaSwapQuoter} from "./interfaces/ISupaSwapQuoter.sol";
import {PoolAddress} from "../libraries/PoolAddress.sol";
import {Path} from "../libraries/Path.sol";

contract Quoter is ISupaSwapQuoter {
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee, // Optional: if you support multiple fee tiers
        uint256 amountIn
    ) public view override returns (uint256 amountOut) {
        IPool pool = getPool(tokenIn, tokenOut, fee);

        (uint160 sqrtPriceX96,,,,,,) = pool.getSlot0();
        uint128 liquidity = pool.getLiquidity();

        bool zeroForOne = tokenIn < tokenOut;

        uint160 sqrtPriceAfterX96 =
            SqrtPriceMath.getNextSqrtPriceFromInput(sqrtPriceX96, liquidity, amountIn, zeroForOne);

        amountOut = AmountMath.computeExactAmountOut(sqrtPriceX96, sqrtPriceAfterX96, liquidity, zeroForOne);
    }

    /// @notice Computes required input amount for exact output swap
    function quoteExactOutputSingle(address tokenIn, address tokenOut, uint24 fee, uint256 amountOut)
        public
        view
        override
        returns (uint256 amountIn)
    {
        IPool pool = getPool(tokenIn, tokenOut, fee);

        (uint160 sqrtPriceX96,,,,,,) = pool.getSlot0();
        uint128 liquidity = pool.getLiquidity();

        bool zeroForOne = tokenIn < tokenOut;

        uint160 sqrtPriceAfterX96 =
            SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtPriceX96, liquidity, amountOut, zeroForOne);

        amountIn = AmountMath.computeExactAmountIn(sqrtPriceX96, sqrtPriceAfterX96, liquidity, zeroForOne);
    }

    function quoteExactInput(QuoteExactInputParams calldata params)
        external
        view
        override
        returns (uint256 amountOut)
    {
        bytes memory path = params.path;
        uint256 amountIn = params.amountIn;

        while (path.length >= 43) {
            (address tokenIn, address tokenOut, uint24 fee) = Path.decodeFirstPool(path);
            amountIn = quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn);
            path = Path.skipToken(path); // move to the next tokenOut as new tokenIn
        }

        amountOut = amountIn;
    }

    function quoteExactOutput(QuoteExactOutputParams calldata params)
        external
        view
        override
        returns (uint256 amountIn)
    {
        bytes memory path = params.path;
        uint256 amountOut = params.amountOut;

        while (path.length >= 43) {
            (address tokenOut, address tokenIn, uint24 fee) = Path.decodeLastPool(path);
            amountOut = quoteExactOutputSingle(tokenIn, tokenOut, fee, amountOut);
            path = Path.skipLastToken(path); // move to the next tokenOut as new tokenIn (in reverse)
        }

        amountIn = amountOut;
    }

    /// @dev Replace with your factory + hash logic
    function computePoolAddress(address tokenA, address tokenB, uint24 fee) internal view returns (address pool) {
        return PoolAddress.computeAddress(factory, tokenA, tokenB, fee);
    }

    function getPool(address tokenA, address tokenB, uint24 fee) internal view returns (IPool) {
        PoolAddress.PoolKey memory key = PoolAddress.getPoolKey(tokenA, tokenB, fee);
        return IPool(PoolAddress.computeAddress(factory, key.token0, key.token1, key.fee));
    }
}
