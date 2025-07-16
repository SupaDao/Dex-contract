// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

library LiquidityMath {
    error AddOverflow();
    error SubUnderflow();

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
}
