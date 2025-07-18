// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FullMath} from "./FullMath.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";

library AmountMath {
    error ZeroNumerator();
    error ZeroDenorminator();
    /// @notice Calculates amountOut for a given amountIn and price ratio
    /// @param amountIn Input amount of tokenIn
    /// @param priceNumerator Price numerator (tokenOut/tokenIn ratio)
    /// @param priceDenominator Price denominator
    /// @return amountOut Output amount of tokenOut

    function getAmountOut(uint256 amountIn, uint256 priceNumerator, uint256 priceDenominator)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (priceDenominator == 0) revert ZeroDenorminator();
        amountOut = FullMath.mulDiv(amountIn, priceNumerator, priceDenominator);
    }

    /// @notice Calculates amountIn needed for a desired amountOut and price ratio
    /// @param amountOut Desired output amount of tokenOut
    /// @param priceNumerator Price numerator (tokenOut/tokenIn ratio)
    /// @param priceDenominator Price denominator
    /// @return amountIn Required input amount of tokenIn
    function getAmountIn(uint256 amountOut, uint256 priceNumerator, uint256 priceDenominator)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (priceDenominator == 0) revert ZeroNumerator();
        amountIn = FullMath.mulDiv(amountOut, priceDenominator, priceNumerator);
    }

    /// @notice Computes the token input amount given price range and liquidity
    /// @param sqrtPriceStartX96 Starting sqrt price
    /// @param sqrtPriceEndX96 Ending sqrt price after swap step
    /// @param liquidity Current liquidity in the range
    /// @param zeroForOne Direction of swap: true if swapping token0 for token1
    /// @return amountIn Required token input for the price movement
    function computeExactAmountIn(
        uint160 sqrtPriceStartX96,
        uint160 sqrtPriceEndX96,
        uint128 liquidity,
        bool zeroForOne
    ) internal pure returns (uint256 amountIn) {
        return zeroForOne
            ? SqrtPriceMath.getAmount0Delta(sqrtPriceEndX96, sqrtPriceStartX96, liquidity, true)
            : SqrtPriceMath.getAmount1Delta(sqrtPriceStartX96, sqrtPriceEndX96, liquidity, true);
    }

    /// @notice Computes the token output amount given price range and liquidity
    /// @param sqrtPriceBefore Starting sqrt price
    /// @param sqrtPriceAfter Ending sqrt price after swap step
    /// @param liquidity Current liquidity in the range
    /// @param zeroForOne Direction of swap: true if swapping token0 for token1
    /// @return amountOut Output token received from the price movement
    function computeExactAmountOut(uint160 sqrtPriceBefore, uint160 sqrtPriceAfter, uint128 liquidity, bool zeroForOne)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (zeroForOne) {
            return SqrtPriceMath.getAmount1Delta(sqrtPriceAfter, sqrtPriceBefore, liquidity, false);
        } else {
            return SqrtPriceMath.getAmount0Delta(sqrtPriceBefore, sqrtPriceAfter, liquidity, false);
        }
    }
}
