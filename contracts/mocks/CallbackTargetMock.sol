// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISupaSwapMintCallback} from "../core/interfaces/callback/ISupaSwapMintCallback.sol";
import {ISupaSwapCallback} from "../core/interfaces/callback/ISupaSwapCallback.sol";

contract CallbackTargetMock is ISupaSwapMintCallback, ISupaSwapCallback {
    address public payer;

    constructor(address _payer) {
        payer = _payer;
    }

    function supaSwapMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        (address token0, address token1) = abi.decode(data, (address, address));

        if (amount0Owed > 0) {
            _safeTransfer(token0, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            _safeTransfer(token1, msg.sender, amount1Owed);
        }
    }

    function supaSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        (address token0, address token1) = abi.decode(data, (address, address));

        if (amount0Delta > 0) {
            _safeTransfer(token0, msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            _safeTransfer(token1, msg.sender, uint256(amount1Delta));
        }
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        // Calls token.transfer(to, value)
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "CallbackMock: transfer failed");
    }
}
