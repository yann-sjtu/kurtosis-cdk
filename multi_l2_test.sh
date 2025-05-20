#!/bin/bash

# Strict mode: exit immediately on any command failure, disallow undefined variables
set -eu

# Clean Kurtosis Environment
kurtosis clean --all
# Setup Kurtosis Environment
kurtosis run --enclave pp --args-file docs/multi-pp-testing/net1.yml .
kurtosis run --enclave pp --args-file docs/multi-pp-testing/net2.yml .

# =============================================================================
# Configuration
# =============================================================================

# Bridge contract address is the same on both L1 and L2 chains
BRIDGE_ADDRESS="0xC0fE590500Eb5FE9eB61aF774a10950CCA44bF0e"
ACCOUNT="0x8943545177806ED17B9F23F0a21ee5948eCaa776"
PRIVATE_KEY="0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"

# =============================================================================
# RPC Endpoints Setup
# =============================================================================

# Get RPC endpoints from Kurtosis
L1RPC=http://$(kurtosis port print pp el-1-geth-lighthouse rpc)
L2RPC1=$(kurtosis port print pp cdk-erigon-rpc-001 rpc)
L2RPC2=$(kurtosis port print pp cdk-erigon-rpc-002 rpc)
BRIDGE_SERVICE=$(kurtosis port print pp zkevm-bridge-proxy-002 web-ui)/bridgeservice

# Get Global Exit Root Manager addresses
GER_MGR=$(cast call $BRIDGE_ADDRESS "globalExitRootManager()(address)" --rpc-url "$L1RPC")
L2GER_MGR1=$(cast call $BRIDGE_ADDRESS "globalExitRootManager()(address)" --rpc-url "$L2RPC1")
L2GER_MGR2=$(cast call $BRIDGE_ADDRESS "globalExitRootManager()(address)" --rpc-url "$L2RPC2")
echo "Address of globalExitRootManager:"
echo "  L1   ==> $GER_MGR"
echo "  L2_1 ==> $L2GER_MGR1"
echo "  L2_2 ==> $L2GER_MGR2"

# Get initial Global Exit Root
GER=$(cast call "$GER_MGR" "getLastGlobalExitRoot()" --rpc-url "$L1RPC")
echo "Initial GER on L1 is $GER"

# =============================================================================
# Bridge Assets from L1 to L2_1
# =============================================================================
echo -e "\n========== BRIDGING ASSETS: L1 -> L2_1 =========="

# Check balance before bridging
L1_BALANCE_BEFORE_BRIDGE=$(cast balance $ACCOUNT --rpc-url "$L1RPC")

# Execute bridge transaction
polycli ulxly bridge asset \
    --bridge-address $BRIDGE_ADDRESS \
    --private-key $PRIVATE_KEY \
    --destination-network 1 \
    --value 10000000000000000000 \
    --rpc-url "$L1RPC"

# Check balance after bridging
L1_BALANCE_AFTER_BRIDGE=$(cast balance $ACCOUNT --rpc-url "$L1RPC")
echo "Balance on L1:"
echo "  Before bridge = $L1_BALANCE_BEFORE_BRIDGE"
echo "  After bridge  = $L1_BALANCE_AFTER_BRIDGE"

# Wait for GER update on L1
echo "Waiting for GER to be updated on L1..."
while true; do
    GER_NEW=$(cast call "$GER_MGR" "getLastGlobalExitRoot()" --rpc-url "$L1RPC")
    if [ "$GER_NEW" != "$GER" ]; then
        GER=$GER_NEW
        echo "GER updated to $GER on L1"
        break
    fi
    sleep 1
done

# Wait for GER to sync to L2
echo "Waiting for GER to sync to L2_1..."
start_time=$(date +%s)
while true; do
    timestamp=$(cast call "$L2GER_MGR1" "globalExitRootMap(bytes32)(uint256)" "$GER" --rpc-url "$L2RPC1")
    if [ "$timestamp" != "0" ]; then
        break
    fi
    sleep 1
done
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo "GER synced to L2_1, took $total_elapsed seconds"

