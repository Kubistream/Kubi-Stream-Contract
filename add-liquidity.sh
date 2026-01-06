#!/bin/bash

# =============================================================================
# Add Liquidity to MockSwapRouter
# =============================================================================
# Script ini akan deposit semua token ke MockSwapRouter untuk testing swap
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Contract Addresses
MOCK_ROUTER="0xc8F83c65d3f2987C2aC3aBC7650F47AF8093bA80"
RPC_URL="https://rpc.sepolia.mantle.xyz"

# Token Addresses
declare -A TOKENS
TOKENS["MNT"]="0x33c6f26dA09502E6540043f030aE1F87f109cc99"
TOKENS["ETH"]="0x7CB382Ce1AA40FA9F9A59a632090c05Dc28caE7b"
TOKENS["USDC"]="0xB288Ba5B5b80Dd0Fd83541ef2e5922f71121Fa13"
TOKENS["USDT"]="0xC4a53c466Cfb62AecED03008B0162baaf36E0B03"
TOKENS["PUFF"]="0x70Db6eFB75c898Ad1e194FDA2B8C6e73dbC944d6"
TOKENS["AXL"]="0xEE589FBF85128abA6f42696dB2F28eA9EBddE173"
TOKENS["SVL"]="0x2C036be74942c597e4d81D7050008dDc11becCEb"
TOKENS["LINK"]="0x90CdcBF4c4bc78dC440252211EFd744d0A4Dc4A1"
TOKENS["WBTC"]="0xced6Ceb47301F268d57fF07879DF45Fda80e6974"
TOKENS["PENDLE"]="0x782Ba48189AF93a0CF42766058DE83291f384bF3"

# Deposit amount (500 tokens with 18 decimals)
DEPOSIT_AMOUNT="500000000000000000000"
APPROVE_AMOUNT="1000000000000000000000"

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set!${NC}"
    echo "Run: source .env"
    exit 1
fi

echo -e "${GREEN}=== Adding Liquidity to MockSwapRouter ===${NC}"
echo -e "Router: ${YELLOW}$MOCK_ROUTER${NC}"
echo ""

# Function to deposit token
deposit_token() {
    local name=$1
    local address=$2
    
    echo -e "${YELLOW}[$name]${NC} Processing..."
    
    # Approve
    echo "  Approving..."
    cast send $address \
        "approve(address,uint256)" \
        $MOCK_ROUTER \
        $APPROVE_AMOUNT \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY \
        --legacy \
        --quiet 2>/dev/null || {
            echo -e "  ${RED}Approve failed (mungkin balance 0)${NC}"
            return 1
        }
    
    # Deposit
    echo "  Depositing 500 tokens..."
    cast send $MOCK_ROUTER \
        "depositToken(address,uint256)" \
        $address \
        $DEPOSIT_AMOUNT \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY \
        --legacy \
        --quiet 2>/dev/null || {
            echo -e "  ${RED}Deposit failed (mungkin balance tidak cukup)${NC}"
            return 1
        }
    
    echo -e "  ${GREEN}✓ Done${NC}"
}

# Deposit all tokens
for token in "${!TOKENS[@]}"; do
    deposit_token "$token" "${TOKENS[$token]}" || true
    echo ""
done

echo -e "${GREEN}=== Liquidity Added ===${NC}"
echo ""

# Check balances
echo -e "${YELLOW}Checking MockSwapRouter balances:${NC}"
for token in "${!TOKENS[@]}"; do
    balance=$(cast call $MOCK_ROUTER "tokenBalance(address)(uint256)" "${TOKENS[$token]}" --rpc-url $RPC_URL 2>/dev/null || echo "0")
    if [ "$balance" != "0" ]; then
        echo -e "  $token: ${GREEN}$balance${NC}"
    else
        echo -e "  $token: ${RED}0${NC}"
    fi
done

echo ""
echo -e "${GREEN}Done!${NC}"
