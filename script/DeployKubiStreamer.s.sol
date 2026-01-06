// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/KubiStreamerDonation.sol";

/// @title DeployKubiStreamer
/// @notice Deploy KubiStreamerDonation dengan addresses dari contracts.json (hardcoded)
/// @dev Addresses sama di kedua chain (CREATE2 deployment)
///

contract DeployKubiStreamer is Script {
    address constant MNT    = 0x33c6f26dA09502E6540043f030aE1F87f109cc99;
    address constant ETH    = 0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b;
    address constant USDC   = 0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13;
    address constant USDT   = 0xC4a53c466Cfb62AecED03008B0162baaf36E0B03;
    address constant PUFF   = 0x70Db6eFB75c898Ad1e194FDA2B8C6e73dbC944d6;
    address constant AXL    = 0xEE589FBF85128abA6f42696dB2F28eA9EBddE173;
    address constant SVL    = 0x2C036be74942c597e4d81D7050008dDc11becCEb;
    address constant LINK   = 0x90CdcBF4c4bc78dC440252211EFd744d0A4Dc4A1;
    address constant WBTC   = 0xced6Ceb47301F268d57fF07879DF45Fda80e6974;
    address constant PENDLE = 0x782Ba48189AF93a0CF42766058DE83291f384bF3;

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD CONTRACT ADDRESSES (Mantle Sepolia only - from contracts.json)
    // ═══════════════════════════════════════════════════════════════════════
    // Minterest
    address constant miUSDC = 0x2007Cb1a90E71c18983F1d4091261816E9e9c2dA;
    address constant miUSDT = 0x04F0aEf9cb921A8Ad848FA8B49aF7fc2E60DbcCb;
    address constant miMNT  = 0x8c2B7136dDaF6129cE33f58d3E5475a0ed3F7b3C;
    address constant miBTC  = 0x8e0dCfecDEEBb1da38DD1bbE9418FD7a4bdd4922;
    address constant miETH  = 0x89C0fa2BAE88752eC733922daa0c2Ff321bb5279;
    // Lendle
    address constant leUSDC = 0xa6c9dD702B198Da46f9C5b21bBe65a2a31fdEB63;
    address constant leUSDT = 0x5c8b8caa55Af0d10ACc3ec95A614d26C90BD9b62;
    address constant leMNT  = 0xfCbFBaf16A7b392F5963232fC3d7bb81238a4Fc1;
    address constant leBTC  = 0x0dF313cE12b511062eCe811e435F0729E7c9746f;
    address constant leETH  = 0xB1eF139d2f4D56B126196D9FF712b67e120c0349;
    // INIT Capital
    address constant aaUSDC = 0x324Db0D78D0225431A2bD49470018b322a006833;
    address constant aaUSDT = 0xbF1dC15Eaa6449d5bf81463578808313F5e208Ee;
    address constant aaMNT  = 0xc79F99285A0f4B640c552090eEab8CAbc4433C1D;
    address constant aaBTC  = 0xA5FC97D4eEE36Cf0CF5beE22cF78e74cE9882E81;
    address constant aaETH  = 0xdf3eBc828195ffBc71bB80c467cF70BfDEf0AC1E;
    // Compound
    address constant coUSDC = 0x8edafBaDe92450979DfF2F10449E7917c722AF50;
    address constant coUSDT = 0xdf5Ca06845d1b2F3ddff5759a493fB5aff68d72d;
    address constant coMNT  = 0xBfc03BA44AcA79cFe6732968f99E9DB0B3880828;
    address constant coBTC  = 0x4E55B3951d334aF5a88474d252f789911E1EFc55;
    address constant coETH  = 0xE54116B3FA1623EB5aAC2ED4628002ceE620E9D8;

    function run() external {
        // ═══════════════════════════════════════════════════════════════════════
        // ENVIRONMENT CONFIG
        // ═══════════════════════════════════════════════════════════════════════
        address router = vm.envOr("KUBI_ROUTER", address(0));
        address superAdmin = vm.envOr("KUBI_SUPER_ADMIN", address(0));
        uint16 feeBps = uint16(vm.envOr("KUBI_FEE_BPS", uint256(250)));
        address feeRecipient = vm.envOr("KUBI_FEE_RECIPIENT", address(0));
        
        require(router != address(0), "Deploy: KUBI_ROUTER not set");
        require(superAdmin != address(0), "Deploy: KUBI_SUPER_ADMIN not set");
        require(feeRecipient != address(0), "Deploy: KUBI_FEE_RECIPIENT not set");

        // ═══════════════════════════════════════════════════════════════════════
        // WHITELIST TOKENS (same on both chains)
        // ═══════════════════════════════════════════════════════════════════════
        address[] memory whitelistTokens = new address[](10);
        whitelistTokens[0] = MNT;
        whitelistTokens[1] = ETH;
        whitelistTokens[2] = USDC;
        whitelistTokens[3] = USDT;
        whitelistTokens[4] = PUFF;
        whitelistTokens[5] = AXL;
        whitelistTokens[6] = SVL;
        whitelistTokens[7] = LINK;
        whitelistTokens[8] = WBTC;
        whitelistTokens[9] = PENDLE;

        // ═══════════════════════════════════════════════════════════════════════
        // YIELD CONFIGS (Mantle only - 20 yield contracts)
        // ═══════════════════════════════════════════════════════════════════════
        address[] memory yieldContracts = new address[](20);
        address[] memory underlyingTokens = new address[](20);
        
        // Minterest (indices 0-4)
        yieldContracts[0] = miUSDC;  underlyingTokens[0] = USDC;
        yieldContracts[1] = miUSDT;  underlyingTokens[1] = USDT;
        yieldContracts[2] = miMNT;   underlyingTokens[2] = MNT;
        yieldContracts[3] = miBTC;   underlyingTokens[3] = WBTC;
        yieldContracts[4] = miETH;   underlyingTokens[4] = ETH;
        
        // Lendle (indices 5-9)
        yieldContracts[5] = leUSDC;  underlyingTokens[5] = USDC;
        yieldContracts[6] = leUSDT;  underlyingTokens[6] = USDT;
        yieldContracts[7] = leMNT;   underlyingTokens[7] = MNT;
        yieldContracts[8] = leBTC;   underlyingTokens[8] = WBTC;
        yieldContracts[9] = leETH;   underlyingTokens[9] = ETH;
        
        // INIT Capital (indices 10-14)
        yieldContracts[10] = aaUSDC; underlyingTokens[10] = USDC;
        yieldContracts[11] = aaUSDT; underlyingTokens[11] = USDT;
        yieldContracts[12] = aaMNT;  underlyingTokens[12] = MNT;
        yieldContracts[13] = aaBTC;  underlyingTokens[13] = WBTC;
        yieldContracts[14] = aaETH;  underlyingTokens[14] = ETH;
        
        // Compound (indices 15-19)
        yieldContracts[15] = coUSDC; underlyingTokens[15] = USDC;
        yieldContracts[16] = coUSDT; underlyingTokens[16] = USDT;
        yieldContracts[17] = coMNT;  underlyingTokens[17] = MNT;
        yieldContracts[18] = coBTC;  underlyingTokens[18] = WBTC;
        yieldContracts[19] = coETH;  underlyingTokens[19] = ETH;

        // ═══════════════════════════════════════════════════════════════════════
        // DEPLOY
        // ═══════════════════════════════════════════════════════════════════════
        console.log("=== DEPLOYING KubiStreamerDonation ===");
        console.log("Chain ID:", block.chainid);
        console.log("Router:", router);
        console.log("SuperAdmin:", superAdmin);
        console.log("FeeBps:", feeBps);
        console.log("FeeRecipient:", feeRecipient);

        vm.startBroadcast();
        
        KubiStreamerDonation donation = new KubiStreamerDonation(router, superAdmin, feeBps, feeRecipient);
        console.log("\nDeployed at:", address(donation));

        // Set global whitelist
        console.log("\nSetting global whitelist for", whitelistTokens.length, "tokens...");
        for (uint256 i = 0; i < whitelistTokens.length; ++i) {
            donation.setGlobalWhitelist(whitelistTokens[i], true);
        }

        // Set yield configs (only for Mantle Sepolia hub chain)
        if (block.chainid == 5003) {
            console.log("\nSetting yield configs for", yieldContracts.length, "yield contracts...");
            for (uint256 j = 0; j < yieldContracts.length; ++j) {
                donation.setYieldConfig(
                    yieldContracts[j],
                    underlyingTokens[j],
                    true,  // allowed
                    0      // minDonation
                );
            }
        } else {
            console.log("\nSkipping yield configs (not hub chain)");
        }

        vm.stopBroadcast();
        
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Contract address:", address(donation));
    }
}
