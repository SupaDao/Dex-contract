// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {Path} from "../libraries/Path.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "../core/interfaces/IPool.sol";
import {PoolAddress} from "../libraries/PoolAddress.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";
import {CallbackValidation} from "../libraries/CallbackValidation.sol";
import {Multicall} from "../base/Multicall.sol";
import {SelfPermit} from "../base/SelfPermit.sol";
import {Payment} from "../base/Payment.sol";
import {ImutableState} from "../base/ImutableStates.sol";
import {PaymentWithFee} from "../base/PaymentWithFee.sol";

contract SwapRouter is ISwapRouter, Multicall, SelfPermit, ImutableState, PaymentWithFee {
    using Path for bytes;
    using SafeCast for uint256;

    error Expired();
    error TooLittleReceived();
    error ExcessiveInputAmount();
    error ExcessiveOutputAmount();

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert Expired();
        _;
    }

    constructor(address _factory, address _weth9) ImutableState(_factory, _weth9) {}

    function supaSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        require(amount0Delta > 0 || amount1Delta > 0, "Zero swap");

        // Decode the swap callback data
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));
        if (isExactInput) {
            pay(tokenIn, data.payer, msg.sender, amountToPay);
        } else {
            // either initiate the next swap or pay
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();
                exactOutputInternal(amountToPay, msg.sender, 0, data);
            } else {
                tokenIn = tokenOut; // swap in/out because exact output swaps are reversed
                pay(tokenIn, data.payer, msg.sender, amountToPay);
            }
        }
    }

    function getPool(address tokenA, address tokenB, uint24 fee) private view returns (IPool) {
        return IPool(PoolAddress.computeAddress(factory, tokenA, tokenB, fee));
    }

    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        if (recipient == address(0)) recipient = address(this);

        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = getPool(tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            amountIn.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc ISwapRouter
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        // Compute the pool address
        address pool = PoolAddress.computeAddress(factory, params.tokenIn, params.tokenOut, params.fee);

        // Approve the pool to spend the input tokens
        TransferHelper.safeApprove(params.tokenIn, pool, params.amountIn);

        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenIn, params.fee, params.tokenOut), payer: msg.sender})
        );

        if (amountOut < params.amountOutMinimum) revert TooLittleReceived();
    }

    /// @inheritdoc ISwapRouter
    function exactInput(ExactInputParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        address payer = msg.sender;

        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();

            exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient,
                0,
                SwapCallbackData({path: params.path.getFirstPool(), payer: payer})
            );
            if (hasMultiplePools) {
                payer = address(this); // at this point, the caller has paid
                params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        if (amountOut < params.amountOutMinimum) revert TooLittleReceived();
    }

    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {
        // allow swapping to the router address with address 0
        if (recipient == address(0)) recipient = address(this);

        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) = getPool(tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));
        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
        return amountIn;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        amountIn = exactOutputInternal(
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenOut, params.fee, params.tokenIn), payer: msg.sender})
        );
        if (amountIn > params.amountInMaximum) revert ExcessiveOutputAmount();
    }

    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256 amountIn) {
        bytes memory path = params.path;
        address payer = msg.sender;
        uint256 amountOut = params.amountOut;

        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            // decode the last pool in the path
            (address tokenOut, address tokenIn, uint24 fee) = path.decodeLastPool();

            // build the subpath for the last pool only
            bytes memory subPath = abi.encodePacked(tokenOut, fee, tokenIn);

            amountIn = exactOutputInternal(
                amountOut,
                hasMultiplePools ? address(this) : params.recipient,
                0,
                SwapCallbackData({path: subPath, payer: payer})
            );

            if (hasMultiplePools) {
                path = path.skipLastToken();
                payer = address(this);
                amountOut = amountIn;
            } else {
                break;
            }
        }

        if (amountIn > params.amountInMaximum) revert ExcessiveOutputAmount();
    }
}
