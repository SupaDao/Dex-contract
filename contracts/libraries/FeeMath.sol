// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {FullMath} from "./FullMath.sol";
import {FixedPoint128} from "./FixedPoint128.sol";

/// @title  FeeMath
/// @notice Safely calculates fee growth over time per unit liquidity

library FeeMath {
    /// @notice Custom errors.
    error ZeroLiquidity();
    error Overflow();

    /// @notice Computes the fee growth per unit of liquidity (Q128.128)
    /// @param _amount The amount of token fees collected (raw tokens)
    /// @param _liquidity The total active liquidity in the current tick
    /// @return feeGrowthInsideX128 Fee growth scaled by Q128
    function computeFeeGrowth(uint256 _amount, uint128 _liquidity)
        internal
        pure
        returns (uint256 feeGrowthInsideX128)
    {
        if (_liquidity == 0) revert ZeroLiquidity();
        feeGrowthInsideX128 = FullMath.mulDiv(_amount, FixedPoint128.Q128, _liquidity);
        if (feeGrowthInsideX128 > type(uint256).max) revert Overflow();
    }

    /// @notice Applies fee growth to an LP’s position to calculate earned fees
    /// @param _feeGrowthInsideX128 Δ fee growth over time (Q128.128)
    /// @param _liquidity Position's liquidity
    /// @return amount Token amount owed to the position

    function applyFeeGrowth(uint256 _feeGrowthInsideX128, uint128 _liquidity) internal pure returns (uint256 amount) {
        amount = FullMath.mulDiv(_feeGrowthInsideX128, _liquidity, FixedPoint128.Q128);
    }
}
