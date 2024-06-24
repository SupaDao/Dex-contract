// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StakeTokens, StakeTokens__InsufficientAmount} from "../src/StakeToken.sol";
import {DeployStake} from "../script/StakeToken.s.sol";

contract StakeTokenTest is Test {
    StakeTokens stake;

    function setUp() public {
        DeployStake deployStake = new DeployStake();
        stake = deployStake.run();
    }

    function testCannotStakeZeroToken() public {
        vm.expectRevert(StakeTokens__InsufficientAmount.selector);
        stake.stake(0);
    }

    function testStakeEvent() public {
      vm.startPrank(msg.sender);
        vm.expectEmit(true, true, true, true);
        emit StakeTokens.Staked(msg.sender, 2000);
        stake.stake(2000);
    }
}
