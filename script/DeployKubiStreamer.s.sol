// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/KubiStreamerDonation.sol";

contract DeployKubiStreamer is Script {
    function run() external {
        // --- isi lewat .env agar gampang pindah jaringan ---
        address router = vm.envOr("KUBI_ROUTER", address(0));                 // contoh Mantle: 0x2bF7E65df939482869b96A6BEb88d3e5bF58Fb81
        address superAdmin = vm.envOr("KUBI_SUPER_ADMIN", address(0));        // wallet super admin
        uint16 feeBps = uint16(vm.envOr("KUBI_FEE_BPS", uint256(250)));       // default 2.5%
        address feeRecipient = vm.envOr("KUBI_FEE_RECIPIENT", address(0));    // wallet penerima fee
        require(router != address(0) && superAdmin != address(0) && feeRecipient != address(0), "Deploy: config zero");
        // ----------------------------------------------------

        address[] memory whitelistTokens = new address[](11);
        whitelistTokens[0] = vm.parseAddress("0x57b78b98b9dd06e06de145b83aedf6f04e4c5500"); // WETHkb
        whitelistTokens[1] = vm.parseAddress("0x1fe9a4e25caa2a22fc0b61010fdb0db462fb5b29"); // USDCkb
        whitelistTokens[2] = vm.parseAddress("0x5e1e8043381f3a21a1a64f46073daf7e74fedc1e"); // USDTkb
        whitelistTokens[3] = vm.parseAddress("0x06c1e044d5beb614faa6128001f519e6c693a044"); // IDRXkb
        whitelistTokens[4] = vm.parseAddress("0x85b8dc34c7af35bac8a45cff53353f39e6f732a2"); // CBBTCkb
        whitelistTokens[5] = vm.parseAddress("0x7392e9e58f202da3877776c41683ac457dfd4cd7"); // ETHkb
        whitelistTokens[6] = vm.parseAddress("0xb03a4cf6eb030bbabd0452300b01c7dcb9584737"); // ZORAkb
        whitelistTokens[7] = vm.parseAddress("0x2ffc2f655a26a4def63efcd59930d1241ee0519a"); // AAVEkb
        whitelistTokens[8] = vm.parseAddress("0x14ac27f376b03b6c05f2189c4f03febb5d76432a"); // NOICEkb
        whitelistTokens[9] = vm.parseAddress("0xdac9107491b3c59a97d7f45cefc97353f6ab46b2"); // EGGSkb
        whitelistTokens[10] = vm.parseAddress("0x9b94108165ef58c9736f2c34b09e3b5b62cf5218"); // AEROkb

        address[] memory yieldContracts = new address[](20);
        address[] memory underlyingTokens = new address[](20);
        bool[] memory allowedStatuses = new bool[](20);
        uint256[] memory minDonations = new uint256[](20);

        address[] memory poolTokenA = new address[](2);
        address[] memory poolTokenB = new address[](2);
        uint24[] memory poolFees = new uint24[](2);
        poolTokenA[0] = whitelistTokens[0]; // WETHkb
        poolTokenB[0] = whitelistTokens[1]; // USDCkb
        poolFees[0] = 3_000;
        poolTokenA[1] = whitelistTokens[0]; // WETHkb
        poolTokenB[1] = whitelistTokens[2]; // USDTkb
        poolFees[1] = 3_000;

        yieldContracts[0] = vm.parseAddress("0xAee2A87701aFEF956473d547bD02cD736729D8a7");
        underlyingTokens[0] = vm.parseAddress("0x1fE9A4E25cAA2a22FC0B61010fDB0DB462FB5b29");
        allowedStatuses[0] = true;
        minDonations[0] = 0;

        yieldContracts[1] = vm.parseAddress("0x6aaBE7258f09474e62E8BebB1cf90E15fbAAF777");
        underlyingTokens[1] = vm.parseAddress("0x5e1E8043381F3A21a1A64f46073daF7E74fEdC1E");
        allowedStatuses[1] = true;
        minDonations[1] = 0;

        yieldContracts[2] = vm.parseAddress("0x5C70fB2a739e9e7Ad5c4311ABF99E0fB65c07eE9");
        underlyingTokens[2] = vm.parseAddress("0x06C1e044D5BEb614faA6128001F519e6c693a044");
        allowedStatuses[2] = true;
        minDonations[2] = 0;

        yieldContracts[3] = vm.parseAddress("0xbB6Dd87f1fe0483d9FFA90f7A163Caf21F40BA6c");
        underlyingTokens[3] = vm.parseAddress("0x85B8Dc34C7Af35baC8a45CfF53353f39E6F732A2");
        allowedStatuses[3] = true;
        minDonations[3] = 0;

        yieldContracts[4] = vm.parseAddress("0xcE74630446990AcF6Cd56facBbd6EE908eE55562");
        underlyingTokens[4] = vm.parseAddress("0x7392e9E58f202Da3877776c41683AC457DFd4CD7");
        allowedStatuses[4] = true;
        minDonations[4] = 0;

        yieldContracts[5] = vm.parseAddress("0xdCC41dee829C1246a936dC5E801cB24303445651");
        underlyingTokens[5] = vm.parseAddress("0x1fE9A4E25cAA2a22FC0B61010fDB0DB462FB5b29");
        allowedStatuses[5] = true;
        minDonations[5] = 0;

        yieldContracts[6] = vm.parseAddress("0x8f5816ca88ED2775305b154625744E36943Cc750");
        underlyingTokens[6] = vm.parseAddress("0x5e1E8043381F3A21a1A64f46073daF7E74fEdC1E");
        allowedStatuses[6] = true;
        minDonations[6] = 0;

        yieldContracts[7] = vm.parseAddress("0x2BB55f68fb05De13B04e5a2cadbAE5A05bCE277B");
        underlyingTokens[7] = vm.parseAddress("0x06C1e044D5BEb614faA6128001F519e6c693a044");
        allowedStatuses[7] = true;
        minDonations[7] = 0;

        yieldContracts[8] = vm.parseAddress("0xa022FD1966577144fCb5Ed8aD5a134861aE5e138");
        underlyingTokens[8] = vm.parseAddress("0x85B8Dc34C7Af35baC8a45CfF53353f39E6F732A2");
        allowedStatuses[8] = true;
        minDonations[8] = 0;

        yieldContracts[9] = vm.parseAddress("0xEC4c46F46191d77C3D8Ba3ddFafe71b58E2089Af");
        underlyingTokens[9] = vm.parseAddress("0x7392e9E58f202Da3877776c41683AC457DFd4CD7");
        allowedStatuses[9] = true;
        minDonations[9] = 0;

        yieldContracts[10] = vm.parseAddress("0xE47Eba0dBf716D99482Fb071ca04aDf4FCCd6b1f");
        underlyingTokens[10] = vm.parseAddress("0x1fE9A4E25cAA2a22FC0B61010fDB0DB462FB5b29");
        allowedStatuses[10] = true;
        minDonations[10] = 0;

        yieldContracts[11] = vm.parseAddress("0x4E3A466BbA553Ace4Cd3a6149d574F3f034b5269");
        underlyingTokens[11] = vm.parseAddress("0x5e1E8043381F3A21a1A64f46073daF7E74fEdC1E");
        allowedStatuses[11] = true;
        minDonations[11] = 0;

        yieldContracts[12] = vm.parseAddress("0x751A0E0147d10b8C21804AC88DCfa6837312ea35");
        underlyingTokens[12] = vm.parseAddress("0x06C1e044D5BEb614faA6128001F519e6c693a044");
        allowedStatuses[12] = true;
        minDonations[12] = 0;

        yieldContracts[13] = vm.parseAddress("0xD8D362BADb84Cc1F97a00273ddC8845FD4148C80");
        underlyingTokens[13] = vm.parseAddress("0x85B8Dc34C7Af35baC8a45CfF53353f39E6F732A2");
        allowedStatuses[13] = true;
        minDonations[13] = 0;

        yieldContracts[14] = vm.parseAddress("0x1061473A78f6eb0a0BcBDE060a5EeA9d4273BB59");
        underlyingTokens[14] = vm.parseAddress("0x7392e9E58f202Da3877776c41683AC457DFd4CD7");
        allowedStatuses[14] = true;
        minDonations[14] = 0;

        yieldContracts[15] = vm.parseAddress("0x824FB936D24B2BAaF92Fe87FD65fF22d01439ECE");
        underlyingTokens[15] = vm.parseAddress("0x1fE9A4E25cAA2a22FC0B61010fDB0DB462FB5b29");
        allowedStatuses[15] = true;
        minDonations[15] = 0;

        yieldContracts[16] = vm.parseAddress("0x012bd7CD0AcC8cB696306B1aB7a537E85eF2056f");
        underlyingTokens[16] = vm.parseAddress("0x5e1E8043381F3A21a1A64f46073daF7E74fEdC1E");
        allowedStatuses[16] = true;
        minDonations[16] = 0;

        yieldContracts[17] = vm.parseAddress("0x4d8346F2F33FFBc7fa2E46bECF83C978943e69C8");
        underlyingTokens[17] = vm.parseAddress("0x06C1e044D5BEb614faA6128001F519e6c693a044");
        allowedStatuses[17] = true;
        minDonations[17] = 0;

        yieldContracts[18] = vm.parseAddress("0x2db087D43Fc8402aDE0706807d32d6EF72411ebd");
        underlyingTokens[18] = vm.parseAddress("0x85B8Dc34C7Af35baC8a45CfF53353f39E6F732A2");
        allowedStatuses[18] = true;
        minDonations[18] = 0;

        yieldContracts[19] = vm.parseAddress("0xD14bD87b18dA3Ec84a9e098DF1c808d9cb7a9852");
        underlyingTokens[19] = vm.parseAddress("0x7392e9E58f202Da3877776c41683AC457DFd4CD7");
        allowedStatuses[19] = true;
        minDonations[19] = 0;

        vm.startBroadcast();
        KubiStreamerDonation donation = new KubiStreamerDonation(router, superAdmin, feeBps, feeRecipient);
        for (uint256 i = 0; i < whitelistTokens.length; ++i) {
            donation.setGlobalWhitelist(whitelistTokens[i], true);
        }
        for (uint256 k = 0; k < poolTokenA.length; ++k) {
            donation.setPoolFee(poolTokenA[k], poolTokenB[k], poolFees[k]);
        }
        for (uint256 j = 0; j < yieldContracts.length; ++j) {
            donation.setYieldConfig(yieldContracts[j], underlyingTokens[j], allowedStatuses[j], minDonations[j]);
        }
        vm.stopBroadcast();
    }
}
