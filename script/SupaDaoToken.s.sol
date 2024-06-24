// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {RewardToken} from "../src/SupaDaoToken.sol";

contract DeployToken is Script {
    address user1;
    address user2;

    function run() external returns (RewardToken, address, address) {
        uint256 initialSupply = 10000000 * 1e18;
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        vm.deal(user1, 1000000e18);
        vm.deal(user2, 50000e18);
        vm.startBroadcast();
        RewardToken token = new RewardToken(initialSupply);
        token.transfer(user1, 20000);
        token.transfer(user2, 10000);
        vm.stopBroadcast();
        return (token, user1, user2);
    }
}
