// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title TransferHelper
/// @notice Safely handles ERC20 transfers and ETH transfers, accounting for non-standard tokens
library TransferHelper {
    error TransferFailed();
    error InvalidAddress();
    error InvalidAmount();

    /// @notice Safely approves an ERC20 token for spending by another address
    /// @param token The ERC20 token contract address
    /// @param to The address to approve for spending
    /// @param value The amount to approve
    /// @dev Reverts with TransferFailed if the approval fails or InvalidAddress/InvalidAmount for invalid inputs
    function safeApprove(address token, address to, uint256 value) internal {
        if (token == address(0) || to == address(0)) revert InvalidAddress();
        if (value == 0) revert InvalidAmount();
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }

    /// @notice Safely transfers ERC20 tokens to a recipient
    /// @param token The ERC20 token contract address
    /// @param to The recipient address
    /// @param value The amount to transfer
    /// @dev Reverts with TransferFailed if the transfer fails or InvalidAddress/InvalidAmount for invalid inputs
    function safeTransfer(address token, address to, uint256 value) internal {
        if (token == address(0) || to == address(0)) revert InvalidAddress();
        if (value == 0) revert InvalidAmount();
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }

    /// @notice Safely transfers ERC20 tokens from a sender to a recipient
    /// @param token The ERC20 token contract address
    /// @param from The sender address
    /// @param to The recipient address
    /// @param value The amount to transfer
    /// @dev Reverts with TransferFailed if the transfer fails or InvalidAddress/InvalidAmount for invalid inputs
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        if (token == address(0) || from == address(0) || to == address(0)) revert InvalidAddress();
        if (value == 0) revert InvalidAmount();
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, to, value)
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }

    /// @notice Safely transfers ETH to a recipient
    /// @param to The recipient address
    /// @param value The amount of ETH to transfer
    /// @dev Reverts with TransferFailed if the transfer fails or InvalidAddress/InvalidAmount for invalid inputs
    function safeTransferETH(address to, uint256 value) internal {
        if (to == address(0)) revert InvalidAddress();
        if (value == 0) revert InvalidAmount();
        (bool success,) = to.call{value: value, gas: 2300}("");
        if (!success) {
            revert TransferFailed();
        }
    }
}
