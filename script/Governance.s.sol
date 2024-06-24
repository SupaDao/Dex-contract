// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {RewardToken} from "../src/SupaDaoToken.sol";
import {Governance} from "../src/Governance.sol";
import {DeployToken} from "./SupaDaoToken.s.sol";

contract DeployGovernance is Script {
    RewardToken token;
    address user1;
    address user2;

    function run() external returns (Governance, address, address) {
        DeployToken deployToken = new DeployToken();
        (token, user1, user2) = deployToken.run();
        address tokenAddress = address(token);
        vm.startBroadcast();
        Governance governance = new Governance(tokenAddress);
        vm.stopBroadcast();
        console.log("Token deployed at:", tokenAddress);
        console.log("Governance deployed at:", address(governance));
        console.log("Governance deployer at:", token.balanceOf(user1));
        console.log("Governance deployer at:", token.balanceOf(user2));
        return (governance, user1, user2);
    }
}
