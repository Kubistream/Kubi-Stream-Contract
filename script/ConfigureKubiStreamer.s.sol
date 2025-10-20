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
    address payable internal constant KUBI_STREAMER = payable(0x88F3Bbca0Ad217dE7286C74C061652dE40e26104); // TODO: replace

    /// @notice Tokens to (de)whitelist globally. Use address(0) for native token.
    address[] internal globalTokens = new address[](0); // e.g. push tokens in setUpWhitelist()
    bool[] internal globalStatuses = new bool[](0);

    /// @notice Yield configurations to register. Vault can be zero if unused.
    struct YieldSetup {
        address yieldContract;
        address underlying;
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
        delete yieldSetups;

        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xAee2A87701aFEF956473d547bD02cD736729D8a7"),
            underlying: vm.parseAddress("0x1fE9A4E25cAA2a22FC0B61010fDB0DB462FB5b29"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x6aaBE7258f09474e62E8BebB1cf90E15fbAAF777"),
            underlying: vm.parseAddress("0x5e1E8043381F3A21a1A64f46073daF7E74fEdC1E"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x5C70fB2a739e9e7Ad5c4311ABF99E0fB65c07eE9"),
            underlying: vm.parseAddress("0x06C1e044D5BEb614faA6128001F519e6c693a044"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xbB6Dd87f1fe0483d9FFA90f7A163Caf21F40BA6c"),
            underlying: vm.parseAddress("0x85B8Dc34C7Af35baC8a45CfF53353f39E6F732A2"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xcE74630446990AcF6Cd56facBbd6EE908eE55562"),
            underlying: vm.parseAddress("0x7392e9E58f202Da3877776c41683AC457DFd4CD7"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xdCC41dee829C1246a936dC5E801cB24303445651"),
            underlying: vm.parseAddress("0x1fE9A4E25cAA2a22FC0B61010fDB0DB462FB5b29"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x8f5816ca88ED2775305b154625744E36943Cc750"),
            underlying: vm.parseAddress("0x5e1E8043381F3A21a1A64f46073daF7E74fEdC1E"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x2BB55f68fb05De13B04e5a2cadbAE5A05bCE277B"),
            underlying: vm.parseAddress("0x06C1e044D5BEb614faA6128001F519e6c693a044"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xa022FD1966577144fCb5Ed8aD5a134861aE5e138"),
            underlying: vm.parseAddress("0x85B8Dc34C7Af35baC8a45CfF53353f39E6F732A2"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xEC4c46F46191d77C3D8Ba3ddFafe71b58E2089Af"),
            underlying: vm.parseAddress("0x7392e9E58f202Da3877776c41683AC457DFd4CD7"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xE47Eba0dBf716D99482Fb071ca04aDf4FCCd6b1f"),
            underlying: vm.parseAddress("0x1fE9A4E25cAA2a22FC0B61010fDB0DB462FB5b29"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x4E3A466BbA553Ace4Cd3a6149d574F3f034b5269"),
            underlying: vm.parseAddress("0x5e1E8043381F3A21a1A64f46073daF7E74fEdC1E"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x751A0E0147d10b8C21804AC88DCfa6837312ea35"),
            underlying: vm.parseAddress("0x06C1e044D5BEb614faA6128001F519e6c693a044"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xD8D362BADb84Cc1F97a00273ddC8845FD4148C80"),
            underlying: vm.parseAddress("0x85B8Dc34C7Af35baC8a45CfF53353f39E6F732A2"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x1061473A78f6eb0a0BcBDE060a5EeA9d4273BB59"),
            underlying: vm.parseAddress("0x7392e9E58f202Da3877776c41683AC457DFd4CD7"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x824FB936D24B2BAaF92Fe87FD65fF22d01439ECE"),
            underlying: vm.parseAddress("0x1fE9A4E25cAA2a22FC0B61010fDB0DB462FB5b29"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x012bd7CD0AcC8cB696306B1aB7a537E85eF2056f"),
            underlying: vm.parseAddress("0x5e1E8043381F3A21a1A64f46073daF7E74fEdC1E"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x4d8346F2F33FFBc7fa2E46bECF83C978943e69C8"),
            underlying: vm.parseAddress("0x06C1e044D5BEb614faA6128001F519e6c693a044"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0x2db087D43Fc8402aDE0706807d32d6EF72411ebd"),
            underlying: vm.parseAddress("0x85B8Dc34C7Af35baC8a45CfF53353f39E6F732A2"),
            allowed: true,
            minDonation: 0
        }));
        yieldSetups.push(YieldSetup({
            yieldContract: vm.parseAddress("0xD14bD87b18dA3Ec84a9e098DF1c808d9cb7a9852"),
            underlying: vm.parseAddress("0x7392e9E58f202Da3877776c41683AC457DFd4CD7"),
            allowed: true,
            minDonation: 0
        }));
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
            kubi.setYieldConfig(cfg.yieldContract, cfg.underlying, cfg.allowed, cfg.minDonation);
        }

        vm.stopBroadcast();
    }
}
