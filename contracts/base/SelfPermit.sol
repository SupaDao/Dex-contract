// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ISelfPermit} from "../interfaces/ISwapPermit.sol";

abstract contract SelfPermit is ISelfPermit {
    /// @inheritdoc ISelfPermit
    function selfPermit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        override
    {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    /// @inheritdoc ISelfPermit
    /// @notice Calls permit on the token if current allowance is zero
    function selfPermitIfNecessary(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        override
    {
        if (IERC20(token).allowance(msg.sender, address(this)) < value) {
            IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
        }
    }

    /// @inheritdoc ISelfPermit
    function selfPermitAllowed(address token, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        payable
        override
    {
        // Call permit with the non-standard signature, approving max allowance
        (bool success,) = token.call(
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,bool,uint8,bytes32,bytes32)",
                msg.sender,
                address(this),
                nonce,
                expiry,
                true,
                v,
                r,
                s
            )
        );
        require(success, "SelfPermit: permit failed");
    }

    /// @inheritdoc ISelfPermit
    function selfPermitAllowedIfNecessary(address token, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        override
    {
        if (IERC20(token).allowance(msg.sender, address(this)) < type(uint256).max) {
            selfPermitAllowed(token, nonce, expiry, v, r, s);
        }
    }
}
