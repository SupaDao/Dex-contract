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
import {ProtocolFees} from "../governance/ProtocolFees.sol";
import {EmergencyPause} from "../governance/EmergencyPause.sol";

contract SwapRouter is ISwapRouter, Multicall, SelfPermit, ImutableState, PaymentWithFee {
    using Path for bytes;
    using SafeCast for uint256;

    error Expired();
    error TooLittleReceived();
    error ExcessiveInputAmount();
    error ExcessiveOutputAmount();

    ProtocolFees public immutable protocolFees;
    EmergencyPause public immutable emergencyPause;

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert Expired();
        _;
    }

    constructor(address _factory, address _weth9, address _protocolFees, address _emergencyPause)
        ImutableState(_factory, _weth9)
    {
        protocolFees = ProtocolFees(_protocolFees);
        emergencyPause = EmergencyPause(_emergencyPause);
    }

    function supaSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        require(amount0Delta > 0 || amount1Delta > 0, "Zero swap");

        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));
        if (isExactInput) {
            pay(tokenIn, data.payer, msg.sender, amountToPay);
        } else {
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();
                exactOutputInternal(amountToPay, msg.sender, 0, data);
            } else {
                tokenIn = tokenOut;
                pay(tokenIn, data.payer, msg.sender, amountToPay);
            }
        }
    }

    function getPool(address tokenA, address tokenB, uint24 fee) private view returns (IPool) {
        PoolAddress.PoolKey memory key = PoolAddress.getPoolKey(tokenA, tokenB, fee);
        return IPool(PoolAddress.computeAddress(factory, key.token0, key.token1, key.fee));
    }

    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        if (recipient == address(0)) recipient = address(this);

        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();
        IPool pool = getPool(tokenIn, tokenOut, fee);
        require(!emergencyPause.isPoolPaused(address(pool)), "Pool paused");

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = pool.swap(
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

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenIn, params.fee, params.tokenOut), payer: msg.sender})
        );

        if (amountOut < params.amountOutMinimum) revert TooLittleReceived();
    }

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

            amountOut = exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient,
                0,
                SwapCallbackData({path: params.path.getFirstPool(), payer: payer})
            );
            if (hasMultiplePools) {
                payer = address(this);
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
        if (recipient == address(0)) recipient = address(this);

        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();
        IPool pool = getPool(tokenIn, tokenOut, fee);
        require(!emergencyPause.isPoolPaused(address(pool)), "Pool paused");

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
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

            (address tokenOut, address tokenIn, uint24 fee) = path.decodeLastPool();

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
