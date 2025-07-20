// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Core Contracts
import {ProtocolFees} from "../contracts/governance/ProtocolFees.sol";
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
        EmergencyPause emergencyPause = new EmergencyPause();
        console.log("EmergencyPause deployed at:", address(emergencyPause));

        ProtocolFees protocolFees = new ProtocolFees(msg.sender, 100, 100); // example: 0.01% fees
        console.log("ProtocolFees deployed at:", address(protocolFees));

        // 2. Core Contracts
        Factory factory = new Factory(address(protocolFees), address(emergencyPause));
        console.log("Factory deployed at:", address(factory));

        PoolDeployer poolDeployer = new PoolDeployer();
        console.log("PoolDeployer deployed at:", address(poolDeployer));

        // 3. WETH / Wrapped Monad
        WMONMock WMON = new WMONMock();
        console.log("WMON (Wrapped Monad) deployed at:", address(WMON));

        // 4. Periphery Contracts
        NonfungibleTokenPositionDescriptor descriptor = new NonfungibleTokenPositionDescriptor(
            address(WMON), 0x4554480000000000000000000000000000000000000000000000000000000000
        );
        console.log("TokenDescriptor deployed at:", address(descriptor));

        Quoter quoter = new Quoter(address(factory));
        console.log("Quoter deployed at:", address(quoter));

        NonfungibleTokenPositionManager nft = new NonfungibleTokenPositionManager(
            address(factory), address(WMON), address(descriptor), address(protocolFees), address(emergencyPause)
        );
        console.log("NonfungibleTokenPositionManager deployed at:", address(nft));

        NonfungibleTokenPositionManager positionManager = new NonfungibleTokenPositionManager(
            address(factory), address(WMON), address(descriptor), address(protocolFees), address(emergencyPause)
        );
        console.log("NonfungiblePositionManager deployed at:", address(positionManager));

        SwapRouter router =
            new SwapRouter(address(factory), address(WMON), address(protocolFees), address(emergencyPause));
        console.log("SwapRouter deployed at:", address(router));

        vm.stopBroadcast();
    }
}
