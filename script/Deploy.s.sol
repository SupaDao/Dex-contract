// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 < 0.9.0;
pragma abicoder v2;

import {Script,console} from "forge-std/Script.sol";
import {SingleSwapToken} from "../contracts/SwapToken.sol";
import {SwapMultiHop} from "../contracts/SwapMultiHop.sol";
import {LiquidityPool} from "../contracts/LiquidityPool.sol";
import {Weth9} from "../contracts/mocks/WETH9.sol";
import {SupadaoFactory} from "../contracts/SupadaoFactory.sol";
import {NonfungiblePositionManager} from "../contracts/NonfungiblePositionManager.sol";
import {SupadaoRouter} from "../contracts/SupadaoRouter.sol";
import {Quoter} from "../contracts/lens/Quoter.sol";
import {SupadaoNFTDescriptor} from "../contracts/SupadaoNFTDescriptor.sol";


contract Deploy is Script{
      SingleSwapToken singleSwapToken;
      SwapMultiHop swapMultiHop;
      Weth9 weth;
      SupadaoFactory supadaoFactory;
      NonfungiblePositionManager nonfungiblePositionManager;
      SupadaoRouter supadaoRouter;
      LiquidityPool liquidity;
      SupadaoNFTDescriptor supadaoNFTDescriptor;
      Quoter quoter;
      
      uint256 constant public INITIAL_SUPPLY = 10000000000000 * 10**18;


      function run () external {
            vm.startBroadcast();
            weth = new Weth9(INITIAL_SUPPLY);
            supadaoNFTDescriptor = new SupadaoNFTDescriptor();
            supadaoFactory = new SupadaoFactory();
            nonfungiblePositionManager = new NonfungiblePositionManager(address(supadaoFactory), address(weth),address(supadaoNFTDescriptor));
            supadaoRouter = new SupadaoRouter(address(supadaoFactory), address(weth));
            singleSwapToken = new SingleSwapToken(address(supadaoRouter));
            swapMultiHop = new SwapMultiHop(address(supadaoRouter));
            quoter = new Quoter(address(supadaoFactory),address(weth));
            liquidity = new LiquidityPool(address(nonfungiblePositionManager));
            vm.stopBroadcast();

            console.log("weth token deployed at", address(weth));
            console.log("supadao NFTDescriptor deployed at", address(supadaoNFTDescriptor));
            console.log("supadao Factory deployed at", address(supadaoFactory));
            console.log("nonfungible Position Manager deployed at", address(nonfungiblePositionManager));
            console.log("supadao Router deployed at", address(supadaoRouter));
            console.log("single Swap Token deployed at", address(singleSwapToken));
            console.log("swap MultiHop deployed at", address(swapMultiHop));
            console.log("quoter deployed at", address(quoter));
            console.log("liquidity deployed at", address(liquidity));

      }
}
