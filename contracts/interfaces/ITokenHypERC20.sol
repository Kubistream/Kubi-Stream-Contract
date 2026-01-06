// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ITokenHypERC20 Interface
/// @notice Interface for Hyperlane-enabled ERC20 tokens with cross-chain transfer capability
interface ITokenHypERC20 {
    /// @notice Transfers tokens to a recipient on a remote chain with custom metadata
    /// @param _destination The domain ID of the destination chain
    /// @param _recipient The recipient address as bytes32 (left-padded)
    /// @param _amount The amount of tokens to transfer
    /// @param _customMetadata Custom metadata to send with the transfer
    /// @return messageId The Hyperlane message ID
    function transferRemoteWithMetadata(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount,
        bytes memory _customMetadata
    ) external payable returns (bytes32 messageId);

    /// @notice Gets the quote for interchain gas payment
    /// @param _destination The domain ID of the destination chain
    /// @param _amount The amount of tokens to transfer
    /// @return gasPayment The amount of native token required for gas
    function quoteGasPayment(uint32 _destination, uint256 _amount) external view returns (uint256 gasPayment);
}
