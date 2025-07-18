// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISupaSwapQuoter {
    struct QuoteExactInputParams {
        bytes path;
        uint256 amountIn;
    }

    struct QuoteExactOutputParams {
        bytes path;
        uint256 amountOut;
    }

    function quoteExactInput(QuoteExactInputParams calldata params) external returns (uint256 amountOut);

    function quoteExactOutput(QuoteExactOutputParams calldata params) external returns (uint256 amountIn);

    function quoteExactInputSingle(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn)
        external
        returns (uint256 amountOut);

    function quoteExactOutputSingle(address tokenIn, address tokenOut, uint24 fee, uint256 amountOut)
        external
        returns (uint256 amountIn);
}
