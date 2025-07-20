// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract EmergencyPause is Ownable, Pausable {
    mapping(address => bool) public pausedPools;
    bool public globalPause;

    event PoolPaused(address pool);
    event PoolUnpaused(address pool);
    event GlobalPauseSet(bool status);

    modifier notPaused(address pool) {
        require(!globalPause && !pausedPools[pool], "Pool is paused");
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setGlobalPause(bool status) external onlyOwner {
        globalPause = status;
        emit GlobalPauseSet(status);
    }

    function pausePool(address pool) external onlyOwner {
        pausedPools[pool] = true;
        emit PoolPaused(pool);
    }

    function unpausePool(address pool) external onlyOwner {
        pausedPools[pool] = false;
        emit PoolUnpaused(pool);
    }

    function isPoolPaused(address pool) external view returns (bool) {
        return globalPause || pausedPools[pool];
    }
}