# Wait for assets to be claimed automatically by sponsor
echo "Waiting for assets to be claimed by sponsor..."
start_time=$(date +%s)
while true; do
    balance=$(cast balance $ACCOUNT --rpc-url "$L2RPC1")
    if [ "$balance" = "10000000000000000000" ]; then
        break
    fi
    sleep 1
done
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo "Balance on L2_1 is $balance, claim took $total_elapsed seconds"

# =============================================================================
# Bridge Assets from L1 to L2_2
# =============================================================================
echo -e "\n========== BRIDGING ASSETS: L1 -> L2_2 =========="

# Check balance before bridging
L1_BALANCE_BEFORE_BRIDGE=$(cast balance $ACCOUNT --rpc-url "$L1RPC")

# Execute bridge transaction
polycli ulxly bridge asset \
    --bridge-address $BRIDGE_ADDRESS \
    --private-key $PRIVATE_KEY \
    --destination-network 2 \
    --value 10000000000000000000 \
    --rpc-url "$L1RPC"

# Check balance after bridging
L1_BALANCE_AFTER_BRIDGE=$(cast balance $ACCOUNT --rpc-url "$L1RPC")
echo "Balance on L1:"
echo "  Before bridge = $L1_BALANCE_BEFORE_BRIDGE"
echo "  After bridge  = $L1_BALANCE_AFTER_BRIDGE"

# Wait for GER update on L1
echo "Waiting for GER to be updated on L1..."
while true; do
    GER_NEW=$(cast call "$GER_MGR" "getLastGlobalExitRoot()" --rpc-url "$L1RPC")
    if [ "$GER_NEW" != "$GER" ]; then
        GER=$GER_NEW
        echo "GER updated to $GER on L1"
        break
    fi
    sleep 1
done

# Wait for GER to sync to L2
echo "Waiting for GER to sync to L2_2..."
start_time=$(date +%s)
while true; do
    timestamp=$(cast call "$L2GER_MGR2" "globalExitRootMap(bytes32)(uint256)" "$GER" --rpc-url "$L2RPC2")
    if [ "$timestamp" != "0" ]; then
        break
    fi
    sleep 1
done
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo "GER synced to L2_2, took $total_elapsed seconds"

# Wait for assets to be claimed automatically by sponsor
echo "Waiting for assets to be claimed by sponsor..."
start_time=$(date +%s)
while true; do
    balance=$(cast balance $ACCOUNT --rpc-url "$L2RPC2")
    if [ "$balance" = "10000000000000000000" ]; then
        break
    fi
    sleep 1
done
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo "Balance on L2_2 is $balance, claim took $total_elapsed seconds"

# =============================================================================
# Bridge Assets from L2_1 to L2_2
# =============================================================================
echo -e "\n========== BRIDGING ASSETS: L2_1 -> L2_2 =========="

# Execute bridge transaction and capture output
result=$(polycli ulxly bridge asset \
    --bridge-address $BRIDGE_ADDRESS \
    --private-key $PRIVATE_KEY \
    --destination-network 2 \
    --value 1000000000000000000 \
    --rpc-url "$L2RPC1" 2>&1)
echo "$result"

# Extract transaction hash and deposit count
TX_HASH=$(echo "$result" | grep -o "txHash=.*" | cut -d= -f2 | sed 's/\x1b\[[0-9;]*m//g')
echo "Bridge transaction hash = $TX_HASH"
LOG_DATA=$(cast receipt "$TX_HASH" --rpc-url "$L2RPC1" --json | jq -r '.logs[0].data')
DEPOSIT_COUNT=0x${LOG_DATA:450:64}
echo "Deposit count = $DEPOSIT_COUNT"

# Wait for GER update on L1
echo "Waiting for GER to be updated on L1..."
start_time=$(date +%s)
while true; do
    GER_NEW=$(cast call "$GER_MGR" "getLastGlobalExitRoot()" --rpc-url "$L1RPC")
    if [ "$GER_NEW" != "$GER" ]; then
        GER=$GER_NEW
        break
    fi
    sleep 1
done
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo "GER updated to $GER on L1, took $total_elapsed seconds"

