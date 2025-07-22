// SPDX-License-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILiquidityManager {
    function mint(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _liquidity, bytes calldata _data)
        external
        returns (uint256 amount0, uint256 amount1);
    function collect(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _amount0, uint128 _amount1)
        external
        returns (uint128 amount0, uint128 amount1);
    function burn(int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        returns (uint256 amount0, uint256 amount1);
}
