// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {StakeTokens} from "../src/StakeToken.sol";
import {RewardToken} from "../src/SupaDaoToken.sol";
import {DeployToken} from "./SupaDaoToken.s.sol";

contract DeployStake is Script {
    RewardToken token;
    address tokenAddress;
    uint256 rewardRate;
    address user1;
    address user2;

    function run() public returns (StakeTokens) {
        rewardRate = 5e18;
        DeployToken deployToken = new DeployToken();
        (token, user1, user2) = deployToken.run();
        tokenAddress = address(token);
        vm.startBroadcast();
        StakeTokens stakeToken = new StakeTokens(tokenAddress, rewardRate);
        vm.stopBroadcast();
        return stakeToken;
    }
}
