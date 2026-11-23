#!/usr/bin/env bash
# Local Anvil rehearsal. Does not deploy to Fuji and does not use a private key.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${PATH}:$HOME/.foundry/bin"

if ! command -v anvil >/dev/null 2>&1 || ! command -v forge >/dev/null 2>&1 || ! command -v cast >/dev/null 2>&1; then
  echo "Foundry is required: anvil, forge, and cast." >&2
  exit 1
fi

PORT="${ANVIL_PORT:-8545}"
RPC="http://127.0.0.1:${PORT}"
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
VERIFIER=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
DEPOSIT=1000000

anvil --port "$PORT" --silent &
ANVIL_PID=$!
cleanup() {
  kill "$ANVIL_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.25
done
if [[ "$ready" -ne 1 ]]; then
  echo "Anvil did not start on port ${PORT}." >&2
  exit 1
fi

unset FUJI_DEPLOYER_PRIVATE_KEY
export FUJI_TREASURY_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export FUJI_VERIFIER_ADDRESS="$VERIFIER"

cd "$ROOT"
LOG="$(forge script script/Deploy.s.sol:DeployFuji \
  --rpc-url "$RPC" \
  --broadcast \
  --unlocked \
  --sender "$DEPLOYER")"
printf '%s\n' "$LOG"

USDC="$(printf '%s\n' "$LOG" | awk '$1=="MockUSDC" && $2 ~ /^0x[0-9a-fA-F]{40}$/ {addr=$2} END {print addr}')"
ESCROW="$(printf '%s\n' "$LOG" | awk '$1=="CommitmentEscrow" && $2 ~ /^0x[0-9a-fA-F]{40}$/ {addr=$2} END {print addr}')"
if [[ -z "$USDC" || -z "$ESCROW" ]]; then
  echo "Deploy logs did not include MockUSDC and CommitmentEscrow addresses." >&2
  exit 1
fi

NOW="$(cast block latest --rpc-url "$RPC" -f timestamp)"
DEADLINE=$((NOW + 180))
GOAL="$(cast keccak "anvil-commitment-deposit")"
VERDICT="$(cast keccak "anvil-proof-passed")"

cast send "$USDC" "mint(address,uint256)" "$DEPLOYER" "$DEPOSIT" \
  --unlocked --from "$DEPLOYER" --rpc-url "$RPC" >/dev/null
cast send "$USDC" "approve(address,uint256)" "$ESCROW" "$DEPOSIT" \
  --unlocked --from "$DEPLOYER" --rpc-url "$RPC" >/dev/null
cast send "$ESCROW" "openPool(bytes32,uint64,uint32)" "$GOAL" "$DEADLINE" 1 \
  --unlocked --from "$DEPLOYER" --rpc-url "$RPC" >/dev/null
cast send "$ESCROW" "createCommitment(bytes32,uint256,uint64)" "$GOAL" "$DEPOSIT" "$DEADLINE" \
  --unlocked --from "$DEPLOYER" --rpc-url "$RPC" >/dev/null
cast send "$ESCROW" "recordProof(bytes32,address,uint32,bytes32,bool)" "$GOAL" "$DEPLOYER" 0 "$VERDICT" true \
  --unlocked --from "$VERIFIER" --rpc-url "$RPC" >/dev/null

cast rpc evm_increaseTime 181 --rpc-url "$RPC" >/dev/null
cast rpc evm_mine --rpc-url "$RPC" >/dev/null

cast send "$ESCROW" "settle(bytes32)" "$GOAL" \
  --unlocked --from "$DEPLOYER" --rpc-url "$RPC" >/dev/null
cast send "$ESCROW" "claim(bytes32)" "$GOAL" \
  --unlocked --from "$DEPLOYER" --rpc-url "$RPC" >/dev/null

BALANCE_RAW="$(cast call "$USDC" "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url "$RPC")"
ESCROW_RAW="$(cast call "$USDC" "balanceOf(address)(uint256)" "$ESCROW" --rpc-url "$RPC")"
# cast prints `1000000 [1e6]`. Compare the integer token only.
BALANCE="${BALANCE_RAW%% *}"
ESCROW_BALANCE="${ESCROW_RAW%% *}"
if [[ "$BALANCE" != "$DEPOSIT" || "$ESCROW_BALANCE" != "0" ]]; then
  echo "Balance check failed. deployer=${BALANCE} escrow=${ESCROW_BALANCE}" >&2
  exit 1
fi

echo "Anvil flow ok. MockUSDC ${USDC} CommitmentEscrow ${ESCROW} refund ${BALANCE}"
