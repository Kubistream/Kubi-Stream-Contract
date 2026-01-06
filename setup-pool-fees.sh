#!/bin/bash

# =============================================================================
# Setup Pool Fees untuk KubiStreamer
# =============================================================================
# Script ini akan set pool fees untuk semua token pairs di KubiStreamer
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Contract Addresses
KUBI_MANTLE="0xDb26Ba8581979dc4E11218735F821Af5171fb737"
RPC_URL="https://rpc.sepolia.mantle.xyz"

# Token Addresses
MNT="0x33c6f26dA09502E6540043f030aE1F87f109cc99"
ETH="0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b"
USDC="0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13"
USDT="0xC4a53c466Cfb62AecED03008B0162baaf36E0B03"
PUFF="0x70Db6eFB75c898Ad1e194FDA2B8C6e73dbC944d6"
AXL="0xEE589FBF85128abA6f42696dB2F28eA9EBddE173"
SVL="0x2C036be74942c597e4d81D7050008dDc11becCEb"
LINK="0x90CdcBF4c4bc78dC440252211EFd744d0A4Dc4A1"
WBTC="0xced6Ceb47301F268d57fF07879DF45Fda80e6974"
PENDLE="0x782Ba48189AF93a0CF42766058DE83291f384bF3"

# Pool Fee (3000 = 0.3%)
POOL_FEE=3000

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set!${NC}"
    echo "Run: export PRIVATE_KEY=0x..."
    exit 1
fi

echo -e "${GREEN}=== Setting Pool Fees for KubiStreamer ===${NC}"
echo -e "Contract: ${YELLOW}$KUBI_MANTLE${NC}"
echo -e "Pool Fee: ${YELLOW}$POOL_FEE (0.3%)${NC}"
echo ""

# All tokens array
TOKENS=("$MNT" "$ETH" "$USDC" "$USDT" "$PUFF" "$AXL" "$SVL" "$LINK" "$WBTC" "$PENDLE")
TOKEN_NAMES=("MNT" "ETH" "USDC" "USDT" "PUFF" "AXL" "SVL" "LINK" "WBTC" "PENDLE")

# Set pool fees for all pairs
count=0
total=$(( ${#TOKENS[@]} * (${#TOKENS[@]} - 1) / 2 ))

for i in "${!TOKENS[@]}"; do
    for j in "${!TOKENS[@]}"; do
        if [ $j -gt $i ]; then
            count=$((count + 1))
            echo -e "${YELLOW}[$count/$total]${NC} Setting ${TOKEN_NAMES[$i]} <-> ${TOKEN_NAMES[$j]}..."
            
            cast send $KUBI_MANTLE \
                "setPoolFee(address,address,uint24)" \
                "${TOKENS[$i]}" \
                "${TOKENS[$j]}" \
                $POOL_FEE \
                --rpc-url $RPC_URL \
                --private-key $PRIVATE_KEY \
                --legacy \
                --quiet 2>/dev/null && echo -e "  ${GREEN}✓${NC}" || echo -e "  ${RED}✗ Failed${NC}"
        fi
    done
done

echo ""
echo -e "${GREEN}=== Pool Fees Setup Complete ===${NC}"
echo ""
echo -e "${YELLOW}Verifying a sample pair (AXL <-> ETH):${NC}"
cast call $KUBI_MANTLE \
    "poolFees(address,address)(uint24)" \
    $AXL $ETH \
    --rpc-url $RPC_URL 2>/dev/null || echo "Could not verify"

echo ""
echo -e "${GREEN}Done!${NC}"
