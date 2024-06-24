// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {LiquidityPoolReward} from "../src/LiquidityPoolReward.sol";
import {RewardToken} from "../src/SupaDaoToken.sol";
import {DeployToken} from "./SupaDaoToken.s.sol";

contract DeployLiquidityPoolReward is Script {
    RewardToken token;
    address tokenAddress;
    uint256 rewardRate;
    address user1;
    address user2;

    function run() external returns (LiquidityPoolReward, address, address) {
        rewardRate = 5e18;
        DeployToken deployToken = new DeployToken();
        (token, user1, user2) = deployToken.run();
        tokenAddress = address(token);
        vm.startBroadcast();
        LiquidityPoolReward liquidityPoolReward = new LiquidityPoolReward(tokenAddress, rewardRate);
        vm.stopBroadcast();
        return (liquidityPoolReward, user1, user2);
    }
}
