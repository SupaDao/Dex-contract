// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DeploySwapToken} from "../script/SwapToken.s.sol";
import {SwapToken, SwapToken__InsufficientAllowance} from "../src/SwapTokens.sol";
import {Tether, Monad} from "../src/SupaDaoToken.sol";
import {LiquidityPool__InsufficientAllowance} from "../src/LiquidityPool.sol";

contract SwapTokenTest is Test {
    SwapToken swap;
    Tether tether;
    Monad monad;
    address user1;

    function setUp() public {
        uint256 initialSupply = 10000000000 * 1e18;
        tether = new Tether(initialSupply);
        monad = new Monad(initialSupply);
        DeploySwapToken deploySwapToken = new DeploySwapToken();
        swap = deploySwapToken.run();
        user1 = vm.addr(1);
        tether.transfer(user1, 10e18);
        monad.transfer(user1, 10e18);

        tether.transfer(address(this), 10e18);
        monad.transfer(address(this), 10e18);
    }

    /* function testSwapAForB() public {
        uint256 amountA = 1e18;

        // Approve the swap contract to transfer tether from this address (for testing)
        monad.approve(address(swap), amountA);

        // Get initial reserve values before the swap
        uint256 initialReserveA = swap.reserveA();
        uint256 initialReserveB = swap.reserveB();

        uint256 amountBOut = swap.swapAForB(amountA);

        // Assert the user received the expected amount of token B
        assertEq(tether.balanceOf(user1), amountBOut);

        // Assert reserveA is updated correctly (increased by amountA)
        assertEq(swap.reserveA(), initialReserveA + amountA);

        // Assert reserveB is updated correctly (decreased by calculated amountB)
        assertGt(initialReserveB, swap.reserveB()); // Greater than due to swap fee
    } */

    // Test insufficient allowance for token A
    function testInsufficientAllowanceA() public {
        uint256 amountA = 1e10;

        // Approve less than the swap amount
        monad.approve(address(swap), amountA / 2);

        vm.expectRevert(SwapToken__InsufficientAllowance.selector);
        swap.swapAForB(amountA);
    }
}
