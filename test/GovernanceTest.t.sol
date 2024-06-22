// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Script.sol";
import {RewardToken} from "../src/SupaDaoToken.sol";
import {
    Governance,
    Governance__VotingExpired,
    Governance__InsufficientVotingPower,
    Governance__AlreadyVoted,
    Governance__VotingNotExpired,
    Governance__AlreadyExecuted
} from "../src/Governance.sol";

contract GovernanceTest is Test {
    Governance governance;
    RewardToken token;
    address user1;
    address user2;
    address user3;

    function setUp() public {
        token = new RewardToken(10000000 * 1e18);
        governance = new Governance(address(token));
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);

        vm.deal(user1, 1000 ether);
        vm.deal(user2, 50 ether);
        token.transfer(user1, 20000);
        token.transfer(user2, 10000);
    }

    function testVoteBeforeDeadline() public {
        uint256 proposalId = governance.createProposal("First proposal", block.timestamp + (60 * 60), 1);
        vm.prank(user1);
        governance.vote(proposalId, true);
        uint256 votesFor = governance.getVotesFor(proposalId);
        assertEq(votesFor, 20000);
    }

    function testVoteAfterDeadline() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 2);
        vm.prank(user1);
        vm.warp(block.timestamp + (60 * 60 * 2));
        vm.expectRevert(Governance__VotingExpired.selector);
        governance.vote(proposalId, true);
    }

    function testVoteInsufficientPower() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 3);
        vm.prank(user3);
        vm.expectRevert(Governance__InsufficientVotingPower.selector);
        governance.vote(proposalId, true);
    }

    function testCannotVoteTwice() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.prank(user2);
        governance.vote(proposalId, false);
        vm.prank(user2);
        vm.expectRevert(Governance__AlreadyVoted.selector);
        governance.vote(proposalId, true);
    }

    function testReturnCorrectProposalId() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        assertEq(proposalId, 4);
    }

    function testCannotExecuteProposalBeforeDeadLine() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.expectRevert(Governance__VotingNotExpired.selector);
        governance.executeProposal(proposalId);
    }

    function testCannotExecuteProjectExecuted() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.prank(user1);
        governance.vote(proposalId, true);
        vm.prank(user2);
        governance.vote(proposalId, true);
        vm.warp(block.timestamp + (60 * 60 * 2));
        vm.stopPrank();
        governance.executeProposal(proposalId);
        vm.expectRevert(Governance__AlreadyExecuted.selector);
        governance.executeProposal(proposalId);
    }

    function testReturnsProposalStruct() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        Governance.Proposals memory proposal = governance.getProposal(proposalId);

        assertEq(proposal.description, "Second proposal");
        assertEq(proposal.votesFor, 0);
        assertEq(proposal.votesAgainst, 0);
        assertEq(proposal.executed, false);
    }

    function testReturnsVoteFor() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.prank(user1);
        governance.vote(proposalId, true);
        vm.prank(user2);
        governance.vote(proposalId, false);
        uint256 voteFor = governance.getVotesFor(proposalId);

        assertEq(voteFor, 20000);
    }

    function testReturnsVoteAgainst() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        vm.prank(user1);
        governance.vote(proposalId, true);
        vm.prank(user2);
        governance.vote(proposalId, false);
        uint256 voteAgainst = governance.getVotesAgainst(proposalId);

        assertEq(voteAgainst, 10000);
    }

    function testReturnsDescription() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        string memory description = governance.getDescription(proposalId);

        assertEq(description, "Second proposal");
    }

    function testReturnsExecution() public {
        uint256 proposalId = governance.createProposal("Second proposal", block.timestamp + (60 * 60), 4);
        bool execution = governance.getExecution(proposalId);

        assertEq(execution, false);
    }
}
