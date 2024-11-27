// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Staking is Ownable {
    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lockPeriod; // Lock duration in seconds
    }

    mapping(address => Stake[]) public stakes;
    uint256[] public milestoneDays = [1, 5, 10, 15, 30];
    uint256[] public rewardRates = [3, 5, 8, 10, 15];
    uint256 public penaltyFees;
    uint256 public constant UNSTAKE_PENALTY_RATE = 2;

    event Staked(address indexed user, uint256 amount, uint256 _lockPeriod);
    event Withdrawn(address indexed user, uint256 amount, uint256 reward);

    constructor() Ownable(msg.sender) {}

    function stake(uint256 _lockPeriod) external payable {
        require(msg.value > 0, "Stake amount should be greater than 0");
        require(_lockPeriod >= 1 days, "Lock period must be greater than a day");

        stakes[msg.sender].push(Stake({
            amount: msg.value,
            startTime: block.timestamp,
            lockPeriod: _lockPeriod
        }));

        emit Staked(msg.sender, msg.value, _lockPeriod);
    }

    function unstake(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake memory userStake = stakes[msg.sender][stakeIndex];

        require(userStake.amount > 0, "User stake withdrawn");
        require(block.timestamp >= userStake.lockPeriod + userStake.startTime, "Stake is still locked");

        uint256 rewardRate = calculateRewardRate(userStake.lockPeriod / 1 days);
        uint256 reward = (userStake.amount * rewardRate) / 100;
        uint256 totalAmount = userStake.amount + reward;

        removeStake(stakeIndex);
        payable(msg.sender).transfer(totalAmount);

        emit Withdrawn(msg.sender, userStake.amount, reward);
    }

    function withdrawalEmmergency(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake memory userStake = stakes[msg.sender][stakeIndex];

        require(userStake.amount > 0, "User stake withdrawn");

        uint256 penalty = (userStake.amount * UNSTAKE_PENALTY_RATE) / 100;
        penaltyFees += penalty;
        uint256 amountAfterPenalty = userStake.amount - penalty;

        removeStake(stakeIndex);
        payable(msg.sender).transfer(amountAfterPenalty);

        emit Withdrawn(msg.sender, amountAfterPenalty, penalty);
    }

    function withdrawFees() public onlyOwner {
        require(penaltyFees > 0, "No fees to withdraw");
        uint256 amount = penaltyFees;
        penaltyFees = 0;
        payable(owner()).transfer(amount);
    }

    function calculateRewardRate(uint256 stakeDays) public view returns (uint256) {
        if (stakeDays >= milestoneDays[milestoneDays.length - 1]) {
            return rewardRates[rewardRates.length - 1];
        }

        for (uint256 i = 0; i < milestoneDays.length - 1; i++) {
            if (stakeDays >= milestoneDays[i] && stakeDays < milestoneDays[i + 1]) {
                uint256 lowerDays = milestoneDays[i];
                uint256 upperDays = milestoneDays[i + 1];
                uint256 lowerRate = rewardRates[i];
                uint256 upperRate = rewardRates[i + 1];

                return lowerRate + ((stakeDays - lowerDays) * (upperRate - lowerRate)) / (upperDays - lowerDays);
            }
        }

        return rewardRates[0];
    }

    function removeStake(uint256 stakeIndex) internal {
        uint256 lastIndex = stakes[msg.sender].length - 1;
        if (stakeIndex != lastIndex) {
            stakes[msg.sender][stakeIndex] = stakes[msg.sender][lastIndex];
        }
        stakes[msg.sender].pop();
    }

    receive() external payable {}
}

