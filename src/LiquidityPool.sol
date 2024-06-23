// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityPoolReward} from "./LiquidityPoolReward.sol";

error LiquidityPool__InsufficientLiquidity();
error LiquidityPool__InsufficientAllowance();

contract LiquidityPool {
    address public tokenA;
    address public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;
    uint256 public totalRewardDistributed;

    LiquidityPoolReward public liquidityPoolReward;

    constructor(address _tokenA, address _tokenB, address _liquidityPoolReward) {
        tokenA = _tokenA;
        tokenB = _tokenB;
        liquidityPoolReward = LiquidityPoolReward(_liquidityPoolReward); // Initialize the reward contract
    }

    function addLiquidity(uint256 amountA, uint256 amountB) public returns (uint256) {
        // Transfer token pairs
        uint256 allowanceA = IERC20(tokenA).allowance(msg.sender, address(this));
        uint256 allowanceB = IERC20(tokenB).allowance(msg.sender, address(this));

        if (allowanceA < amountA) {
            revert LiquidityPool__InsufficientAllowance();
        }

        if (allowanceB < amountB) {
            revert LiquidityPool__InsufficientAllowance();
        }

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        uint256 liquidityMinted;
        if (totalLiquidity == 0) {
            liquidityMinted = sqrt(amountA * amountB);
        } else {
            liquidityMinted = min((amountA * totalLiquidity) / reserveA, (amountB * totalLiquidity) / reserveB);
        }

        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;
        reserveA += amountA;
        reserveB += amountB;

        // Update the rewards for the user
        liquidityPoolReward.stake(liquidityMinted, msg.sender); // Notify reward contract about new liquidity

        return liquidityMinted;
    }

    function removeLiquidity(uint256 liquidityAmount) public returns (uint256, uint256) {
        if (liquidity[msg.sender] < liquidityAmount) {
            revert LiquidityPool__InsufficientLiquidity();
        }

        uint256 amountA = (liquidityAmount * reserveA) / totalLiquidity;
        uint256 amountB = (liquidityAmount * reserveB) / totalLiquidity;
        liquidity[msg.sender] -= liquidityAmount;
        totalLiquidity -= liquidityAmount;
        reserveA -= amountA;
        reserveB -= amountB;
        IERC20(tokenA).transfer(msg.sender, amountA);
        IERC20(tokenB).transfer(msg.sender, amountB);

        // Update the rewards for the user
        liquidityPoolReward.withdraw(liquidityAmount, msg.sender); // Notify reward contract about liquidity removal

        return (amountA, amountB);
    }

    // Helper Pure functions
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < y) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
