// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Tether, Monad} from "../src/SupaDaoToken.sol";
import {DeployLiquidityPoolReward} from "./LiquidityPoolReward.s.sol";
import {LiquidityPoolReward} from "../src/LiquidityPoolReward.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";

contract DeployLiquidityPool is Script {
    Tether tether;
    Monad monad;
    LiquidityPool liquidityPool;
    LiquidityPoolReward reward;
    address liquidityReward;
    address user1;
    address user2;

    function run() external returns (LiquidityPool, address, address) {
        uint256 initialSupply = 10000000000 * 1e18;
        tether = new Tether(initialSupply);
        monad = new Monad(initialSupply);
        DeployLiquidityPoolReward deployLiquidityPoolReward = new DeployLiquidityPoolReward();

        (reward, user1, user2) = deployLiquidityPoolReward.run(); /* 
        tether.transfer(user1, 10e18);
        tether.transfer(user2, 5e18);
        monad.transfer(user1, 5e18);
        monad.transfer(user2, 10e18); */
        vm.startBroadcast();
        liquidityPool = new LiquidityPool(address(monad), address(tether), address(reward));
        vm.stopBroadcast();
        return (liquidityPool, address(monad), address(tether));
    }
}
