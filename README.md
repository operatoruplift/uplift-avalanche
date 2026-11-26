# Operator Uplift on BNB Chain

Operator Uplift is a stake-on-your-goals accountability app with more than 2,000 users. This repository is the public commitment escrow behind it. A person locks a refundable test USDC deposit on a shared goal. A verifier records daily photo-proof verdicts. After the deadline, people who finish claim their deposit back, plus a pro-rata share of the deposits from people who missed.

The hackathon build runs on BNB Smart Chain testnet (chain id 97). The same contracts already run on Avalanche Fuji. The GitHub repository name remains `uplift-avalanche`. The contracts are chain-agnostic. This build uses testnet tokens. `MockUSDC` is a faucet token for those testnets.

The MIT license in `LICENSE` applies to this repository.

## Status

BNB Smart Chain testnet deployment is pending a funded deployer key. The deploy and verify commands are below. No key is stored in this repository. Avalanche Fuji is already deployed and verified. Addresses and the Fuji smoke test are in [DEPLOYMENTS.md](DEPLOYMENTS.md).

What is new for the BNB Bangkok hackathon, the agent boundary, the faucet routes, and the deployer and verifier addresses prepared for the BSC testnet deploy are in [docs/BNB_BANGKOK.md](docs/BNB_BANGKOK.md). The HackQuest paste sheet is [SUBMISSION.md](SUBMISSION.md).

## Problem

People set a goal, miss a few days, and the goal disappears into a notes app. A shared pool makes the follow-through concrete. Everyone deposits the same kind of token, under the same deadline, with the same number of proof days. The rule is on-chain, so nobody in the pool gets a private exception.

## How it works on BNB Chain

