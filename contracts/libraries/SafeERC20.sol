// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";
import {ZeroAddress} from "../errors/Errors.sol";

library SafeERC20 {
    function safeTransfer(IERC20 t, address to, uint256 v) internal {
        if (to == address(0)) revert ZeroAddress();
        require(t.transfer(to, v), "TRANSFER_FAIL");
    }
    function safeTransferFrom(IERC20 t, address f, address to, uint256 v) internal {
        if (to == address(0)) revert ZeroAddress();
        require(t.transferFrom(f, to, v), "TRANSFER_FROM_FAIL");
    }
    function safeApprove(IERC20 t, address s, uint256 v) internal {
        if (s == address(0)) revert ZeroAddress();
        require(t.approve(s, v), "APPROVE_FAIL");
    }
}