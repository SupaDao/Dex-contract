//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error StakeTokens__InsufficientAmount();
error StakeTokens__InsufficientStakingBalance();
error StakeTokens__InsufficientRewardBalance();

contract StakeTokens is Ownable {
    IERC20 public stakingToken;
    uint256 public rewardRate;
    uint256 public totalStaked;

    struct Stake {
        uint256 amount;
        uint256 lastUpdated;
        uint256 reward;
    }

    mapping(address => Stake) public stakes;

    //Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 reward);
    event RewardClaim(address indexed user, uint256 reward);

    constructor(address _stakingToken, uint256 _rewardRate) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardRate = _rewardRate;
    }

    modifier updateReward(address account) {
        if (account != address(0)) {
            stakes[account].reward = earned(account);
            stakes[account].lastUpdated = block.timestamp;
        }
        _;
    }

    function stake(uint256 amount) public updateReward(msg.sender) {
        if (amount <= 0) {
            revert StakeTokens__InsufficientAmount();
        }
        stakingToken.transfer(address(this), amount);
        stakes[msg.sender].amount += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        if (amount <= 0) {
            revert StakeTokens__InsufficientAmount();
        }

        if (stakes[msg.sender].amount < amount) {
            revert StakeTokens__InsufficientStakingBalance();
        }

        stakingToken.transfer(msg.sender, amount);
        stakes[msg.sender].amount -= amount;
        totalStaked -= amount;
        emit Withdrawn(msg.sender, amount, stakes[msg.sender].reward);
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = stakes[msg.sender].reward;
        if (reward <= 0) {
            revert StakeTokens__InsufficientRewardBalance();
        }
        stakes[msg.sender].reward = 0;
        stakingToken.transfer(msg.sender, reward);
        emit RewardClaim(msg.sender, reward);
    }

    function earned(address account) public view returns (uint256) {
        Stake memory stakeInfo = stakes[account];
        uint256 stakedTime = block.timestamp - stakeInfo.lastUpdated;
        uint256 reward = stakeInfo.reward + (stakeInfo.amount * stakedTime * rewardRate / 1e18);
        return reward;
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = stakingToken.balanceOf(address(this));
        stakingToken.transfer(owner(), balance);
    }

    //Helper functions

    function calculatePercentage(uint256 number, uint256 percentage) public pure returns (uint256) {
        require(percentage >= 0 && percentage <= 100, "Percentage must be between 0 and 100");

        return (number * percentage) / 100;
    }
}
