// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISwapManager {
    function swap(
        address _recipient,
        bool _zeroForOne,
        int256 _amount,
        uint160 _sqrtPriceLimitX96,
        bytes calldata _data
    ) external returns (int256 amount0, int256 amount1);
}
