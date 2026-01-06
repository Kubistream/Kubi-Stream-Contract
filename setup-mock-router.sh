#!/bin/bash

# =============================================================================
# Setup MockSwapRouter - Complete Setup Script
# =============================================================================
# Script ini akan:
# 1. Setup pool fees di KubiStreamer
# 2. Mint tokens untuk liquidity
# 3. Deposit tokens ke MockSwapRouter
# 4. Set exchange rates (harga realistis)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# CONTRACT ADDRESSES - UPDATE SESUAI KEBUTUHAN
# =============================================================================
KUBI_MANTLE="0xDb26Ba8581979dc4E11218735F821Af5171fb737"
MOCK_ROUTER="0x493Be13415bf36D997f40Aac50C264d855c7f869"
RPC_URL="https://mantle-sepolia.g.alchemy.com/v2/kavdD0d3AcCK-APKJhHkW"

# =============================================================================
# TOKEN ADDRESSES
# =============================================================================
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

# Token arrays
TOKENS=("$MNT" "$ETH" "$USDC" "$USDT" "$PUFF" "$AXL" "$SVL" "$LINK" "$WBTC" "$PENDLE")
TOKEN_NAMES=("MNT" "ETH" "USDC" "USDT" "PUFF" "AXL" "SVL" "LINK" "WBTC" "PENDLE")

# =============================================================================
# EXCHANGE RATES (basis points, 10000 = 1:1)
# Semua rates relatif ke ETH sebagai base
# Contoh: AXL_RATE=500 berarti 1 AXL = 0.05 ETH
# =============================================================================
declare -A TOKEN_RATES_TO_ETH
TOKEN_RATES_TO_ETH["MNT"]=300       # 1 MNT = 0.03 ETH
TOKEN_RATES_TO_ETH["ETH"]=10000     # 1 ETH = 1 ETH
TOKEN_RATES_TO_ETH["USDC"]=4        # 1 USDC = 0.0004 ETH (~$1 jika ETH=$2500)
TOKEN_RATES_TO_ETH["USDT"]=4        # 1 USDT = 0.0004 ETH
TOKEN_RATES_TO_ETH["PUFF"]=1        # 1 PUFF = 0.0001 ETH (meme token)
TOKEN_RATES_TO_ETH["AXL"]=3         # 1 AXL = 0.0003 ETH (~$0.75)
TOKEN_RATES_TO_ETH["SVL"]=2         # 1 SVL = 0.0002 ETH
TOKEN_RATES_TO_ETH["LINK"]=56       # 1 LINK = 0.0056 ETH (~$14)
TOKEN_RATES_TO_ETH["WBTC"]=160000   # 1 WBTC = 16 ETH (~$40k)
TOKEN_RATES_TO_ETH["PENDLE"]=20     # 1 PENDLE = 0.002 ETH (~$5)

# =============================================================================
# CONFIGURATION
# =============================================================================
POOL_FEE=3000                           # 0.3%
MINT_AMOUNT="100000000000000000000000000000000000000000000"  # Large amount
DEPOSIT_AMOUNT="100000000000000000000000000000000000000000000" # Large amount
MAX_RETRIES=3                           # Retry 3 times on failure
RETRY_DELAY=2                           # Wait 2 seconds between retries

# =============================================================================
# RETRY FUNCTION
# =============================================================================
retry_command() {
    local cmd="$1"
    local description="$2"
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if eval "$cmd" 2>/dev/null; then
            return 0
        fi
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            sleep $RETRY_DELAY
        fi
    done
    return 1
}

# =============================================================================
# CHECK PREREQUISITES
# =============================================================================
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set!${NC}"
    echo "Run: export PRIVATE_KEY=0x..."
    exit 1
fi

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        SETUP MOCK SWAP ROUTER - COMPLETE SETUP                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "KubiStreamer: ${YELLOW}$KUBI_MANTLE${NC}"
echo -e "MockRouter:   ${YELLOW}$MOCK_ROUTER${NC}"
echo -e "Max Retries:  ${YELLOW}$MAX_RETRIES${NC}"
echo ""

