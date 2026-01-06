// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IHyperlaneRecipient
/// @notice Interface untuk kontrak yang menerima pesan via Hyperlane
/// @dev Diimplementasikan oleh KubiStreamerDonation untuk menerima donasi cross-chain
interface IHyperlaneRecipient {
    /// @notice Handler untuk pesan cross-chain dari Hyperlane
    /// @param _origin Chain ID asal pesan
    /// @param _sender Alamat pengirim (dalam format bytes32)
    /// @param _message Data pesan yang di-encode
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) external;
}
