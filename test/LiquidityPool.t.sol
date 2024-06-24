// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityPool, LiquidityPool__InsufficientAllowance} from "../src/LiquidityPool.sol";
import {Tether, Monad} from "../src/SupaDaoToken.sol";
import {LiquidityPoolReward} from "../src/LiquidityPoolReward.sol";
import {DeployLiquidityPoolReward} from "../script/LiquidityPoolReward.s.sol";

contract LiquidityPoolTest is Test {
    Tether tether;
    Monad monad;
    LiquidityPool liquidityPool;
    LiquidityPoolReward reward;
    address liquidityReward;
    address user1;
    address user2;

    function setUp() public {
        uint256 initialSupply = 10000000000 * 1e18;
        tether = new Tether(initialSupply);
        monad = new Monad(initialSupply);
        DeployLiquidityPoolReward deployLiquidityPoolReward = new DeployLiquidityPoolReward();
        (reward, user1, user2) = deployLiquidityPoolReward.run();

        liquidityPool = new LiquidityPool(address(monad), address(tether), address(reward));

        tether.transfer(user1, 10e18);
        monad.transfer(user1, 5e18);
    }

    function testInsufficientAllowanceA() public {
        uint256 amountA = 1e18;
        uint256 amountB = 2e18;

        // Approve less than the amount being added
        tether.approve(address(liquidityPool), amountA / 2);
        monad.approve(address(liquidityPool), type(uint256).max);
        vm.expectRevert(LiquidityPool__InsufficientAllowance.selector);
        liquidityPool.addLiquidity(amountA, amountB);
    }

    /* function testInsufficientAllowanceB() public {
        uint256 amountA = 1e18;
        uint256 amountB = 2e18;

        // Approve less than the amount being added
        tether.approve(address(liquidityPool), type(uint256).max);
        monad.approve(address(liquidityPool), amountB / 2);

        vm.expectRevert(LiquidityPool__InsufficientAllowance.selector);
        liquidityPool.addLiquidity(amountA, amountB);
    } */
}
