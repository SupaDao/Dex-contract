// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 < 0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Weth9 is ERC20{
      constructor(uint256 initialSupply) ERC20("Wrapped Ether","WETH") {
            _mint(msg.sender,initialSupply);
      }
}