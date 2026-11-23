# Operator Uplift commitment escrow (Avalanche Fuji)

Operator Uplift commitment-deposit escrow on Avalanche Fuji testnet, built for Team1 Builders Demo Day.

A commitment deposit is a refundable pledge toward a shared goal. A person puts test USDC into a pool, a verifier records daily photo-proof verdicts, and settlement returns the deposit to people who finish.

The MIT license in `LICENSE` applies to this repository.

`MockUSDC` is a Fuji testnet faucet. Do not deploy it on Avalanche mainnet.

## Design

`openPool(goalId, deadline, requiredProofDays)` creates a pool. The first caller fixes two terms:

- `deadline`, a unix timestamp. Settlement is refused before it.
- `requiredProofDays`, how many passed days finish the commitment. Days are numbered `0 .. requiredProofDays - 1`, with a cap of 366.

`createCommitment(goalId, amount, deadline)` is the deposit. It pulls `amount` of the escrow token (test USDC, 6 decimals) into the pool. `deadline` must match the opened pool. It does not change the terms. Many addresses can join one `goalId`. One address joins a pool once. The pool holds at most 64 deposits, so settlement cannot grow without a bound.

`recordProof(goalId, user, day, verdictHash, passed)` is `VERIFIER_ROLE` only. It emits `ProofRecorded`. The same day cannot be recorded twice. The contract stores `verdictHash`. It does not recompute it. The app defines that hash as keccak256 of the canonical verdict JSON (sorted object keys, no whitespace). Proofs are accepted until settlement, including after the deadline, so a slightly late verifier can still record the last day.

`settle(goalId)` can be called by anyone once `block.timestamp >= deadline`. It does not transfer tokens. It writes pull payments once. A second call reverts with `AlreadySettled` and moves nothing.

- A finisher (passed days >= `requiredProofDays`) can claim their full deposit back, plus a pro-rata share of 96 percent of the deposits of people who did not finish. The share is weighted by each finisher's own deposit.
- 4 percent of the missed deposits goes to the treasury address set in the constructor. Integer-division dust is added to the treasury, so the contract can pay out the whole balance. The treasury therefore receives at least 4 percent, and sometimes a few extra base units.
- People who did not finish receive nothing when at least one person finished.

If nobody finished, there is no finisher to receive the 96 percent. Each depositor can claim `amount * 9600 / 10000` of their own deposit, and the remaining 4 percent plus dust goes to the treasury. The event flag `nobodyFinished` is true. Funds are not stuck.

`claim(goalId)` and `claimTreasury(goalId)` are the pulls. Claims are one-shot. The treasury pull sends to the immutable treasury, never to the caller. State is updated before the token transfer, and the entry points that move tokens use `ReentrancyGuard` and `SafeERC20`.

`MockUSDC` has 6 decimals and a public `mint`. That mint is a testnet faucet.

## Deployed on Fuji (testnet)

Both contracts are verified.

- CommitmentEscrow `0xBd806A533435029AF2d5eE514D002367Aa4886a3`  
  https://testnet.snowtrace.io/address/0xBd806A533435029AF2d5eE514D002367Aa4886a3
- MockUSDC `0x70Ef2264cFFAA7DE4e160C3d584DB5B941eE707e`  
  https://testnet.snowtrace.io/address/0x70Ef2264cFFAA7DE4e160C3d584DB5B941eE707e

Addresses, transaction hashes, and the smoke test are in [DEPLOYMENTS.md](DEPLOYMENTS.md).

## Layout

Git submodules, pinned in `.gitmodules`:

- OpenZeppelin Contracts v5.2.0 (`acd4ff74de833399287ed6b31b4debf6b2b35527`) at `lib/openzeppelin-contracts`
- forge-std v1.11.0 (`8e40513d678f392f398620b3ef2b418648b33e89`) at `lib/forge-std`

Solidity `0.8.24`. Optimizer on, 200 runs. Fuji chain id `43113`. RPC `https://api.avax-test.network/ext/bc/C/rpc`.

## Build

```sh
git clone --recurse-submodules https://github.com/operatoruplift/uplift-avalanche
cd uplift-avalanche
forge build
```

If the repository is already cloned without submodules:

```sh
git submodule update --init --recursive
forge build
```

Foundry downloads solc 0.8.24 on the first build.

## Test

```sh
forge test
```

## Local Anvil flow

`script/anvil-e2e.sh` starts Anvil, deploys with `--unlocked` (no private key), and runs the deposit, verifier record, settle, and claim flow against that local chain. It checks that the finisher receives the full test deposit back.

```sh
script/anvil-e2e.sh
```

## Deploy

Requires a funded deployer. This repository does not create that key, and it does not contain one. Copy `.env.example` to `.env` locally and export the variables in your shell. Do not commit `.env`.

```sh
forge script script/Deploy.s.sol:DeployFuji \
  --rpc-url "$FUJI_RPC_URL" \
  --broadcast \
  --slow
```

`FUJI_DEPLOYER_PRIVATE_KEY` is read inside the script with `vm.envUint` when it is non-empty. `FUJI_TREASURY_ADDRESS` and `FUJI_VERIFIER_ADDRESS` are required. The script deploys `MockUSDC` and `CommitmentEscrow`, and grants `VERIFIER_ROLE` to the verifier address. The deployer is the admin.

The live Fuji deployment is the one linked above. A new broadcast is a new pair of contracts.

## Verify on Snowtrace (Routescan)

```sh
forge verify-contract \
  --chain fuji \
  --constructor-args "$(cast abi-encode "constructor(address,address,address)" "$FUJI_USDC_ADDRESS" "$FUJI_TREASURY_ADDRESS" "$FUJI_ADMIN_ADDRESS")" \
  "$FUJI_ESCROW_ADDRESS" \
  src/CommitmentEscrow.sol:CommitmentEscrow

forge verify-contract \
  --chain fuji \
  "$FUJI_USDC_ADDRESS" \
  src/MockUSDC.sol:MockUSDC
```

`foundry.toml` points chain `fuji` at `https://api.routescan.io/v2/network/testnet/evm/43113/etherscan/api`. `SNOWTRACE_API_KEY` is read from the environment. Routescan often accepts any non-empty key. The equivalent explicit verifier URL is:

```sh
forge verify-contract \
  --chain-id 43113 \
  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/43113/etherscan/api" \
  --etherscan-api-key "$SNOWTRACE_API_KEY" \
  --constructor-args "$(cast abi-encode "constructor(address,address,address)" "$FUJI_USDC_ADDRESS" "$FUJI_TREASURY_ADDRESS" "$FUJI_ADMIN_ADDRESS")" \
  "$FUJI_ESCROW_ADDRESS" \
  src/CommitmentEscrow.sol:CommitmentEscrow
```

Verified source should match optimizer 200 and solc 0.8.24.
