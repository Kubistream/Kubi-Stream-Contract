// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/KubiStreamerDonation.sol";

/// @title ConfigureCrossChain
/// @notice Script untuk konfigurasi cross-chain bridging antara Base Sepolia (Spoke) dan Mantle Sepolia (Hub)

contract ConfigureCrossChain is Script {
    // Chain Domain IDs (Hyperlane)
    uint32 constant MANTLE_SEPOLIA_DOMAIN = 5003;
    uint32 constant BASE_SEPOLIA_DOMAIN = 84532;

    // KubiStreamer addresses (deployed 2026-01-06)
    address constant MANTLE_KUBI_STREAMER = 0x888361c3362712Ba6BB442cbF714038fCe0d9e49;
    address constant BASE_KUBI_STREAMER = 0xF3607A98c7a4c0a41F62C1492a771C47c4ed62Dc;

    // HypERC20 token addresses (same on both chains via CREATE2)
    address[] internal hypTokens;

    function setUp() public {
        // Token addresses from contracts.json (same on both chains)
        hypTokens.push(0x33c6f26dA09502E6540043f030aE1F87f109cc99); // MNT
        hypTokens.push(0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b); // ETH
        hypTokens.push(0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13); // USDC
        hypTokens.push(0xC4a53c466Cfb62AecED03008B0162baaf36E0B03); // USDT
        hypTokens.push(0x70Db6eFB75c898Ad1e194FDA2B8C6e73dbC944d6); // PUFF
        hypTokens.push(0xEE589FBF85128abA6f42696dB2F28eA9EBddE173); // AXL
        hypTokens.push(0x2C036be74942c597e4d81D7050008dDc11becCEb); // SVL
        hypTokens.push(0x90CdcBF4c4bc78dC440252211EFd744d0A4Dc4A1); // LINK
        hypTokens.push(0xced6Ceb47301F268d57fF07879DF45Fda80e6974); // WBTC
        hypTokens.push(0x782Ba48189AF93a0CF42766058DE83291f384bF3); // PENDLE
    }

    function run() external {
        address kubiAddress = vm.envAddress("KUBI_STREAMER");
        string memory mode = vm.envString("KUBI_MODE");

        require(kubiAddress != address(0), "Set KUBI_STREAMER env var");
        require(bytes(mode).length > 0, "Set KUBI_MODE to 'hub' or 'spoke'");

        KubiStreamerDonation kubi = KubiStreamerDonation(payable(kubiAddress));

        vm.startBroadcast();

        if (keccak256(bytes(mode)) == keccak256(bytes("hub"))) {
            _configureHub(kubi);
        } else if (keccak256(bytes(mode)) == keccak256(bytes("spoke"))) {
            _configureSpoke(kubi);
        } else {
            revert("KUBI_MODE must be 'hub' or 'spoke'");
        }

        vm.stopBroadcast();

        console.log("Cross-chain configuration complete!");
    }

    /// @notice Configure Mantle Sepolia as Hub chain
    function _configureHub(KubiStreamerDonation kubi) internal {
        console.log("Configuring as HUB chain (Mantle Sepolia)...");

        // 1. Set as hub chain
        kubi.setIsHubChain(true);
        console.log("  setIsHubChain(true)");

        // 2. Trust tokens from Base Sepolia
        console.log("  Setting trusted remote tokens from Base (84532)...");
        for (uint256 i = 0; i < hypTokens.length; i++) {
            kubi.setTrustedRemoteToken(BASE_SEPOLIA_DOMAIN, hypTokens[i], true);
        }
        console.log("  Trusted", hypTokens.length, "tokens");

        // 3. Whitelist HypERC20 tokens in global whitelist
        console.log("  Setting global whitelist...");
        for (uint256 i = 0; i < hypTokens.length; i++) {
            kubi.setGlobalWhitelist(hypTokens[i], true);
        }
        console.log("  Whitelisted", hypTokens.length, "tokens");

        console.log("Hub configuration complete!");
    }

    /// @notice Configure Base Sepolia as Spoke chain
    function _configureSpoke(KubiStreamerDonation kubi) internal {
        console.log("Configuring as SPOKE chain (Base Sepolia)...");

        // 1. Set as spoke chain (not hub)
        kubi.setIsHubChain(false);
        console.log("  setIsHubChain(false)");

        // 2. Set hub chain domain ID
        kubi.setHubChainDomainId(MANTLE_SEPOLIA_DOMAIN);
        console.log("  setHubChainDomainId(5003)");

        // 3. Set hub contract address (KubiStreamer on Mantle)
        kubi.setHubContractAddress(MANTLE_KUBI_STREAMER);
        console.log("  setHubContractAddress set");

        // 4. Map each HypERC20 token to itself (token IS the HypERC20)
        console.log("  Setting tokenToHypToken mappings...");
        for (uint256 i = 0; i < hypTokens.length; i++) {
            kubi.setTokenToHypToken(hypTokens[i], hypTokens[i]);
        }
        console.log("  Mapped", hypTokens.length, "tokens");

        // 5. Whitelist HypERC20 tokens in global whitelist
        console.log("  Setting global whitelist...");
        for (uint256 i = 0; i < hypTokens.length; i++) {
            kubi.setGlobalWhitelist(hypTokens[i], true);
        }
        console.log("  Whitelisted", hypTokens.length, "tokens");

        console.log("Spoke configuration complete!");
    }
}
