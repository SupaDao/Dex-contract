// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {
    Governance,
    Governance__VotingExpired,
    Governance__InsufficientVotingPower,
    Governance__AlreadyVoted,
    Governance__VotingNotExpired,
    Governance__AlreadyExecuted
} from "../src/Governance.sol";

import {DeployGovernance} from "../script/Governance.s.sol";

contract GovernanceTest is Test {
    Governance governance;
    address user1;
    address user2;
    address user3;

    function setUp() public {
        DeployGovernance deployGovernance = new DeployGovernance();
        user3 = vm.addr(3);
        (governance, user1, user2) = deployGovernance.run();
    }

    function testVoteBeforeDeadline() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("First proposal", block.timestamp + (60 * 60), 1);
        vm.stopPrank();
        vm.prank(user1);
        governance.vote(proposalId, true);
        uint256 votesFor = governance.getVotesFor(proposalId);
        assertEq(votesFor, 20000);
    }

    function testVoteAfterDeadline() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 2);
        vm.stopPrank();
        vm.prank(user1);
        vm.warp(block.timestamp + (60 * 60 * 2));
        vm.expectRevert(Governance__VotingExpired.selector);
        governance.vote(proposalId, true);
    }

    function testVoteInsufficientPower() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 3);
        vm.stopPrank();
        vm.prank(user3);
        vm.expectRevert(Governance__InsufficientVotingPower.selector);
        governance.vote(proposalId, true);
    }

    function testCannotVoteTwice() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.stopPrank();
        vm.prank(user2);
        governance.vote(proposalId, false);
        vm.prank(user2);
        vm.expectRevert(Governance__AlreadyVoted.selector);
        governance.vote(proposalId, true);
    }

    function testReturnCorrectProposalId() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.stopPrank();
        assertEq(proposalId, 4);
    }

    function testCannotExecuteProposalBeforeDeadLine() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.expectRevert(Governance__VotingNotExpired.selector);
        governance.executeProposal(proposalId);
        vm.stopPrank();
    }

    function testCannotExecuteProjectExecuted() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.stopPrank();
        vm.prank(user1);
        governance.vote(proposalId, true);
        vm.prank(user2);
        governance.vote(proposalId, true);
        vm.warp(block.timestamp + (60 * 60 * 2));
        vm.startPrank(msg.sender);
        governance.executeProposal(proposalId);
        vm.expectRevert(Governance__AlreadyExecuted.selector);
        governance.executeProposal(proposalId);
        vm.stopPrank();
    }

    function testReturnsProposalStruct() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.stopPrank();
        Governance.Proposals memory proposal = governance.getProposal(proposalId);

        assertEq(proposal.description, "Second proposal");
        assertEq(proposal.votesFor, 0);
        assertEq(proposal.votesAgainst, 0);
        assertEq(proposal.executed, false);
    }

    function testReturnsVoteFor() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.stopPrank();
        vm.prank(user1);
        governance.vote(proposalId, true);
        vm.prank(user2);
        governance.vote(proposalId, false);
        uint256 voteFor = governance.getVotesFor(proposalId);

        assertEq(voteFor, 20000);
    }

    function testReturnsVoteAgainst() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.stopPrank();
        vm.prank(user1);
        governance.vote(proposalId, true);
        vm.prank(user2);
        governance.vote(proposalId, false);
        uint256 voteAgainst = governance.getVotesAgainst(proposalId);

        assertEq(voteAgainst, 10000);
    }

    function testReturnsDescription() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.stopPrank();
        string memory description = governance.getDescription(proposalId);

        assertEq(description, "Second proposal");
    }

    function testReturnsExecution() public {
        vm.startPrank(msg.sender);
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.stopPrank();
        bool execution = governance.getExecution(proposalId);

        assertEq(execution, false);
    }
}
