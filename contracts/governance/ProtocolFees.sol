// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolFees is Ownable {
    uint24 public swapFee;
    uint24 public liquidityFee;
    address public feeRecipient;

    event FeesUpdated(uint24 swapFee, uint24 liquidityFee);
    event FeeRecipientUpdated(address indexed newRecipient);

    constructor(address _feeRecipient, uint24 _swapFee, uint24 _liquidityFee) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "Invalid recipient");
        feeRecipient = _feeRecipient;
        swapFee = _swapFee;
        liquidityFee = _liquidityFee;
    }

    function updateFees(uint24 _swapFee, uint24 _liquidityFee) external onlyOwner {
        require(_swapFee <= 100, "Swap fee too high");
        require(_liquidityFee <= 100, "Liquidity fee too high");
        swapFee = _swapFee;
        liquidityFee = _liquidityFee;
        emit FeesUpdated(_swapFee, _liquidityFee);
    }

    function updateFeeRecipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid address");
        feeRecipient = _newRecipient;
        emit FeeRecipientUpdated(_newRecipient);
    }

    function getFees() external view returns (uint24, uint24, address) {
        return (swapFee, liquidityFee, feeRecipient);
    }
}
