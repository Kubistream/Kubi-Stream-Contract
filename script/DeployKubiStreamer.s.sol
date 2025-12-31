// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/KubiStreamerDonation.sol";

/// @title Deploy KubiStreamerDonation Contract (CREATE2 deterministic)
/// @notice Deployment script using CREATE2 for same address across all chains.
/// @dev IMPORTANT: Set KUBI_STREAMER_SALT to the SAME value on ALL chains!
contract DeployKubiStreamer is Script {

    // ============ CONFIGURATION STRUCTS ============
    struct DeployConfig {
        address router;
        address superAdmin;
        uint16 feeBps;
        address feeRecipient;
        uint32 hubChainId;
        bool isHubChain;
        bytes32 salt;
        string saltString;
    }

    // ============ MAIN DEPLOYMENT ============
    function run() external {
        DeployConfig memory config = _loadConfig();
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        
        vm.startBroadcast(privateKey);

        KubiStreamerDonation donation = new KubiStreamerDonation{salt: config.salt}(
            config.router,
            config.superAdmin,
            config.feeBps,
            config.feeRecipient,
            config.hubChainId,
            deployer  // Owner for CREATE2 compatibility
        );

        _logDeployment(config, address(donation));

        // Set isHubChain
        donation.setIsHubChain(config.isHubChain);

        // Configure whitelist, pool fees, and yield configs
        _configureWhitelist(donation);
        _configurePoolFees(donation);
        _configureYields(donation);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Chain:", config.isHubChain ? "HUB (Mantle)" : "SPOKE (Base)");
        console.logAddress(address(donation));
        console.log("========================\n");
    }

    // ============ LOAD CONFIG ============
    function _loadConfig() internal view returns (DeployConfig memory) {
        string memory saltString = vm.envString("KUBI_STREAMER_SALT");
        
        DeployConfig memory config = DeployConfig({
            router: vm.envOr("KUBI_ROUTER", address(0)),
            superAdmin: vm.envOr("KUBI_SUPER_ADMIN", address(0)),
            feeBps: uint16(vm.envOr("KUBI_FEE_BPS", uint256(250))),
            feeRecipient: vm.envOr("KUBI_FEE_RECIPIENT", address(0)),
            hubChainId: uint32(vm.envOr("KUBI_HUB_CHAIN_ID", uint256(5001))),
            isHubChain: vm.envOr("KUBI_IS_HUB", uint256(0)) == 1,
            salt: keccak256(abi.encodePacked(saltString)),
            saltString: saltString
        });

        require(config.router != address(0), "Deploy: router zero");
        require(config.superAdmin != address(0), "Deploy: superAdmin zero");
        require(config.feeRecipient != address(0), "Deploy: feeRecipient zero");
        require(bytes(saltString).length > 0, "Deploy: KUBI_STREAMER_SALT required");

        return config;
    }

    // ============ LOGGING ============
    function _logDeployment(DeployConfig memory config, address deployed) internal pure {
        console.log("\n=== KubiStreamerDonation Deployment (CREATE2) ===");
        console.log("Salt string:", config.saltString);
        console.log("Salt hash:");
        console.logBytes32(config.salt);
        console.log("Deployed at:");
        console.logAddress(deployed);
        console.log("[INFO] CREATE2 deploy - same address on all chains with same salt!\n");
        console.log("Setting isHubChain to:", config.isHubChain ? "true (HUB)" : "false (SPOKE)");
    }

    // ============ WHITELIST CONFIG ============
    function _configureWhitelist(KubiStreamerDonation donation) internal {
        console.log("Setting token whitelist...");
        
        // Token whitelist - 10 tokens
        address[10] memory tokens = [
            0x33c6f26dA09502E6540043f030aE1F87f109cc99, // MNT
            0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b, // ETH
            0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13, // USDC
            0xC4a53c466Cfb62AecED03008B0162baaf36E0B03, // USDT
            0x70Db6eFB75c898Ad1e194FDA2B8C6e73dbC944d6, // PUFF
            0xEE589FBF85128abA6f42696dB2F28eA9EBddE173, // AXL
            0x2C036be74942c597e4d81D7050008dDc11becCEb, // SVL
            0x90CdcBF4c4bc78dC440252211EFd744d0A4Dc4A1, // LINK
            0xced6Ceb47301F268d57fF07879DF45Fda80e6974, // WBTC
            0x782Ba48189AF93a0CF42766058DE83291f384bF3  // PENDLE
        ];

        for (uint256 i = 0; i < tokens.length; ++i) {
            donation.setGlobalWhitelist(tokens[i], true);
        }
    }

    // ============ POOL FEES CONFIG ============
    function _configurePoolFees(KubiStreamerDonation donation) internal {
        console.log("Setting pool fees...");
        
        address eth = 0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b;
        address usdc = 0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13;
        address usdt = 0xC4a53c466Cfb62AecED03008B0162baaf36E0B03;

        donation.setPoolFee(eth, usdc, 3000);
        donation.setPoolFee(eth, usdt, 3000);
    }

    // ============ YIELD CONFIG ============
    function _configureYields(KubiStreamerDonation donation) internal {
        console.log("Setting yield configurations...");
        _configureYieldsMinterest(donation);
        _configureYieldsLendle(donation);
        _configureYieldsInitCapital(donation);
        _configureYieldsCompound(donation);
    }

    // Minterest yields (5)
    function _configureYieldsMinterest(KubiStreamerDonation donation) internal {
        // miUSDC -> USDC
        donation.setYieldConfig(0x2007Cb1a90E71c18983F1d4091261816E9e9c2dA, 0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13, true, 0);
        // miUSDT -> USDT
        donation.setYieldConfig(0x04F0aEf9cb921A8Ad848FA8B49aF7fc2E60DbcCb, 0xC4a53c466Cfb62AecED03008B0162baaf36E0B03, true, 0);
        // miMNT -> MNT
        donation.setYieldConfig(0x8c2B7136dDaF6129cE33f58d3E5475a0ed3F7b3C, 0x33c6f26dA09502E6540043f030aE1F87f109cc99, true, 0);
        // miBTC -> WBTC
        donation.setYieldConfig(0x8e0dCfecDEEBb1da38DD1bbE9418FD7a4bdd4922, 0xced6Ceb47301F268d57fF07879DF45Fda80e6974, true, 0);
        // miETH -> ETH
        donation.setYieldConfig(0x89C0fa2BAE88752eC733922daa0c2Ff321bb5279, 0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b, true, 0);
    }

    // Lendle yields (5)
    function _configureYieldsLendle(KubiStreamerDonation donation) internal {
        // leUSDC -> USDC
        donation.setYieldConfig(0xa6c9dD702B198Da46f9C5b21bBe65a2a31fdEB63, 0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13, true, 0);
        // leUSDT -> USDT
        donation.setYieldConfig(0x5c8b8caa55Af0d10ACc3ec95A614d26C90BD9b62, 0xC4a53c466Cfb62AecED03008B0162baaf36E0B03, true, 0);
        // leMNT -> MNT
        donation.setYieldConfig(0xfCbFBaf16A7b392F5963232fC3d7bb81238a4Fc1, 0x33c6f26dA09502E6540043f030aE1F87f109cc99, true, 0);
        // leBTC -> WBTC
        donation.setYieldConfig(0x0dF313cE12b511062eCe811e435F0729E7c9746f, 0xced6Ceb47301F268d57fF07879DF45Fda80e6974, true, 0);
        // leETH -> ETH
        donation.setYieldConfig(0xB1eF139d2f4D56B126196D9FF712b67e120c0349, 0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b, true, 0);
    }

    // INIT Capital yields (5)
    function _configureYieldsInitCapital(KubiStreamerDonation donation) internal {
        // aaUSDC -> USDC
        donation.setYieldConfig(0x324Db0D78D0225431A2bD49470018b322a006833, 0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13, true, 0);
        // aaUSDT -> USDT
        donation.setYieldConfig(0xbF1dC15Eaa6449d5bf81463578808313F5e208Ee, 0xC4a53c466Cfb62AecED03008B0162baaf36E0B03, true, 0);
        // aaMNT -> MNT
        donation.setYieldConfig(0xc79F99285A0f4B640c552090eEab8CAbc4433C1D, 0x33c6f26dA09502E6540043f030aE1F87f109cc99, true, 0);
        // aaBTC -> WBTC
        donation.setYieldConfig(0xA5FC97D4eEE36Cf0CF5beE22cF78e74cE9882E81, 0xced6Ceb47301F268d57fF07879DF45Fda80e6974, true, 0);
        // aaETH -> ETH
        donation.setYieldConfig(0xdf3eBc828195ffBc71bB80c467cF70BfDEf0AC1E, 0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b, true, 0);
    }

    // Compound yields (5)
    function _configureYieldsCompound(KubiStreamerDonation donation) internal {
        // coUSDC -> USDC
        donation.setYieldConfig(0x8edafBaDe92450979DfF2F10449E7917c722AF50, 0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13, true, 0);
        // coUSDT -> USDT
        donation.setYieldConfig(0xdf5Ca06845d1b2F3ddff5759a493fB5aff68d72d, 0xC4a53c466Cfb62AecED03008B0162baaf36E0B03, true, 0);
        // coMNT -> MNT
        donation.setYieldConfig(0xBfc03BA44AcA79cFe6732968f99E9DB0B3880828, 0x33c6f26dA09502E6540043f030aE1F87f109cc99, true, 0);
        // coBTC -> WBTC
        donation.setYieldConfig(0x4E55B3951d334aF5a88474d252f789911E1EFc55, 0xced6Ceb47301F268d57fF07879DF45Fda80e6974, true, 0);
        // coETH -> ETH
        donation.setYieldConfig(0xE54116B3FA1623EB5aAC2ED4628002ceE620E9D8, 0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b, true, 0);
    }
}
