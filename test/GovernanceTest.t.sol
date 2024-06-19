// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Governance,Governance__VotingExpired} from "../src/Governance.sol";
import {DeployGovernance} from "../script/Governance.s.sol";

contract GovernanceTest is Test{
      Governance governance;
      address admin = address(1);
      function setUp () external{
            DeployGovernance deployGovernance = new DeployGovernance();
            governance = deployGovernance.run();

      }

      function testRevertVotingExpired() public {
            // Set the voting period to 1 block
            vm.startPrank(msg.sender);
            governance.createProposal("test proposal", block.timestamp + 100);
            vm.stopPrank();
            vm.prank(address(2));
            vm.warp(block.timestamp + 1000);
            vm.expectRevert(abi.encodeWithSelector(Governance__VotingExpired.selector));
            governance.vote(0, true);
            vm.stopPrank();
      }
}