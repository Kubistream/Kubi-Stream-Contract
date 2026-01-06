# Setup MockSwapRouter untuk Testing

Panduan langkah-langkah untuk deploy dan configure MockSwapRouter di Mantle Sepolia.

---

## Deployed Contracts

| Contract | Chain | Address |
|----------|-------|---------|
| KubiStreamerDonation | Base Sepolia | `0x4AB4a2290cB651065D346299425b2D45eEf9D75D` |
| KubiStreamerDonation | Mantle Sepolia | `0xDb26Ba8581979dc4E11218735F821Af5171fb737` |
| MockSwapRouter | Mantle Sepolia | `0xc8F83c65d3f2987C2aC3aBC7650F47AF8093bA80` |

---

## Prerequisites

```bash
cd Kubi-Stream-Contract
source .env
```

Pastikan `PRIVATE_KEY` sudah di-set di `.env`.

> **Note:** Project sudah memiliki copy lokal OpenZeppelin contracts di `contracts/utils/` dan `contracts/interfaces/`. Tidak perlu install tambahan.

---

## Step 1: Deploy MockSwapRouter (Jika Belum Deploy)

```bash
forge script script/DeployMockSwapRouter.s.sol \
  --rpc-url https://rpc.sepolia.mantle.xyz \
  --private-key $PRIVATE_KEY \
  --broadcast -vvv
```

---

## Step 2: Set Environment Variables

```bash
export MOCK_ROUTER=0xc8F83c65d3f2987C2aC3aBC7650F47AF8093bA80
export KUBI_MANTLE=0xDb26Ba8581979dc4E11218735F821Af5171fb737
export KUBI_BASE=0x4AB4a2290cB651065D346299425b2D45eEf9D75D
```

---

## Step 3: Deposit Token untuk Swap Output

MockSwapRouter perlu memiliki token yang akan di-output saat swap.

**Deposit ETH token (untuk swap AXL → ETH):**

```bash
# Approve ETH token ke MockSwapRouter
cast send 0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b \
  "approve(address,uint256)" \
  $MOCK_ROUTER \
  1000000000000000000000 \
  --rpc-url https://rpc.sepolia.mantle.xyz \
  --private-key $PRIVATE_KEY --legacy

# Deposit 500 ETH token ke MockSwapRouter
cast send $MOCK_ROUTER \
  "depositToken(address,uint256)" \
  0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b \
  500000000000000000000 \
  --rpc-url https://rpc.sepolia.mantle.xyz \
  --private-key $PRIVATE_KEY --legacy
```

**Deposit token lain sesuai kebutuhan:**

```bash
# Deposit USDC untuk swap ke USDC
cast send 0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13 \
  "approve(address,uint256)" \
  $MOCK_ROUTER \
  1000000000000000000000 \
  --rpc-url https://rpc.sepolia.mantle.xyz \
  --private-key $PRIVATE_KEY --legacy

cast send $MOCK_ROUTER \
  "depositToken(address,uint256)" \
  0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13 \
  500000000000000000000 \
  --rpc-url https://rpc.sepolia.mantle.xyz \
  --private-key $PRIVATE_KEY --legacy
```

---

## Step 4: Verify Setup

**Cek router di KubiStreamer Mantle:**

```bash
cast call $KUBI_MANTLE \
  "router()(address)" \
  --rpc-url https://rpc.sepolia.mantle.xyz
```

> Harus return `0xc8F83c65d3f2987C2aC3aBC7650F47AF8093bA80`

**Cek balance token di MockSwapRouter:**

```bash
cast call $MOCK_ROUTER \
  "tokenBalance(address)(uint256)" \
  0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b \
  --rpc-url https://rpc.sepolia.mantle.xyz
```

> Harus return balance > 0

---

## Step 5: Test Cross-Chain Donation dengan Swap

1. Buka `kubi-tester` di browser
2. Connect ke **Base Sepolia**
3. Donate token (misal: AXL) ke streamer yang punya primary token = ETH
4. Tunggu bridging selesai
5. Cek balance streamer di Mantle → harus dapat ETH token

---

## Troubleshooting

### Error: SwapNotEnabled

```bash
# Enable swap pair manual
cast send $MOCK_ROUTER \
  "setSwapEnabled(address,address,bool)" \
  <TOKEN_A> \
  <TOKEN_B> \
  true \
  --rpc-url https://rpc.sepolia.mantle.xyz \
  --private-key $PRIVATE_KEY --legacy
```

### Error: Not enough output token

Deposit lebih banyak token ke MockSwapRouter (Step 3).

### Update Swap Router (jika perlu ganti router)

```bash
cast send $KUBI_MANTLE \
  "setSwapRouter(address)" \
  <NEW_ROUTER_ADDRESS> \
  --rpc-url https://rpc.sepolia.mantle.xyz \
  --private-key $PRIVATE_KEY --legacy
```

---

## Token Addresses Reference

| Token | Address |
|-------|---------|
| MNT | `0x33c6f26dA09502E6540043f030aE1F87f109cc99` |
| ETH | `0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b` |
| USDC | `0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13` |
| USDT | `0xC4a53c466Cfb62AecED03008B0162baaf36E0B03` |
| PUFF | `0x70Db6eFB75c898Ad1e194FDA2B8C6e73dbC944d6` |
| AXL | `0xEE589FBF85128abA6f42696dB2F28eA9EBddE173` |
| SVL | `0x2C036be74942c597e4d81D7050008dDc11becCEb` |
| LINK | `0x90CdcBF4c4bc78dC440252211EFd744d0A4Dc4A1` |
| WBTC | `0xced6Ceb47301F268d57fF07879DF45Fda80e6974` |
| PENDLE | `0x782Ba48189AF93a0CF42766058DE83291f384bF3` |
