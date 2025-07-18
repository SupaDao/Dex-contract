// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {SafeCast} from "./SafeCast.sol";
import {FullMath} from "./FullMath.sol";
import {FixedPoint96} from "./FixedPoint96.sol";

library LiquidityMath {
    using SafeCast for uint256;

    error AddOverflow();
    error SubUnderflow();

    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }

    function addLiquidity(uint128 _a, uint128 _b) internal pure returns (uint128 c) {
        unchecked {
            c = _a + _b;
            if (c < _a) revert AddOverflow();
        }
    }

    function subLiquidity(uint128 _a, uint128 _b) internal pure returns (uint128 c) {
        if (_a < _b) revert SubUnderflow();
        unchecked {
            c = _a - _b;
        }
    }

    function getLiquidityForAmount0(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount0)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    function getLiquidityForAmount1(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96));
    }

    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    function getAmountsForLiquidity(
        uint160 _sqrtPriceX96,
        uint160 _sqrtRatioAX96,
        uint160 _sqrtRatioBX96,
        uint128 _liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (_sqrtRatioAX96 > _sqrtRatioBX96) {
            (_sqrtRatioAX96, _sqrtRatioBX96) = (_sqrtRatioBX96, _sqrtRatioAX96);
        }

        if (_sqrtPriceX96 <= _sqrtRatioAX96) {
            amount0 = _getAmount0(_sqrtRatioAX96, _sqrtRatioBX96, _liquidity);
        } else if (_sqrtPriceX96 < _sqrtRatioBX96) {
            amount0 = _getAmount0(_sqrtPriceX96, _sqrtRatioBX96, _liquidity);
            amount1 = _getAmount1(_sqrtRatioAX96, _sqrtPriceX96, _liquidity);
        } else {
            amount1 = _getAmount1(_sqrtRatioAX96, _sqrtRatioBX96, _liquidity);
        }
    }

    function _getAmount0(uint160 _sqrtA, uint160 _sqrtB, uint128 _L) private pure returns (uint256) {
        return FullMath.mulDiv(uint256(_L) << 96, _sqrtB - _sqrtA, uint256(_sqrtB) * _sqrtA);
    }

    function _getAmount1(uint160 _sqrtA, uint160 _sqrtB, uint128 _L) private pure returns (uint256) {
        return FullMath.mulDiv(_L, _sqrtB - _sqrtA, 1 << 96);
    }
}
