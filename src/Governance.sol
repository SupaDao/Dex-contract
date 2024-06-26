// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//Errors
error Governance__VotingExpired();
error Governance__VotingNotExpired();
error Governance__AlreadyVoted();
error Governance__InsufficientVotingPower();
error Governance__AlreadyExecuted();

contract Governance is Ownable {
    struct Proposals {
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 deadline;
        bool executed;
    }

    IERC20 public governaceToken;

    mapping(uint256 => Proposals) public proposals;
    mapping(uint256 => mapping(address => bool)) public votes;

    event Approve(uint256 proposalId, uint256 votesFor, string description);

    constructor(address _tokenAddress) Ownable(msg.sender) {
        governaceToken = IERC20(_tokenAddress);
    }

    function createProposal(string memory _description, uint256 _duration, uint256 _proposalId)
        public
        onlyOwner
        returns (uint256)
    {
        proposals[_proposalId] = Proposals({
            description: _description,
            votesFor: 0,
            votesAgainst: 0,
            deadline: block.timestamp + _duration,
            executed: false
        });
        return _proposalId;
    }

    function vote(uint256 _proposalId, bool _support) public {
        if (block.timestamp > proposals[_proposalId].deadline) {
            revert Governance__VotingExpired();
        }

        if (votes[_proposalId][msg.sender]) {
            revert Governance__AlreadyVoted();
        }

        uint256 votingPower = governaceToken.balanceOf(msg.sender);
        if (votingPower <= 0) {
            revert Governance__InsufficientVotingPower();
        }

        if (_support) {
            proposals[_proposalId].votesFor += votingPower;
        } else {
            proposals[_proposalId].votesAgainst += votingPower;
        }

        votes[_proposalId][msg.sender] = true;
    }

    function executeProposal(uint256 _proposalId) public onlyOwner {
        Proposals storage proposal = proposals[_proposalId];

        if (proposal.deadline >= block.timestamp) {
            revert Governance__VotingNotExpired();
        }

        if (proposal.executed) {
            revert Governance__AlreadyExecuted();
        }

        if (proposal.votesFor > proposal.votesAgainst) {
            emit Approve(_proposalId, proposal.votesFor, proposal.description);
            proposal.executed = true;
        }

        proposal.executed = true;
    }

    // Helpers
    function getProposal(uint256 _proposalId) public view returns (Proposals memory) {
        Proposals storage proposal = proposals[_proposalId];
        return proposal;
    }

    function getVotesFor(uint256 _proposalId) public view returns (uint256) {
        return proposals[_proposalId].votesFor;
    }

    function getVotesAgainst(uint256 _proposalId) public view returns (uint256) {
        return proposals[_proposalId].votesAgainst;
    }

    function getDescription(uint256 _proposalId) public view returns (string memory) {
        return proposals[_proposalId].description;
    }

    function getExecution(uint256 _proposalId) public view returns (bool) {
        return proposals[_proposalId].executed;
    }

    function getDeadline(uint256 _proposalId) public view returns (uint256) {
        return proposals[_proposalId].deadline;
    }
}
