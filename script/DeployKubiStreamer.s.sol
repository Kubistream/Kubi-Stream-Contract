// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/KubiStreamerDonation.sol";

contract DeployKubiStreamer is Script {
    function run() external {
        // --- ubah sesuai kebutuhanmu ---
        address router = 0x1689E7B1F10000AE47eBfE339a4f69dECd19F602;         // UniswapV2Router02 address
        address superAdmin = 0x1234b50310fF79958509d1a9C8a92458ED1496D1;     // wallet super admin
        uint16 feeBps = 250;            // 2.5%
        address feeRecipient = 0x123454Ce54DEBE2cEbCe95740E9e0f65DFf9DBE2;   // wallet penerima fee
        // -------------------------------

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

        vm.startBroadcast();
        KubiStreamerDonation donation = new KubiStreamerDonation(router, superAdmin, feeBps, feeRecipient);
        for (uint256 i = 0; i < whitelistTokens.length; ++i) {
            donation.setGlobalWhitelist(whitelistTokens[i], true);
        }
        vm.stopBroadcast();
    }
}
