#!/bin/bash

# =============================================================================
# Update Depositor Contract di Semua TokenYield
# =============================================================================
# Script ini akan update depositorContract ke KubiStreamer baru
# untuk semua TokenYield contracts
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# New KubiStreamer address
KUBI_STREAMER="0xDb26Ba8581979dc4E11218735F821Af5171fb737"
RPC_URL="https://rpc.sepolia.mantle.xyz"

# All TokenYield contracts
declare -A YIELD_CONTRACTS
YIELD_CONTRACTS["miUSDC"]="0x2007Cb1a90E71c18983F1d4091261816E9e9c2dA"
YIELD_CONTRACTS["miUSDT"]="0x04F0aEf9cb921A8Ad848FA8B49aF7fc2E60DbcCb"
YIELD_CONTRACTS["miMNT"]="0x8c2B7136dDaF6129cE33f58d3E5475a0ed3F7b3C"
YIELD_CONTRACTS["miBTC"]="0x8e0dCfecDEEBb1da38DD1bbE9418FD7a4bdd4922"
YIELD_CONTRACTS["miETH"]="0x89C0fa2BAE88752eC733922daa0c2Ff321bb5279"
YIELD_CONTRACTS["leUSDC"]="0xa6c9dD702B198Da46f9C5b21bBe65a2a31fdEB63"
YIELD_CONTRACTS["leUSDT"]="0x5c8b8caa55Af0d10ACc3ec95A614d26C90BD9b62"
YIELD_CONTRACTS["leMNT"]="0xfCbFBaDe92450979DfF2F10449E7917c722AF50"
YIELD_CONTRACTS["leBTC"]="0x0dF313cE12b511062eCe811e435F0729E7c9746f"
YIELD_CONTRACTS["leETH"]="0xB1eF139d2f4D56B126196D9FF712b67e120c0349"
YIELD_CONTRACTS["aaUSDC"]="0x324Db0D78D0225431A2bD49470018b322a006833"
YIELD_CONTRACTS["aaUSDT"]="0xbF1dC15Eaa6449d5bf81463578808313F5e208Ee"
YIELD_CONTRACTS["aaMNT"]="0xc79F99285A0f4B640c552090eEab8CAbc4433C1D"
YIELD_CONTRACTS["aaBTC"]="0xA5FC97D4eEE36Cf0CF5beE22cF78e74cE9882E81"
YIELD_CONTRACTS["aaETH"]="0xdf3eBc828195ffBc71bB80c467cF70BfDEf0AC1E"
YIELD_CONTRACTS["coUSDC"]="0x8edafBaDe92450979DfF2F10449E7917c722AF50"
YIELD_CONTRACTS["coUSDT"]="0xdf5Ca06845d1b2F3ddff5759a493fB5aff68d72d"
YIELD_CONTRACTS["coMNT"]="0xBfc03BA44AcA79cFe6732968f99E9DB0B3880828"
YIELD_CONTRACTS["coBTC"]="0x4E55B3951d334aF5a88474d252f789911E1EFc55"
YIELD_CONTRACTS["coETH"]="0xE54116B3FA1623EB5aAC2ED4628002ceE620E9D8"

MAX_RETRIES=3

# Check PRIVATE_KEY
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set!${NC}"
    echo "Run: export PRIVATE_KEY=0x..."
    exit 1
fi

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     UPDATE DEPOSITOR CONTRACT FOR ALL YIELD TOKENS            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "New Depositor: ${YELLOW}$KUBI_STREAMER${NC}"
echo ""

success=0
failed=0
total=${#YIELD_CONTRACTS[@]}
count=0

for name in "${!YIELD_CONTRACTS[@]}"; do
    count=$((count + 1))
    address="${YIELD_CONTRACTS[$name]}"
    echo -ne "  [${count}/${total}] ${name} (${address:0:10}...)... "
    
    retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        if cast send "$address" \
            "updateDepositorContract(address)" \
            "$KUBI_STREAMER" \
            --rpc-url $RPC_URL \
            --private-key $PRIVATE_KEY \
            --quiet 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
            success=$((success + 1))
            break
        fi
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            sleep 2
        fi
    done
    
    if [ $retries -eq $MAX_RETRIES ]; then
        echo -e "${RED}✗ (failed after $MAX_RETRIES retries)${NC}"
        failed=$((failed + 1))
    fi
done

echo ""
echo -e "${GREEN}Success: $success${NC} | ${RED}Failed: $failed${NC}"
echo ""
echo -e "${GREEN}Done!${NC}"
