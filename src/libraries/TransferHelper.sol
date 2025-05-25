//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/ITransferHelperErrors.sol";

library TransferHelper {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @dev Reverts with `TransferFromFailed` if transfer fails.
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert TransferFromFailed();
        }
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Reverts with `TransferFailed` if transfer fails.
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Reverts with `ApproveFailed` if transfer fails.
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert ApproveFailed();
        }
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Reverts with `ETHTransferFailed` if transfer fails.
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        if (!success) {
            revert ETHTransferFailed();
        }
    }
}
