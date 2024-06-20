// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {RewardToken} from "../src/SupaDaoToken.sol";
import {Governance} from "../src/Governance.sol";

contract DeployGovernance is Script {
    function run() external returns (Governance) {
        uint256 initialSupply = 1000000 * 1e18;
        address user = address(2);
        RewardToken token = new RewardToken(initialSupply);
        address tokenAddress = address(token);
        vm.startBroadcast();
        Governance governance = new Governance(tokenAddress);
        vm.stopBroadcast();
        console.log("Token deployed at:", tokenAddress);
        console.log("Governance deployed at:", address(governance));
        console.log("Governance deployer at:", token.balanceOf(user));
        return governance;
    }
}
