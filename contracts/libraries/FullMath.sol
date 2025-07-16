// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  512‑bit mul‑div helpers
/// @notice Enables full‑precision (a * b) / denominator without overflow
/// @dev    Mirrors Uniswap V3’s FullMath but trimmed for ^0.8.x and better naming.

library FullMath {
    /* ----------mulDiv----------*/

    /// @notice Custom errors for better gas optimization
    error InvalidDenominator();
    error OverFlow();

    /// @notice Calculates floor(a × b ÷ denominator) with full precision
    /// @dev    Reverts if denominator == 0 or result overflows uint256.
    function mulDiv(uint256 _a, uint256 _b, uint256 _denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512‑bit multiply [prod1 prod0] = a * b
            uint256 prod0; // low 256 bits
            uint256 prod1; // high 256 bits
            assembly {
                let mm := mulmod(_a, _b, not(0))
                prod0 := mul(_a, _b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non‑overflow cases (prod1 == 0) early
            if (prod1 == 0) {
                if (_denominator <= 0) revert InvalidDenominator();
                assembly {
                    result := div(prod0, _denominator)
                }
                return result;
            }

            // Make sure division result fits into 256 bits and denominator > high part
            if (_denominator < prod1) revert OverFlow();

            ///////////////////////////////////////////////
            // 512 by 256 division ‑‑ Hensel lifting trick
            ///////////////////////////////////////////////

            // 1. Subtract remainder from [prod1 prod0] so it becomes divisible by denominator
            uint256 remainder;
            assembly {
                remainder := mulmod(_a, _b, _denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // 2. Factor powers of two out of denominator and compute largest power‑of‑two divisor of denominator
            //    Always >= 1.
            uint256 twos = _denominator & (~_denominator + 1);
            assembly {
                _denominator := div(_denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1) // 2^256 / twos
            }

            // 3. Shift bits from prod1 into prod0
            prod0 |= prod1 * twos;

            // 4. Compute modular inverse of denominator mod 2^256
            uint256 inv = (3 * _denominator) ^ 2;
            inv *= 2 - _denominator * inv; // inverse mod 2^8
            inv *= 2 - _denominator * inv; // inverse mod 2^16
            inv *= 2 - _denominator * inv; // inverse mod 2^32
            inv *= 2 - _denominator * inv; // inverse mod 2^64
            inv *= 2 - _denominator * inv; // inverse mod 2^128
            inv *= 2 - _denominator * inv; // inverse mod 2^256

            // 5. Multiply by modular inverse to get the result modulo 2^256
            result = prod0 * inv;
            return result; // exact division
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   mulDivRoundingUp
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Calculates ceil(a × b ÷ denominator) with full precision
    /// @dev    Same caveats as mulDiv. Reverts on overflow/denominator == 0.
    function mulDivRoundingUp(uint256 _a, uint256 _b, uint256 _denominator) internal pure returns (uint256 result) {
        result = mulDiv(_a, _b, _denominator);
        unchecked {
            if (mulmod(_a, _b, _denominator) != 0) {
                // add 1 if remainder > 0
                require(result < type(uint256).max, "overflow");
                result += 1;
            }
        }
    }
}
