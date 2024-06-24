// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {
    LiquidityPoolReward,
    LiquidityPoolReward__InsufficientAmount,
    LiquidityPoolReward__InsufficientBalance
} from "../src/LiquidityPoolReward.sol";
import {DeployLiquidityPoolReward} from "../script/LiquidityPoolReward.s.sol";

contract LiquidityPoolRewardTest is Test {
    LiquidityPoolReward liquidityReward;
    address user1;
    address user2;

    function setUp() public {
        DeployLiquidityPoolReward deployLiquidityReward = new DeployLiquidityPoolReward();
        (liquidityReward, user1, user2) = deployLiquidityReward.run();
    }

    function testRetunZeroTotalSupplyOnInitialization() public view {
        uint256 tokenStored = liquidityReward.rewardPerToken();
        assertEq(tokenStored, 0);
    }

    function testStakeToken() public {
        vm.startPrank(msg.sender);
        vm.expectEmit(true, true, true, true);
        emit LiquidityPoolReward.Staked(user1, 2000);
        liquidityReward.stake(2000, user1);
    }

    function testCannotStakeZeroToken() public {
        vm.startPrank(msg.sender);
        vm.expectRevert(LiquidityPoolReward__InsufficientAmount.selector);
        liquidityReward.stake(0, user1);
    }

    function testWithdrawal() public {
        vm.startPrank(msg.sender);
        liquidityReward.stake(2000, user1);
        vm.expectEmit(true, true, true, true);
        emit LiquidityPoolReward.Withdrawn(user1, 1000);
        liquidityReward.withdraw(1000, user1);
    }

    function testCannotWithdrawMoreThanBalance() public {
        vm.startPrank(msg.sender);
        liquidityReward.stake(2000, user1);
        vm.expectRevert(LiquidityPoolReward__InsufficientBalance.selector);
        liquidityReward.withdraw(100000, user1);
    }

    function testCannotWithdrawZeroToken() public {
        vm.startPrank(msg.sender);
        vm.expectRevert(LiquidityPoolReward__InsufficientAmount.selector);
        liquidityReward.withdraw(0, user1);
    }
}
