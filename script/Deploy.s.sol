// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Core Contracts
import {EmergencyPause} from "../contracts/governance/EmergencyPause.sol";
import {Factory} from "../contracts/core/Factory.sol";
import {PoolDeployer} from "../contracts/core/PoolDeployer.sol";
import {Pool} from "../contracts/core/Pool.sol";

// WETH & Mocks
import {WMONMock} from "../contracts/mocks/WMONMock.sol";

// Periphery
import {NonfungibleTokenPositionDescriptor} from "../contracts/periphery/NonfungibleTokenPositionDescriptor.sol";
import {NonfungibleTokenPositionManager} from "../contracts/periphery/NonfungibleTokenPositionManager.sol";
import {SwapRouter} from "../contracts/periphery/SwapRouter.sol";
import {Quoter} from "../contracts/periphery/Quoter.sol";

contract DeployAll is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Governance Contracts
        // EmergencyPause emergencyPause = new EmergencyPause();
        // console.log("EmergencyPause deployed at:", address(emergencyPause));

        // 2. Core Contracts
        Factory factory = new Factory();
        console.log("Factory deployed at:", address(factory));

        // PoolDeployer poolDeployer = new PoolDeployer();
        // console.log("PoolDeployer deployed at:", address(poolDeployer));

        // 3. WETH / Wrapped Monad
        WMONMock WMON = new WMONMock();
        console.log("WMON (Wrapped Monad) deployed at:", address(WMON));

        bytes32 label = bytes32("MON");

        // 4. Periphery Contracts
        NonfungibleTokenPositionDescriptor descriptor = new NonfungibleTokenPositionDescriptor(address(WMON), label);
        console.log("TokenDescriptor deployed at:", address(descriptor));

        Quoter quoter = new Quoter(address(factory));
        console.log("Quoter deployed at:", address(quoter));

        NonfungibleTokenPositionManager positionManager =
            new NonfungibleTokenPositionManager(address(factory), address(WMON), address(descriptor));
        console.log("NonfungibleTokenPositionManager deployed at:", address(positionManager));

        SwapRouter router = new SwapRouter(address(factory), address(WMON));
        console.log("SwapRouter deployed at:", address(router));

        vm.stopBroadcast();
    }
}
