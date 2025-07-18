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

    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
    }

    struct SwapState {
        int256 amountSpecifiedRemaining;
        int256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        uint256 feeGrowthGlobalX128;
        uint128 protocolFee;
        uint128 liquidity;
    }

    struct StepComputations {
        uint160 sqrtPriceStartX96;
        int24 tickNext;
        bool initialized;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }

    event Mint(
        address sender,
        address indexed recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event Collect(
        address indexed owner,
        address indexed recipient,
        int24 indexed tickLower,
        int24 tickUpper,
        uint128 amount0,
        uint128 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

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

    function tokens() external view returns (address tokenA, address tokenB);
    function getSlot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function getLiquidity() external view returns (uint128 liquidity);
    function getPositions(bytes32 key)
        external
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}
