#!/usr/bin/env bash
# Local Anvil rehearsal for both deploy entry points.
# Does not broadcast to BNB Smart Chain or Fuji and does not use a private key.
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
TREASURY=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
DEPOSIT=1000000

# Chain 97 is also the real BSC testnet id. Keep rehearsal receipts out of
# broadcast/ so they cannot be mistaken for a BscScan deployment.
SCRATCH="$(mktemp -d)"
export FOUNDRY_BROADCAST="${SCRATCH}/broadcast"
export FOUNDRY_CACHE_PATH="${SCRATCH}/cache"

PIDS=()
cleanup() {
  for pid in "${PIDS[@]+"${PIDS[@]}"}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

start_anvil() {
  local port="$1"
  local chain_id="${2:-}"
  if [[ -n "$chain_id" ]]; then
    anvil --port "$port" --chain-id "$chain_id" --silent &
  else
    anvil --port "$port" --silent &
  fi
  PIDS+=("$!")
  local rpc="http://127.0.0.1:${port}"
  local ready=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if cast chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.25
  done
  if [[ "$ready" -ne 1 ]]; then
    echo "Anvil did not start on port ${port}." >&2
    exit 1
  fi
}

unset FUJI_DEPLOYER_PRIVATE_KEY
unset BSC_DEPLOYER_PRIVATE_KEY

cd "$ROOT"

# Deposit, record, settle, and claim against one unlocked deploy.
rehearse() {
  local contract="$1"
  local prefix="$2"
  local rpc="$3"
  unset FUJI_TREASURY_ADDRESS FUJI_VERIFIER_ADDRESS
  unset BSC_TREASURY_ADDRESS BSC_VERIFIER_ADDRESS
  export "${prefix}_TREASURY_ADDRESS=${TREASURY}"
  export "${prefix}_VERIFIER_ADDRESS=${VERIFIER}"

  local log
  log="$(forge script "script/Deploy.s.sol:${contract}" \
    --rpc-url "$rpc" \
    --broadcast \
    --unlocked \
    --sender "$DEPLOYER")"
  printf '%s\n' "$log"

  local usdc escrow
  usdc="$(printf '%s\n' "$log" | awk '$1=="MockUSDC" && $2 ~ /^0x[0-9a-fA-F]{40}$/ {addr=$2} END {print addr}')"
  escrow="$(printf '%s\n' "$log" | awk '$1=="CommitmentEscrow" && $2 ~ /^0x[0-9a-fA-F]{40}$/ {addr=$2} END {print addr}')"
  if [[ -z "$usdc" || -z "$escrow" ]]; then
    echo "Deploy logs did not include MockUSDC and CommitmentEscrow addresses." >&2
    exit 1
  fi

  local now deadline goal verdict
  now="$(cast block latest --rpc-url "$rpc" -f timestamp)"
  deadline=$((now + 180))
  goal="$(cast keccak "anvil-commitment-deposit-${contract}")"
  verdict="$(cast keccak "anvil-proof-passed-${contract}")"

  cast send "$usdc" "mint(address,uint256)" "$DEPLOYER" "$DEPOSIT" \
    --unlocked --from "$DEPLOYER" --rpc-url "$rpc" >/dev/null
  cast send "$usdc" "approve(address,uint256)" "$escrow" "$DEPOSIT" \
    --unlocked --from "$DEPLOYER" --rpc-url "$rpc" >/dev/null
  cast send "$escrow" "openPool(bytes32,uint64,uint32)" "$goal" "$deadline" 1 \
    --unlocked --from "$DEPLOYER" --rpc-url "$rpc" >/dev/null
  cast send "$escrow" "createCommitment(bytes32,uint256,uint64)" "$goal" "$DEPOSIT" "$deadline" \
    --unlocked --from "$DEPLOYER" --rpc-url "$rpc" >/dev/null
  cast send "$escrow" "recordProof(bytes32,address,uint32,bytes32,bool)" "$goal" "$DEPLOYER" 0 "$verdict" true \
    --unlocked --from "$VERIFIER" --rpc-url "$rpc" >/dev/null

  cast rpc evm_increaseTime 181 --rpc-url "$rpc" >/dev/null
  cast rpc evm_mine --rpc-url "$rpc" >/dev/null

  cast send "$escrow" "settle(bytes32)" "$goal" \
    --unlocked --from "$DEPLOYER" --rpc-url "$rpc" >/dev/null
  cast send "$escrow" "claim(bytes32)" "$goal" \
    --unlocked --from "$DEPLOYER" --rpc-url "$rpc" >/dev/null

  local balance_raw escrow_raw balance escrow_balance
  balance_raw="$(cast call "$usdc" "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url "$rpc")"
  escrow_raw="$(cast call "$usdc" "balanceOf(address)(uint256)" "$escrow" --rpc-url "$rpc")"
  # cast prints `1000000 [1e6]`. Compare the integer token only.
  balance="${balance_raw%% *}"
  escrow_balance="${escrow_raw%% *}"
  if [[ "$balance" != "$DEPOSIT" || "$escrow_balance" != "0" ]]; then
    echo "Balance check failed for ${contract}. deployer=${balance} escrow=${escrow_balance}" >&2
    exit 1
  fi

  echo "Anvil flow ok. ${contract} MockUSDC ${usdc} CommitmentEscrow ${escrow} refund ${balance}"
}

# Deploy entry point must revert on the wrong chain. A compile or RPC failure
# is not treated as a successful refusal.
expect_refuse() {
  local contract="$1"
  local prefix="$2"
  local rpc="$3"
  unset FUJI_TREASURY_ADDRESS FUJI_VERIFIER_ADDRESS
  unset BSC_TREASURY_ADDRESS BSC_VERIFIER_ADDRESS
  export "${prefix}_TREASURY_ADDRESS=${TREASURY}"
  export "${prefix}_VERIFIER_ADDRESS=${VERIFIER}"

  local log status
  set +e
  log="$(forge script "script/Deploy.s.sol:${contract}" \
    --rpc-url "$rpc" \
    --broadcast \
    --unlocked \
    --sender "$DEPLOYER" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "Expected ${contract} to refuse ${rpc}." >&2
    printf '%s\n' "$log" >&2
    exit 1
  fi
  if [[ "$log" != *"refusing chain"* && "$log" != *"WrongChain"* ]]; then
    echo "Expected ${contract} to revert with WrongChain on ${rpc}." >&2
    printf '%s\n' "$log" >&2
    exit 1
  fi
  echo "Chain guard ok. ${contract} refused ${rpc}."
}

start_anvil "$PORT"
rehearse DeployFuji FUJI "$RPC"
rehearse DeployBscTestnet BSC "$RPC"

# Chain 97 is the BSC testnet target. Chain 56 is BNB Smart Chain mainnet and
# must be refused, as must pointing the Fuji entry point at chain 97.
BSC_PORT="${ANVIL_BSC_PORT:-18545}"
MAINNET_PORT="${ANVIL_BSC_MAINNET_PORT:-18546}"
start_anvil "$BSC_PORT" 97
start_anvil "$MAINNET_PORT" 56
rehearse DeployBscTestnet BSC "http://127.0.0.1:${BSC_PORT}"
expect_refuse DeployBscTestnet BSC "http://127.0.0.1:${MAINNET_PORT}"
expect_refuse DeployFuji FUJI "http://127.0.0.1:${BSC_PORT}"

echo "Anvil flow ok. Fuji and BSC testnet entry points settled, and the chain guard refused mainnet."
