// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPool {
    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function initialize(uint160 _sqrtPriceX96) external;

    function mint(address _recipient, int24 _tickLower, int24 _tickUpper, uint128 _liquidity, bytes calldata _data)
        external
        returns (uint256 amount0, uint256 amount1);

    function swap(
        address _recipient,
        bool _zeroForOne,
        int256 _amountSpecified,
        uint160 _sqrtPriceLimitX96,
        bytes calldata _data
    ) external returns (int256 amount0, int256 amount1);

    function collect(
        address _recipient,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _amount0Requested,
        uint128 _amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    function burn(int24 _tickLower, int24 _tickUpper, uint128 _liquidity)
        external
        returns (uint256 amount0, uint256 amount1);
}