# Wait for GER to sync to L2
echo "Waiting for GER to sync to L2_2..."
start_time=$(date +%s)
while true; do
    timestamp=$(cast call "$L2GER_MGR2" "globalExitRootMap(bytes32)(uint256)" "$GER" --rpc-url "$L2RPC2")
    if [ "$timestamp" != "0" ]; then
        break
    fi
    sleep 1
done
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo "GER synced to L2_2, took $total_elapsed seconds"

# Claim assets manually (not auto-claimed for L2->L2)
L2_BALANCE_BEFORE_CLAIM=$(cast balance $ACCOUNT --rpc-url "$L2RPC2")
polycli ulxly claim asset \
    --bridge-address $BRIDGE_ADDRESS \
    --bridge-service-url "$BRIDGE_SERVICE" \
    --private-key $PRIVATE_KEY \
    --deposit-network 1 \
    --deposit-count "$DEPOSIT_COUNT" \
    --rpc-url "$L2RPC2"
L2_BALANCE_AFTER_CLAIM=$(cast balance $ACCOUNT --rpc-url "$L2RPC2")
echo "Balance on L2_2:"
echo "  Before claim = $L2_BALANCE_BEFORE_CLAIM"
echo "  After claim  = $L2_BALANCE_AFTER_CLAIM"

# =============================================================================
# Bridge Assets from L2_2 to L2_1
# =============================================================================
echo -e "\n========== BRIDGING ASSETS: L2_2 -> L2_1 =========="

# Execute bridge transaction and capture output
result=$(polycli ulxly bridge asset \
    --bridge-address $BRIDGE_ADDRESS \
    --private-key $PRIVATE_KEY \
    --destination-network 1 \
    --value 2000000000000000000 \
    --rpc-url "$L2RPC2" 2>&1)
echo "$result"

# Extract transaction hash and deposit count
TX_HASH=$(echo "$result" | grep -o "txHash=.*" | cut -d= -f2 | sed 's/\x1b\[[0-9;]*m//g')
echo "Bridge transaction hash = $TX_HASH"
LOG_DATA=$(cast receipt "$TX_HASH" --rpc-url "$L2RPC2" --json | jq -r '.logs[0].data')
DEPOSIT_COUNT=0x${LOG_DATA:450:64}
echo "Deposit count = $DEPOSIT_COUNT"

# Wait for GER update on L1
echo "Waiting for GER to be updated on L1..."
start_time=$(date +%s)
while true; do
    GER_NEW=$(cast call "$GER_MGR" "getLastGlobalExitRoot()" --rpc-url "$L1RPC")
    if [ "$GER_NEW" != "$GER" ]; then
        GER=$GER_NEW
        break
    fi
    sleep 1
done
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo "GER updated to $GER on L1, took $total_elapsed seconds"

# Wait for GER to sync to L2
echo "Waiting for GER to sync to L2_1..."
start_time=$(date +%s)
while true; do
    timestamp=$(cast call "$L2GER_MGR1" "globalExitRootMap(bytes32)(uint256)" "$GER" --rpc-url "$L2RPC1")
    if [ "$timestamp" != "0" ]; then
        break
    fi
    sleep 1
done
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo "GER synced to L2_1, took $total_elapsed seconds"

# Claim assets manually (not auto-claimed for L2->L2)
L2_BALANCE_BEFORE_CLAIM=$(cast balance $ACCOUNT --rpc-url "$L2RPC1")
polycli ulxly claim asset \
    --bridge-address $BRIDGE_ADDRESS \
    --bridge-service-url "$BRIDGE_SERVICE" \
    --private-key $PRIVATE_KEY \
    --deposit-network 2 \
    --deposit-count "$DEPOSIT_COUNT" \
    --rpc-url "$L2RPC1"
L2_BALANCE_AFTER_CLAIM=$(cast balance $ACCOUNT --rpc-url "$L2RPC1")
echo "Balance on L2_1:"
echo "  Before claim = $L2_BALANCE_BEFORE_CLAIM"
echo "  After claim  = $L2_BALANCE_AFTER_CLAIM"
