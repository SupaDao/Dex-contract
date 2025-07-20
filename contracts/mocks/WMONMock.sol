// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WMONMock is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    error InsufficientBalance(uint256 available, uint256 required);

    constructor() ERC20("Wrapped Monad", "WMON") {}

    // Fallback function to handle plain Ether deposits
    receive() external payable {
        deposit();
    }

    // Deposit ETH to get WETH
    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    // Withdraw WETH to get ETH
    function withdraw(uint256 wad) public {
        if (balanceOf(msg.sender) < wad) revert InsufficientBalance(balanceOf(msg.sender), wad);
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }
}
