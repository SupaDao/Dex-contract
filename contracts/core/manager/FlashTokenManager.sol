// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LowGasSafeMath} from "../../libraries/LowGasSafeMath.sol";
import {FullMath} from "../../libraries/FullMath.sol";
import {FixedPoint128} from "../../libraries/FixedPoint128.sol";
import {TransferHelper} from "../../libraries/TransferHelper.sol";
import {IERC20Minimal} from "../../interfaces/IERC20Minimal.sol";
import {ISupaSwapFlashCallback} from "../interfaces/callback/ISupaSwapFlashCallback.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IFlashTokenManager} from "../interfaces/manager/IFlashTokenManager.sol";
import {NoDelegateCall} from "../NoDelegateCall.sol";

contract FlashTokenManager is NoDelegateCall, IFlashTokenManager {
    using LowGasSafeMath for uint256;

    address public immutable pool;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;

    event Flash(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 paid0,
        uint256 paid1
    );
    event SetFeeProtocol(uint8 feeProtocol0Old, uint8 feeProtocol1Old, uint8 feeProtocol0, uint8 feeProtocol1);
    event CollectProtocol(address indexed sender, address indexed recipient, uint128 amount0, uint128 amount1);

    error InsufficientLiquidity();
    error UnAuthorized();
    error InvalidBalance();

    modifier onlyPool() {
        if (msg.sender != pool) revert UnAuthorized();
        _;
    }

    constructor(address _pool, address _token0, address _token1, uint24 _fee) {
        pool = _pool;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }

    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, pool));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, pool));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data)
        external
        onlyPool
        noDelegateCall
    {
        uint128 _liquidity = IPool(pool).getLiquidity();
        if (_liquidity == 0) revert InsufficientLiquidity();

        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();

        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        ISupaSwapFlashCallback(msg.sender).supaSwapFlashCallback(int256(fee0), int256(fee1), data);

        if (balance0Before.add(fee0) > balance0()) revert InvalidBalance();
        if (balance1Before.add(fee1) > balance1()) revert InvalidBalance();

        uint256 paid0 = balance0() - balance0Before;
        uint256 paid1 = balance1() - balance1Before;

        (,,,,, uint8 feeProtocol,) = IPool(pool).getSlot0();

        if (paid0 > 0) {
            uint8 feeProtocol0 = feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
            if (fees0 > 0) {
                IPool(pool).addProtocolFeesCollected0(uint128(fees0));
                IPool(pool).setFeeGrowthGlobal0X128(
                    IPool(pool).feeGrowthGlobal0X128() + FullMath.mulDiv(paid0 - fees0, FixedPoint128.Q128, _liquidity)
                );
            }
        }
        if (paid1 > 0) {
            uint8 feeProtocol1 = feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
            if (fees1 > 0) {
                IPool(pool).addProtocolFeesCollected1(uint128(fees1));
                IPool(pool).setFeeGrowthGlobal1X128(
                    IPool(pool).feeGrowthGlobal1X128() + FullMath.mulDiv(paid1 - fees1, FixedPoint128.Q128, _liquidity)
                );
            }
        }

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override onlyPool {
        require(
            (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10))
                && (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10))
        );
        (,,,,, uint8 feeProtocolOld,) = IPool(pool).getSlot0();
        IPool(pool).setSlot0FeeProtocol(feeProtocol0 + (feeProtocol1 << 4));
        emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        override
        onlyPool
        returns (uint128 amount0, uint128 amount1)
    {
        amount0 = amount0Requested > uint128(IPool(pool).protocolFeesCollected0())
            ? uint128(IPool(pool).protocolFeesCollected0())
            : amount0Requested;
        amount1 = amount1Requested > uint128(IPool(pool).protocolFeesCollected1())
            ? uint128(IPool(pool).protocolFeesCollected1())
            : amount1Requested;

        if (amount0 > 0) {
            if (amount0 == IPool(pool).protocolFeesCollected0()) amount0--;
            IPool(pool).subProtocolFeesCollected0(amount0);
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            if (amount1 == IPool(pool).protocolFeesCollected1()) amount1--;
            IPool(pool).subProtocolFeesCollected1(amount1);
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}
