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

        vm.startBroadcast();
        new KubiStreamerDonation(router, superAdmin, feeBps, feeRecipient);
        vm.stopBroadcast();
    }
}
