// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 < 0.9.0;

interface IToken {
      function deposit() external payable;

      function withdraw(uint256 amount) external;

      function totalSupply() external view returns(uint);

      function balanceOf (address account) external view returns(uint256);

      function transfer(address recipient,uint256 amount) external view returns(uint256);

      function allowance (address spender,uint256 amount) external returns(bool);

      function approve(address spender,uint256 amount) external returns(bool);

      function transferFrom(address sender,address recipient,uint256 amount) external returns(bool);

      function burn(uint256 amount) external;

      event Transfer(address indexed from, address indexed to, uint256 value);

      event Approval(address indexed owner, address indexed spender, uint256 value);

}