The live walkthrough is [binance.operatoruplift.com](https://binance.operatoruplift.com). The page uses the escrow once `NEXT_PUBLIC_BSC_ESCROW_ADDRESS` and `NEXT_PUBLIC_BSC_USDC_ADDRESS` are set from the deploy below.

1. Get test BNB for gas from the [BNB Chain testnet faucet](https://www.bnbchain.org/en/testnet-faucet).
2. Connect MetaMask. The page uses BNB Smart Chain testnet.

| Field | Value |
| --- | --- |
| Network | BNB Smart Chain Testnet |
| RPC | `https://data-seed-prebsc-1-s1.bnbchain.org:8545` |
| Chain id | `97` |
| Symbol | tBNB |
| Explorer | https://testnet.bscscan.com |

3. Mint test USDC. The mint button calls public `mint` on `MockUSDC`.
4. Open a pool, or join one by using the same goal name. The deposit is test USDC (6 decimals).
5. Submit one photo. The server reviews it and, when the verifier key is set, records a passed day on-chain.
6. After the deadline, anyone can settle. Each person then claims. The demo can use a deadline a few minutes out so a walkthrough finishes in one sitting.

## Architecture

This repository is the Foundry escrow. The browser app is the Operator Uplift website (`operatoruplift/WEBSITE`). `binance.operatoruplift.com` is the BNB Chain demo. `fuji.operatoruplift.com` is the Fuji demo.

```
MetaMask (ethers v6)
  openPool, createCommitment, settle, claim
        |
        +--> POST /api/uplift/bnb/proof
               wallet signature over goal, day, challenge, photo
               vision review
               keccak256 of the canonical verdict JSON
               recordProof from the VERIFIER_ROLE key
        |
CommitmentEscrow on BNB Smart Chain testnet (chain id 97)
  stores the verdict hash
  writes pull payments once, at settle
```

The browser does not send a pass bit. A failed or abstained review is not written, so that day stays open. Settlement can be called by anyone after the deadline and moves no tokens. `claim` pays the caller the amount `settle` already wrote. `claimTreasury` pays the immutable treasury, never the caller.

The server records a proof only when the deployment has the variables below. Names only:

| Variable | Who reads it | What it is |
| --- | --- | --- |
| `NEXT_PUBLIC_BSC_ESCROW_ADDRESS` | browser, inlined at build | escrow address |
| `NEXT_PUBLIC_BSC_USDC_ADDRESS` | browser, inlined at build | test USDC address |
| `NEXT_PUBLIC_BSC_CHAIN_ID` | browser, optional | `97`, or `31337` for local Anvil |
| `NEXT_PUBLIC_BSC_RPC_URL` | browser, optional | public BSC testnet RPC when the chain id is `97` |
| `BSC_ESCROW_ADDRESS` | server, each request | same escrow address |
| `BSC_RPC_URL` | server | BSC testnet RPC used to send `recordProof` |
| `BSC_VERIFIER_ADDRESS` | server | address that holds `VERIFIER_ROLE` |
| `BSC_VERIFIER_PRIVATE_KEY` | server only | key for that address. Never `NEXT_PUBLIC_` |
| `ANTHROPIC_API_KEY` or `PROOF_VISION_API_KEY` | server | vision review, shared with the rest of the app |
| `UPSTASH_REDIS_REST_URL` | server | paid-call budget, shared with the rest of the app |
| `UPSTASH_REDIS_REST_TOKEN` | server | paid-call budget, shared with the rest of the app |

`BSC_VERIFIER_PRIVATE_KEY` must be the key for the address granted `VERIFIER_ROLE` at deploy time. A new key is created with `cast wallet new`. Keep the printed key in the host's secret store, not in git. Fund that address with test BNB so it can send `recordProof`.

Without the vision key, the proof route returns `enabled: false` and records nothing. Without Upstash, the review abstains. Without `BSC_VERIFIER_PRIVATE_KEY`, a passed review returns `verifier_not_configured` and writes nothing.

## Settlement

`openPool(goalId, deadline, requiredProofDays)` creates a pool. The first caller fixes two terms:

- `deadline`, a unix timestamp. Settlement is refused before it.
- `requiredProofDays`, how many passed days finish the commitment. Days are numbered `0 .. requiredProofDays - 1`, with a cap of 366.

`createCommitment(goalId, amount, deadline)` is the deposit. It pulls `amount` of the escrow token (test USDC, 6 decimals) into the pool. `deadline` must match the opened pool. It does not change the terms. Many addresses can join one `goalId`. One address joins a pool once. The pool holds at most 64 deposits, so settlement cannot grow without a bound.

`recordProof(goalId, user, day, verdictHash, passed)` is `VERIFIER_ROLE` only. It emits `ProofRecorded`. The same day cannot be recorded twice. The contract stores `verdictHash`. It does not recompute it. The app defines that hash as keccak256 of the canonical verdict JSON (sorted object keys, no whitespace). Proofs are accepted until settlement, including after the deadline, so a slightly late verifier can still record the last day.

`settle(goalId)` can be called by anyone once `block.timestamp >= deadline`. It does not transfer tokens. It writes pull payments once. A second call reverts with `AlreadySettled` and moves nothing.

- A finisher (passed days >= `requiredProofDays`) can claim their full deposit back, plus a pro-rata share of 96 percent of the deposits of people who did not finish. The share is weighted by each finisher's own deposit.
- 4 percent of the missed deposits goes to the treasury address set in the constructor. Integer-division dust is added to the treasury, so the contract can transfer its full balance. The treasury therefore receives at least 4 percent of missed deposits, and sometimes a few extra base units.
- People who did not finish receive nothing when at least one person finished.
- If everyone finishes, missed deposits are zero and the treasury receives nothing from that pool. Finishers claim exactly what they deposited.

If nobody finished, there is no finisher to receive the 96 percent. Each depositor can claim `amount * 9600 / 10000` of their own deposit, and the remaining 4 percent plus dust goes to the treasury. The event flag `nobodyFinished` is true. Funds are not stuck.

`claim(goalId)` and `claimTreasury(goalId)` are the pulls. Claims are one-shot. The treasury pull sends to the immutable treasury, never to the caller. State is updated before the token transfer, and the entry points that move tokens use `ReentrancyGuard` and `SafeERC20`.

## Business model

Protocol revenue is the 4 percent treasury fee on missed deposits. That fee is taken only from deposits of people who did not finish. A finisher's own deposit is returned in full.

Finishers also receive pro-rata pool rewards: 96 percent of the missed deposits, split in proportion to each finisher's deposit. Two people who finish, one of whom deposited twice as much, split that 96 percent two to one.

If everyone finishes, the protocol earns nothing from that pool. Revenue shows up when the accountability rule matters, and it does not tax the people who kept the goal. If nobody finishes, each person can still claim 96 percent of their own deposit and the treasury still receives 4 percent.

This submission collects that fee in test USDC on BNB Smart Chain testnet. A later mainnet release would use a real stablecoin and the same fee schedule, after a separate review. `MockUSDC` stays on testnet. Optional later revenue is a paid product for private team pools and extra verifier tools. The on-chain fee stands on its own and does not require a subscription.

The existing Operator Uplift community is the distribution. More than 2,000 people already set goals in the product. A public testnet challenge is the next step, with the pool terms visible on BscScan.

## Roadmap

1. Broadcast the BSC testnet deploy (`DeployBscTestnet` or `DeployBnb`) with a funded deployer, verify on BscScan, and write the addresses into [DEPLOYMENTS.md](DEPLOYMENTS.md).
2. Set the `NEXT_PUBLIC_BSC_*` and `BSC_*` variables so [binance.operatoruplift.com](https://binance.operatoruplift.com) points at those contracts.
3. Run a public testnet challenge with the existing Operator Uplift community. Keep deadlines short enough that a pool can settle during a demo.
4. Add a second verifier address so one key is not the only writer of proofs. The contract already uses `AccessControl` for this.
5. After review, deploy the same escrow on BNB Smart Chain mainnet with a real stablecoin. Leave `MockUSDC` on testnet. Keep the 4 percent fee and the 64 person cap.
6. Add team pools and a public finish-rate view so the community can see the rule working.

## Layout

Git submodules, pinned in `.gitmodules`:

- OpenZeppelin Contracts v5.2.0 (`acd4ff74de833399287ed6b31b4debf6b2b35527`) at `lib/openzeppelin-contracts`
- forge-std v1.11.0 (`8e40513d678f392f398620b3ef2b418648b33e89`) at `lib/forge-std`

Solidity `0.8.24`. Optimizer on, 200 runs.

| Network | Chain id | Foundry RPC alias |
| --- | --- | --- |
| BNB Smart Chain testnet | `97` | `bsc-testnet`, or `bsc_testnet` for a second public endpoint |
| opBNB testnet, optional | `5611` | `opbnb_testnet` |
| Avalanche Fuji | `43113` | `fuji` |
| Local Anvil | `31337` | `anvil` |

## Setup

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

Foundry downloads solc 0.8.24 on the first build. Copy `.env.example` to `.env` locally when you deploy. Do not commit `.env`.

## Test

```sh
forge test
```

`forge test` runs 17 tests: 12 for `CommitmentEscrow`, and 5 that run `script/DeployBnb.s.sol` in-process. Those 5 cover the role grant on chain id `97`, the treasury default on opBNB testnet, the public mint, and the refusal of chain ids `56` and `43113`.

`script/anvil-e2e.sh` starts Anvil, deploys with `--unlocked` (no private key), and runs the deposit, verifier record, settle, and claim flow. It does this for `DeployFuji` and `DeployBscTestnet`, then again for `DeployBscTestnet` on a local chain id `97`. It also checks that `DeployBscTestnet` refuses chain id `56` and that `DeployFuji` refuses chain id `97`.

```sh
script/anvil-e2e.sh
```

## Deploy on BNB Smart Chain testnet

Two entry points deploy the same two contracts on chain id `97`. `script/Deploy.s.sol:DeployBscTestnet` shares its code with the Fuji deploy and needs an explicit treasury. `script/DeployBnb.s.sol:DeployBnb` is described after it. Use one of them for a given deployment.

Requires a funded deployer. This repository does not create that key, and it does not contain one. Export the variables in your shell. The script reads `BSC_DEPLOYER_PRIVATE_KEY` when it is non-empty, so the key does not need to appear in the command.

```sh
export BSC_TREASURY_ADDRESS=0xYourTreasury
export BSC_VERIFIER_ADDRESS=0xYourVerifier
export BSC_DEPLOYER_PRIVATE_KEY=0xYourFundedDeployerKey
forge script script/Deploy.s.sol:DeployBscTestnet \
  --rpc-url bsc-testnet \
  --broadcast \
  --slow
```

`bsc-testnet` is the RPC alias in `foundry.toml`: `https://data-seed-prebsc-1-s1.bnbchain.org:8545`. The same name is Foundry's chain alias for chain id 97, so verify uses `--chain bsc-testnet`. The explicit form `--rpc-url "$BSC_RPC_URL"` is the same endpoint.

The script deploys `MockUSDC` and `CommitmentEscrow`, and grants `VERIFIER_ROLE` to `BSC_VERIFIER_ADDRESS`. The deployer is the admin. It reverts on any chain other than `97` and local Anvil `31337`. If a dataseed rejects a type-2 transaction, rerun the same command with `--legacy` added.

Copy the logged addresses into [DEPLOYMENTS.md](DEPLOYMENTS.md) and into the website variables in the architecture table.

### `DeployBnb`: default treasury and opBNB testnet

`script/DeployBnb.s.sol:DeployBnb` deploys the same `MockUSDC` and `CommitmentEscrow` and grants the same `VERIFIER_ROLE`. Two things differ. `BSC_TREASURY_ADDRESS` is optional, and an empty value makes the deployer the treasury. The script also accepts opBNB testnet (chain id `5611`). It reverts unless the chain id is `97`, `5611`, or local Anvil `31337`, so it refuses BNB Smart Chain mainnet as well.

```sh
export BSC_VERIFIER_ADDRESS=0xYourVerifier
export BSC_DEPLOYER_PRIVATE_KEY=0xYourFundedDeployerKey
forge script script/DeployBnb.s.sol:DeployBnb \
  --rpc-url bsc_testnet \
  --broadcast \
  --slow
```

`bsc_testnet` is a second RPC alias in `foundry.toml`, `https://bsc-testnet-dataseed.bnbchain.org`. It is the same network as `bsc-testnet`, through another public BNB Chain endpoint. opBNB testnet is `--rpc-url opbnb_testnet` and is not the hackathon deploy target.

The faucet routes that do not ask for mainnet BNB, and the deployer and verifier addresses prepared for this deploy, are in [docs/BNB_BANGKOK.md](docs/BNB_BANGKOK.md).

## Verify on BscScan testnet

`BSC_ADMIN_ADDRESS` is the deployer address printed as `admin`. `BSC_USDC_ADDRESS` is the logged `MockUSDC` address. `foundry.toml` sends chain `bsc-testnet` to Etherscan API v2 at `https://api.etherscan.io/v2/api?chainid=97`, with the key in `BSCSCAN_API_KEY`. Etherscan lists chain 97 as a paid-tier chain. Verified source should match optimizer 200 and solc 0.8.24.

The commands are the same after either deploy entry point. `--chain` takes `bsc-testnet` or `97`. The underscore name `bsc_testnet` is an RPC alias only, and `--chain` rejects it. If `DeployBnb` ran with an empty `BSC_TREASURY_ADDRESS`, set `BSC_TREASURY_ADDRESS` to the logged `treasury` address first, because that address is a constructor argument. For opBNB testnet, use `--chain opbnb-testnet`.

```sh
forge verify-contract \
  --chain bsc-testnet \
  --verifier etherscan \
  --watch \
  --constructor-args "$(cast abi-encode "constructor(address,address,address)" "$BSC_USDC_ADDRESS" "$BSC_TREASURY_ADDRESS" "$BSC_ADMIN_ADDRESS")" \
  "$BSC_ESCROW_ADDRESS" \
  src/CommitmentEscrow.sol:CommitmentEscrow

forge verify-contract \
  --chain bsc-testnet \
  --verifier etherscan \
  --watch \
  "$BSC_USDC_ADDRESS" \
  src/MockUSDC.sol:MockUSDC
```

The equivalent explicit verifier URL is:

```sh
forge verify-contract \
  --chain-id 97 \
  --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=97" \
  --etherscan-api-key "$BSCSCAN_API_KEY" \
  --watch \
  --constructor-args "$(cast abi-encode "constructor(address,address,address)" "$BSC_USDC_ADDRESS" "$BSC_TREASURY_ADDRESS" "$BSC_ADMIN_ADDRESS")" \
  "$BSC_ESCROW_ADDRESS" \
  src/CommitmentEscrow.sol:CommitmentEscrow
```

If the API key is refused, verify with Sourcify (no key) or the form at https://testnet.bscscan.com/verifyContract:

```sh
forge verify-contract \
  --chain 97 \
  --verifier sourcify \
  --constructor-args "$(cast abi-encode "constructor(address,address,address)" "$BSC_USDC_ADDRESS" "$BSC_TREASURY_ADDRESS" "$BSC_ADMIN_ADDRESS")" \
  "$BSC_ESCROW_ADDRESS" \
  src/CommitmentEscrow.sol:CommitmentEscrow

forge verify-contract \
  --chain 97 \
  --verifier sourcify \
  "$BSC_USDC_ADDRESS" \
  src/MockUSDC.sol:MockUSDC
```

## Avalanche Fuji

Fuji is the earlier testnet. The walkthrough is [fuji.operatoruplift.com](https://fuji.operatoruplift.com), which opens [/app/fuji](https://fuji.operatoruplift.com/app/fuji) when the public addresses are set. Chain id `43113`. RPC `https://api.avax-test.network/ext/bc/C/rpc`. Test AVAX comes from the [Avalanche faucet](https://build.avax.network/console/primary-network/faucet) or the [Core faucet](https://core.app/tools/testnet-faucet/?subnet=c&token=c).

Both contracts are verified:

- CommitmentEscrow `0xBd806A533435029AF2d5eE514D002367Aa4886a3`  
  https://testnet.snowtrace.io/address/0xBd806A533435029AF2d5eE514D002367Aa4886a3
- MockUSDC `0x70Ef2264cFFAA7DE4e160C3d584DB5B941eE707e`  
  https://testnet.snowtrace.io/address/0x70Ef2264cFFAA7DE4e160C3d584DB5B941eE707e

`FUJI_VERIFIER_PRIVATE_KEY` must be the key for `0x47FEbfc801ccB311C8f1D245296a0F350b728C5A`, the address granted `VERIFIER_ROLE` in [DEPLOYMENTS.md](DEPLOYMENTS.md). The website reads `NEXT_PUBLIC_FUJI_ESCROW_ADDRESS`, `NEXT_PUBLIC_FUJI_USDC_ADDRESS`, `NEXT_PUBLIC_FUJI_CHAIN_ID`, `NEXT_PUBLIC_FUJI_RPC_URL`, `FUJI_ESCROW_ADDRESS`, `FUJI_RPC_URL`, `FUJI_VERIFIER_ADDRESS`, and `FUJI_VERIFIER_PRIVATE_KEY`. `fuji.operatoruplift.com` is a branch domain on the Vercel project `website` (`prj_JjcNxnKQBrZ9l3zcAoA0RQArAdcB`), tracking `cursor/fuji-commitment-deposit-48e4`.

```sh
forge script script/Deploy.s.sol:DeployFuji \
  --rpc-url "$FUJI_RPC_URL" \
  --broadcast \
  --slow
```

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

`foundry.toml` points chain `fuji` at `https://api.routescan.io/v2/network/testnet/evm/43113/etherscan/api`. `SNOWTRACE_API_KEY` is read from the environment. Routescan often accepts any non-empty key. `DeployFuji` reverts on any chain other than `43113` and local Anvil `31337`.
