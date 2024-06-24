// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {DeployLiquidityPool} from "./LiquidityPool.s.sol";
import {SwapToken} from "../src/SwapTokens.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {Tether, Monad} from "../src/SupaDaoToken.sol";

contract DeploySwapToken is Script {
    SwapToken swapToken;
    address monad;
    address tether;
    LiquidityPool reward;

    function run() external returns (SwapToken) {
        DeployLiquidityPool deployLiquidityPool = new DeployLiquidityPool();
        (reward, monad, tether) = deployLiquidityPool.run();
        vm.startBroadcast();
        swapToken = new SwapToken(monad, tether);
        vm.stopBroadcast();
        return swapToken;
    }
}
