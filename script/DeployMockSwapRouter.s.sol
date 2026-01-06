// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/mocks/MockSwapRouter.sol";
import "../contracts/KubiStreamerDonation.sol";

/// @title DeployMockSwapRouter
/// @notice Deploy MockSwapRouter dan configure untuk testing
///
/// Usage:
/// ======
/// forge script script/DeployMockSwapRouter.s.sol \
///   --rpc-url https://rpc.sepolia.mantle.xyz \
///   --private-key $PRIVATE_KEY \
///   --broadcast -vvv

contract DeployMockSwapRouter is Script {
    // Token addresses (same on both chains)
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

    // Existing Factory address (for compatibility)
    address constant FACTORY = 0xf4dDf7D2F7dD24b4A0a24Bc6B91A2DE5e8873B6c;
    address constant WETH9 = 0x19f5557E23e9914A18239990f6C70D68FDF0deD5;

    // KubiStreamer address
    address constant KUBI_STREAMER = 0xDb26Ba8581979dc4E11218735F821Af5171fb737;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== DEPLOYING MockSwapRouter ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // 1. Deploy MockSwapRouter
        MockSwapRouter mockRouter = new MockSwapRouter(FACTORY, WETH9);
        console.log("MockSwapRouter deployed at:", address(mockRouter));

        // 2. Enable swap pairs (all tokens can swap to ETH)
        address[] memory tokens = new address[](10);
        tokens[0] = MNT;
        tokens[1] = ETH;
        tokens[2] = USDC;
        tokens[3] = USDT;
        tokens[4] = PUFF;
        tokens[5] = AXL;
        tokens[6] = SVL;
        tokens[7] = LINK;
        tokens[8] = WBTC;
        tokens[9] = PENDLE;

        console.log("\nEnabling swap pairs...");
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                mockRouter.setSwapEnabled(tokens[i], tokens[j], true);
            }
        }
        console.log("  Enabled all token pairs");

        // 3. Update router in KubiStreamer
        console.log("\nUpdating router in KubiStreamer...");
        KubiStreamerDonation kubi = KubiStreamerDonation(payable(KUBI_STREAMER));
        kubi.setSwapRouter(address(mockRouter));
        console.log("  Router updated");

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("MockSwapRouter:", address(mockRouter));
        console.log("\nNEXT STEPS:");
        console.log("1. Deposit tokens to MockSwapRouter for swap output");
        console.log("2. Test cross-chain donation with swap");
    }
}
