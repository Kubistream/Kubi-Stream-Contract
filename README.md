# 🎥 Kubi Streamer — Seamless Crypto Donation Platform

**Kubi Streamer** adalah smart contract platform donasi untuk streamer yang menerima dukungan (gift) menggunakan crypto, dengan sistem fee otomatis, auto-swap token, dan hasil donasi langsung dikirim ke wallet streamer (tanpa perantara).

---

## ✨ Fitur Utama

- 💸 **Donasi Langsung ke Streamer**
  Donatur mengirim token langsung ke smart contract, lalu otomatis dipotong fee platform dan dikirim ke wallet streamer.

- 🔄 **Auto-Swap via Uniswap V2 Router**
  Jika token donasi berbeda dengan token utama streamer (primary token), kontrak otomatis melakukan swap melalui router V2.

- 🧾 **Fee Platform Fleksibel**
  Super admin atau owner dapat mengatur besar fee (`feeBps`) dan penerima fee (`feeRecipient`).

- 🧱 **Sistem Whitelist Multi-Level**
  - **Global whitelist** (token-token yang disetujui oleh super admin)
  - **Streamer whitelist** (subset token global yang diterima streamer)
  - **Primary token** (token utama streamer untuk auto-swap)

- ⚡ **Gas Efficient**
  Menggunakan custom error & struktur modular untuk efisiensi gas maksimum.

- 🧠 **Event-Based Integration**
  Mengirim event realtime untuk sinkronisasi backend:
  ```solidity
  event Donation(address indexed donor, address indexed streamer, address token, uint256 amount, uint256 fee, string message);
  event GlobalWhitelistUpdated(address indexed token, bool allowed);
  event StreamerWhitelistUpdated(address indexed streamer, address indexed token, bool allowed);
  ```

---

## 🧩 Struktur Kontrak

```
contracts/
├── errors/
│   └── Errors.sol
├── interfaces/
│   ├── IERC20.sol
│   ├── IUniswapV2Factory.sol
│   └── IUniswapV2Router02.sol
├── libraries/
│   └── SafeERC20.sol
├── utils/
│   ├── Ownable.sol
│   └── ReentrancyGuard.sol
└── KubiStreamerDonation.sol      <-- Kontrak utama
```

---

## 🧠 Alur Donasi

```
Donatur
   ↓ (donate(token, amount, streamer))
Smart Contract (KubiStreamerDonation)
   ↓
Potong Fee → feeRecipient
   ↓
Kirim ke Streamer (langsung / auto-swap)
   ↓
Emit Event → Backend Listener (WebSocket)
```

---

## ⚙️ Deployment

### 🧾 Konfigurasi

Edit file `script/DeployKubiStreamer.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/KubiStreamerDonation.sol";

contract DeployKubiStreamer is Script {
    function run() external {
        // --- ubah sesuai kebutuhanmu ---
        address router = 0x...;         // UniswapV2Router02 address
        address superAdmin = 0x...;     // wallet super admin
        uint16 feeBps = 250;            // 2.5%
        address feeRecipient = 0x...;   // wallet penerima fee
        // -------------------------------

        vm.startBroadcast();
        new KubiStreamerDonation(router, superAdmin, feeBps, feeRecipient);
        vm.stopBroadcast();
    }
}
```

Lalu jalankan:
```bash
forge script script/DeployKubiStreamer.s.sol \
  --rpc-url https://base-sepolia.g.alchemy.com/v2/YOUR_KEY \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

## 🧠 Cara Mengatur Whitelist

### Tambah token global:
```solidity
setGlobalWhitelist(0xUSDC, true);
```

### Tambah token streamer:
```solidity
setStreamerWhitelist(streamerAddress, 0xUSDC, true);
```

### Set primary token streamer:
```solidity
setPrimaryToken(streamerAddress, 0xUSDC);
```

### Update fee:
```solidity
setFeeConfig(300, 0xNewFeeWallet);
```

---

## 🧩 Integrasi Backend (Realtime Sync)

Backend bisa mendengarkan event whitelist via WebSocket:

```js
import { ethers } from "ethers";

const provider = new ethers.WebSocketProvider("wss://base-sepolia.g.alchemy.com/v2/YOUR_KEY");
const contract = new ethers.Contract("0xKubiStreamerAddress", abi, provider);

contract.on("GlobalWhitelistUpdated", (token, allowed, event) => {
  console.log("Global token changed:", token, allowed);
  // kirim ke backend Laravel
});

contract.on("StreamerWhitelistUpdated", (streamer, token, allowed, event) => {
  console.log("Streamer whitelist updated:", streamer, token, allowed);
});

contract.on("Donation", async (donor, streamer, token, amount, fee, message, event) => {
  console.log(`Donation received from ${donor} to ${streamer}:`, {
    token,
    amount: amount.toString(),
    fee: fee.toString(),
    message,
    tx: event.transactionHash,
  });

  // kirim ke backend Laravel untuk disimpan di database
  await fetch("https://your-backend/api/donation", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      donor,
      streamer,
      token,
      amount: amount.toString(),
      fee: fee.toString(),
      message,
      tx_hash: event.transactionHash,
      block_number: event.blockNumber,
    }),
  });
});
```

---

## 🧪 Testing

Unit test menggunakan Foundry:
```bash
forge test -vv
```

Tersedia 4 skenario:
1. Donasi ERC20 langsung (whitelisted)
2. Donasi ERC20 auto-swap
3. Donasi ETH langsung
4. Donasi ETH auto-swap

---

## 🧱 License

MIT © 2025 — Kubi Streamer Project  
Developed with ❤️ using [Foundry](https://book.getfoundry.sh/) & Solidity 0.8.x