# =============================================================================
# STEP 1: SETUP POOL FEES
# =============================================================================
setup_pool_fees() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  STEP 1: Setting Pool Fees (${POOL_FEE} = 0.3%)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    count=0
    success=0
    failed=0
    total=$(( ${#TOKENS[@]} * (${#TOKENS[@]} - 1) / 2 ))
    
    for i in "${!TOKENS[@]}"; do
        for j in "${!TOKENS[@]}"; do
            if [ $j -gt $i ]; then
                count=$((count + 1))
                echo -ne "  [${count}/${total}] ${TOKEN_NAMES[$i]} <-> ${TOKEN_NAMES[$j]}... "
                
                cmd="cast send $KUBI_MANTLE 'setPoolFee(address,address,uint24)' '${TOKENS[$i]}' '${TOKENS[$j]}' $POOL_FEE --rpc-url $RPC_URL --private-key \$PRIVATE_KEY --legacy --quiet"
                
                if retry_command "$cmd" "${TOKEN_NAMES[$i]} <-> ${TOKEN_NAMES[$j]}"; then
                    echo -e "${GREEN}✓${NC}"
                    success=$((success + 1))
                else
                    echo -e "${RED}✗ (failed after $MAX_RETRIES retries)${NC}"
                    failed=$((failed + 1))
                fi
            fi
        done
    done
    echo -e "  ${GREEN}Success: $success${NC} | ${RED}Failed: $failed${NC}"
    echo ""
}

# =============================================================================
# STEP 2: MINT TOKENS
# =============================================================================
mint_tokens() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  STEP 2: Minting Tokens${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    WALLET=$(cast wallet address --private-key $PRIVATE_KEY 2>/dev/null)
    success=0
    failed=0
    
    for i in "${!TOKENS[@]}"; do
        echo -ne "  ${TOKEN_NAMES[$i]}... "
        
        # Try mint with retry
        cmd="cast send '${TOKENS[$i]}' 'mint(address,uint256)' '$WALLET' '$MINT_AMOUNT' --rpc-url $RPC_URL --private-key \$PRIVATE_KEY --legacy --quiet"
        
        if retry_command "$cmd" "mint ${TOKEN_NAMES[$i]}"; then
            echo -e "${GREEN}✓${NC}"
            success=$((success + 1))
        else
            # Try faucet as fallback
            cmd_faucet="cast send '${TOKENS[$i]}' 'faucet(uint256)' '$MINT_AMOUNT' --rpc-url $RPC_URL --private-key \$PRIVATE_KEY --legacy --quiet"
            if retry_command "$cmd_faucet" "faucet ${TOKEN_NAMES[$i]}"; then
                echo -e "${GREEN}✓ (faucet)${NC}"
                success=$((success + 1))
            else
                echo -e "${YELLOW}⊘ skipped${NC}"
                failed=$((failed + 1))
            fi
        fi
    done
    echo -e "  ${GREEN}Success: $success${NC} | ${YELLOW}Skipped: $failed${NC}"
    echo ""
}

# =============================================================================
# STEP 3: DEPOSIT LIQUIDITY TO ROUTER
# =============================================================================
deposit_liquidity() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  STEP 3: Depositing Liquidity${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    success=0
    failed=0
    
    for i in "${!TOKENS[@]}"; do
        echo -ne "  ${TOKEN_NAMES[$i]}... "
        
        # Approve with retry
        cmd_approve="cast send '${TOKENS[$i]}' 'approve(address,uint256)' '$MOCK_ROUTER' '$DEPOSIT_AMOUNT' --rpc-url $RPC_URL --private-key \$PRIVATE_KEY --legacy --quiet"
        retry_command "$cmd_approve" "approve ${TOKEN_NAMES[$i]}" || true
        
        # Deposit with retry
        cmd_deposit="cast send '$MOCK_ROUTER' 'depositToken(address,uint256)' '${TOKENS[$i]}' '$DEPOSIT_AMOUNT' --rpc-url $RPC_URL --private-key \$PRIVATE_KEY --legacy --quiet"
        
        if retry_command "$cmd_deposit" "deposit ${TOKEN_NAMES[$i]}"; then
            echo -e "${GREEN}✓${NC}"
            success=$((success + 1))
        else
            echo -e "${RED}✗ (failed after $MAX_RETRIES retries)${NC}"
            failed=$((failed + 1))
        fi
    done
    echo -e "  ${GREEN}Success: $success${NC} | ${RED}Failed: $failed${NC}"
    echo ""
}

# =============================================================================
# STEP 4: SET EXCHANGE RATES
# =============================================================================
set_exchange_rates() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  STEP 4: Setting Exchange Rates${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    success=0
    failed=0
    total=$(( ${#TOKEN_NAMES[@]} * (${#TOKEN_NAMES[@]} - 1) ))
    count=0
    
    for i in "${!TOKEN_NAMES[@]}"; do
        for j in "${!TOKEN_NAMES[@]}"; do
            if [ $i -ne $j ]; then
                count=$((count + 1))
                name_i="${TOKEN_NAMES[$i]}"
                name_j="${TOKEN_NAMES[$j]}"
                
                rate_i=${TOKEN_RATES_TO_ETH[$name_i]}
                rate_j=${TOKEN_RATES_TO_ETH[$name_j]}
                
                # Calculate cross rate
                if [ $rate_j -gt 0 ]; then
                    cross_rate=$(( (rate_i * 10000) / rate_j ))
                else
                    cross_rate=10000
                fi
                
                echo -ne "  [${count}/${total}] ${name_i} -> ${name_j} (rate: ${cross_rate})... "
                
                cmd="cast send '$MOCK_ROUTER' 'setExchangeRate(address,address,uint256)' '${TOKENS[$i]}' '${TOKENS[$j]}' $cross_rate --rpc-url $RPC_URL --private-key \$PRIVATE_KEY --legacy --quiet"
                
                if retry_command "$cmd" "${name_i} -> ${name_j}"; then
                    echo -e "${GREEN}✓${NC}"
                    success=$((success + 1))
                else
                    echo -e "${RED}✗${NC}"
                    failed=$((failed + 1))
                fi
            fi
        done
    done
    echo -e "  ${GREEN}Success: $success${NC} | ${RED}Failed: $failed${NC}"
    echo ""
}

# =============================================================================
# STEP 5: VERIFY SETUP
# =============================================================================
verify_setup() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  STEP 5: Verifying Setup${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n  ${YELLOW}Router Balances:${NC}"
    for i in "${!TOKENS[@]}"; do
        balance=$(cast call $MOCK_ROUTER "tokenBalance(address)(uint256)" "${TOKENS[$i]}" --rpc-url $RPC_URL 2>/dev/null || echo "0")
        if [ "$balance" != "0" ]; then
            echo -e "    ${TOKEN_NAMES[$i]}: ${GREEN}$balance${NC}"
        else
            echo -e "    ${TOKEN_NAMES[$i]}: ${RED}0${NC}"
        fi
    done
    
    echo -e "\n  ${YELLOW}Sample Exchange Rates:${NC}"
    echo -ne "    AXL -> ETH: "
    cast call $MOCK_ROUTER "getExchangeRate(address,address)(uint256)" $AXL $ETH --rpc-url $RPC_URL 2>/dev/null || echo "N/A"
    echo -ne "    WBTC -> ETH: "
    cast call $MOCK_ROUTER "getExchangeRate(address,address)(uint256)" $WBTC $ETH --rpc-url $RPC_URL 2>/dev/null || echo "N/A"
    echo ""
}

# =============================================================================
# MAIN MENU
# =============================================================================
show_menu() {
    echo ""
    echo -e "${YELLOW}Select operation:${NC}"
    echo "  1) Run ALL steps (complete setup)"
    echo "  2) Setup Pool Fees only"
    echo "  3) Mint Tokens only"
    echo "  4) Deposit Liquidity only"
    echo "  5) Set Exchange Rates only"
    echo "  6) Verify Setup"
    echo "  0) Exit"
    echo ""
    read -p "Choice [1]: " choice
    choice=${choice:-1}
    
    case $choice in
        1)
            setup_pool_fees
            mint_tokens
            deposit_liquidity
            set_exchange_rates
            verify_setup
            ;;
        2) setup_pool_fees ;;
        3) mint_tokens ;;
        4) deposit_liquidity ;;
        5) set_exchange_rates ;;
        6) verify_setup ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}" ;;
    esac
}

# Run menu or all if --all flag
if [ "$1" == "--all" ]; then
    setup_pool_fees
    mint_tokens
    deposit_liquidity
    set_exchange_rates
    verify_setup
else
    show_menu
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                        SETUP COMPLETE!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
