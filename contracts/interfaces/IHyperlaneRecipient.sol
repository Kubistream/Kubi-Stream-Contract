// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IHyperlaneRecipient
/// @notice Interface for contracts that receive messages via Hyperlane
interface IHyperlaneRecipient {
    /// @notice Called by Hyperlane Mailbox when receiving a message from another chain
    /// @param origin The domain ID of the origin chain
    /// @param sender The address of the sender as bytes32
    /// @param message The message body
    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata message
    ) external;
}
