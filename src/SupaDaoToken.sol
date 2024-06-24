// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RewardToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("RSupaDao", "RSD") {
        _mint(msg.sender, initialSupply);
    }
}

/**
 * @dev This tokens are just for testing purposes
 */
contract Tether is ERC20 {
    constructor(uint256 initialSupply) ERC20("Tether", "USDT") {
        _mint(msg.sender, initialSupply);
    }
}

contract Monad is ERC20 {
    constructor(uint256 initialSupply) ERC20("Monad", "MND") {
        _mint(msg.sender, initialSupply);
    }
}
