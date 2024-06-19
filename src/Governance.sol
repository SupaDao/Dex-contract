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
      struct Proposals{
            string description;
            uint256 votesFor;
            uint256 votesAgainst;
            uint256 deadline;
            bool executed;
      }

      IERC20 public governaceToken;
      uint256 public proposalCount;

      mapping(uint256 => Proposals) public proposals;
      mapping(uint256 => mapping( address => bool )) public votes;

      event Approve(uint256 proposalId, uint256 votesFor, string description);

      constructor (address _tokenAddress) Ownable(msg.sender){
            governaceToken = IERC20(_tokenAddress);
      }

      function createProposal(string memory _description, uint256 _duration) public onlyOwner {
            proposals[proposalCount] = Proposals({
                  description : _description,
                  votesFor:0,
                  votesAgainst: 0,
                  deadline: block.timestamp + _duration,
                  executed: false
            });
            proposalCount++;
      }

      function vote(uint256 _proposalId, bool _support) public{
            if(block.timestamp > proposals[_proposalId].deadline){
                  revert Governance__VotingExpired();
            }

            if (votes[_proposalId][msg.sender]){
                  revert Governance__AlreadyVoted();
            }

            uint256 votingPower = governaceToken.balanceOf(msg.sender);
            if (votingPower < 0) {
                  revert Governance__InsufficientVotingPower();
            }

            if(_support){
                  proposals[_proposalId].votesFor += votingPower;
            } else {
                  proposals[_proposalId].votesAgainst += votingPower;
            }

            votes[_proposalId][msg.sender] = true;
      }

      function executeProposal (uint256 _proposalId) public onlyOwner{
            Proposals storage proposal = proposals[_proposalId];

            if(proposal.deadline >= block.timestamp){
                  revert Governance__VotingNotExpired();
            }

            if (proposal.executed){
                  revert Governance__AlreadyExecuted();
            }

            if(proposal.votesFor > proposal.votesAgainst){
                  emit Approve(_proposalId, proposal.votesFor, proposal.description);
            }

            proposal.executed = true;
      }
}