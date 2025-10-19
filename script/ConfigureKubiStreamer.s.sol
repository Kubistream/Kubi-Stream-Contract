// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/KubiStreamerDonation.sol";

/// @notice Helper script to batch update global token whitelist and yield configs.
/// @dev Fill the placeholders below with the addresses that apply to your deployment.
contract ConfigureKubiStreamer is Script {
    /// -----------------------------------------------------------------------
    /// ─── USER CONFIGURATION SECTION ────────────────────────────────────────
    /// -----------------------------------------------------------------------

    /// @notice Address of the deployed KubiStreamerDonation contract.
    address internal constant KUBI_STREAMER = 0x0000000000000000000000000000000000000000; // TODO: replace

    /// @notice Tokens to (de)whitelist globally. Use address(0) for native token.
    address[] internal globalTokens = new address[](0); // e.g. push tokens in setUpWhitelist()
    bool[] internal globalStatuses = new bool[](0);

    /// @notice Yield configurations to register. Vault can be zero if unused.
    struct YieldSetup {
        address yieldContract;
        address underlying;
        address vault;
        bool allowed;
        uint256 minDonation; // in underlying decimals, after fee
    }

    YieldSetup[] internal yieldSetups;

    /// -----------------------------------------------------------------------
    /// ─── INTERNAL CONFIG INITIALISERS ──────────────────────────────────────
    /// -----------------------------------------------------------------------

    function setUpWhitelist() internal {
        // Example:
        // globalTokens = new address[](3);
        // globalStatuses = new bool[](3);
        // globalTokens[0] = address(0); // Native token
        // globalStatuses[0] = true;
        // globalTokens[1] = 0x...; // USDC
        // globalStatuses[1] = true;
        // globalTokens[2] = 0x...; // Remove a token
        // globalStatuses[2] = false;
    }

    function setUpYields() internal {
        // Example:
        // yieldSetups.push(
        //     YieldSetup({
        //         yieldContract: 0x...,
        //         underlying: 0x..., // same as primary token
        //         vault: address(0),  // optional
        //         allowed: true,
        //         minDonation: 1e6    // require >= 1 unit (adjust decimals)
        //     })
        // );
    }

    /// -----------------------------------------------------------------------
    /// ─── EXECUTION ─────────────────────────────────────────────────────────
    /// -----------------------------------------------------------------------

    function run() external {
        require(KUBI_STREAMER != address(0), "Configure: set KUBI_STREAMER");

        setUpWhitelist();
        setUpYields();
        require(globalTokens.length == globalStatuses.length, "Configure: whitelist length mismatch");

        vm.startBroadcast();

        KubiStreamerDonation kubi = KubiStreamerDonation(KUBI_STREAMER);

        for (uint256 i = 0; i < globalTokens.length; i++) {
            kubi.setGlobalWhitelist(globalTokens[i], globalStatuses[i]);
        }

        for (uint256 i = 0; i < yieldSetups.length; i++) {
            YieldSetup memory cfg = yieldSetups[i];
            require(cfg.yieldContract != address(0), "Configure: yield zero");
            kubi.setYieldConfig(cfg.yieldContract, cfg.underlying, cfg.vault, cfg.allowed, cfg.minDonation);
        }

        vm.stopBroadcast();
    }
}
