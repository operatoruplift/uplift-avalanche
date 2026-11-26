# Operator Uplift on BNB Chain (BNB Bangkok)

Operator Uplift is a commitment-deposit escrow. A person puts test USDC into a shared goal, an AI photo-proof verifier records the verdict on-chain, and settlement returns the deposit to people who finish. This document is the BNB Bangkok hackathon slice of that product.

The product is a commitment contract. It is an accountability deposit on a goal you set for yourself, shared with other people in the same pool.

Submission deadline: 09:00 ICT on Friday 27 November 2026 (HackQuest, BNB Bangkok, Park Hyatt Bangkok). Track: Developer Track. Theme this deployment is built for: on-chain AI agents.

Chain: BNB Smart Chain testnet, chain id `97`. Explorer: https://testnet.bscscan.com. RPC: `https://bsc-testnet-dataseed.bnbchain.org`.

## What is new for this hackathon

The hackathon asks for work built on BNB Chain, and for a clear line between that work and anything that already existed.

| Piece | Already shipped, before BNB Bangkok | Added for this hackathon |
| --- | --- | --- |
| `CommitmentEscrow` and `MockUSDC` (Solidity 0.8.24, OpenZeppelin v5.2.0) | Yes. Published in this repo for Team1 Builders Demo Day. | Reused. Not rewritten. |
| Settlement rules (finisher refund, 96/4 split, pull payments) | Yes. Covered by `forge test`. | Unchanged. |
| Avalanche Fuji deployment and Snowtrace verification | Yes. Addresses in [DEPLOYMENTS.md](../DEPLOYMENTS.md). | Left in place. `foundry.toml` Fuji RPC and Routescan verifier are untouched. |
| Photo-proof AI verifier (vision review, verdict hash, `recordProof`) | Yes. The app is the Operator Uplift website at [fuji.operatoruplift.com](https://fuji.operatoruplift.com). This repo does not contain that app. | No new model and no new website in this change. The same verifier can target BSC once it is pointed at the addresses below. |
| BSC testnet RPC, Etherscan V2 verify entry, opBNB testnet RPC | No. | `foundry.toml` aliases `bsc_testnet` and `opbnb_testnet`. |
| `script/DeployBnb.s.sol` | No. | Deploys `MockUSDC` and `CommitmentEscrow` on chain id 97 (or opBNB 5611, or local Anvil) and grants `VERIFIER_ROLE`. Refuses every other chain, including BNB Smart Chain mainnet. |
| This document | No. | Hackathon architecture, faucet, deploy, and judging notes. |

The new artifact is the BNB Chain deploy path and, once funded, the testnet contracts. The commitment rules and the photo-proof agent are existing product work.

## On-chain AI agents

The verifier is the agent. A person submits a photo for a goal day. The existing review service looks at the photo and produces a verdict. The agent hashes the canonical verdict JSON with keccak256 and calls `recordProof` with `VERIFIER_ROLE`. The contract stores that hash. It does not store the photo, and it does not decide the verdict itself.

The agent cannot move funds. It cannot open a pool, deposit, settle, or claim. Its only write is one proof day, once. A second write for the same day reverts, including an attempt to flip a miss into a pass. After the deadline anyone can settle. Settlement writes pull payments and transfers nothing. The person who finished calls `claim` and receives what settlement already calculated.

That split is the agent boundary: judgment stays off-chain, where a vision model can see a photo, and the commitment stays on-chain, where the role, the hash, and the payout are public.

opBNB testnet (chain id `5611`, RPC `https://opbnb-testnet-rpc.bnbchain.org`, explorer https://opbnb-testnet.bscscan.com) is configured for a later deploy if daily proofs need a cheaper chain. This submission targets BSC testnet.

## Architecture

```
Wallet (Core, MetaMask, or any BNB Chain wallet)
  openPool, createCommitment, settle, claim
        |
        +--> photo proof
               wallet signature over goal, day, challenge, photo
               vision review (existing Operator Uplift reviewer)
               keccak256 of the canonical verdict JSON
               recordProof from the VERIFIER_ROLE key
        |
CommitmentEscrow on BSC testnet (chain id 97)
  stores the verdict hash
  writes pull payments once, at settle
```

`openPool(goalId, deadline, requiredProofDays)` fixes the terms. `createCommitment` pulls test USDC into that pool. Many addresses can join one goal. One address joins once. A pool holds at most 64 deposits, and a goal asks for at most 366 proof days.

`recordProof(goalId, user, day, verdictHash, passed)` is `VERIFIER_ROLE` only. Days are `0 .. requiredProofDays - 1`. Proofs are accepted until settlement, including a few blocks after the deadline.

`settle(goalId)` is callable by anyone once `block.timestamp >= deadline`. It does not transfer tokens.

- A person who finishes (passed days at least `requiredProofDays`) can claim their full deposit back, plus a pro-rata share of 96 percent of the deposits of people who did not finish. The share is weighted by each finisher's own deposit.
- 4 percent of those missed deposits, plus integer-division dust, accrues to the treasury set in the constructor. `claimTreasury` sends that amount to the treasury, never to the caller.
- People who did not finish receive nothing when at least one person finished.
- If nobody finished, each depositor can claim `amount * 9600 / 10000` of their own deposit, and the remaining 4 percent plus dust goes to the treasury. Funds are not stuck.

`MockUSDC` has 6 decimals and a public `mint`. That mint is the testnet stand-in for a stablecoin faucet. Do not deploy it on BNB Smart Chain mainnet, and do not point production accounting at it.

## Deploy on BSC testnet

Requires a deployer funded with tBNB. This repository does not contain a key. Copy `.env.example` to `.env` locally if you want the variable names in one file. Export the variables in your shell. Do not commit `.env`.

```sh
export BSC_VERIFIER_ADDRESS=0xYourVerifier
export BSC_TREASURY_ADDRESS=0xYourTreasury   # optional; defaults to the deployer
export BSC_DEPLOYER_PRIVATE_KEY=0xYourDeployerKey

forge script script/DeployBnb.s.sol:DeployBnb \
  --rpc-url bsc_testnet \
  --broadcast \
  --slow
```

`--rpc-url bsc_testnet` uses `https://bsc-testnet-dataseed.bnbchain.org` from `foundry.toml`. You can pass `$BSC_RPC_URL` instead. The script reads `BSC_DEPLOYER_PRIVATE_KEY` itself. Leave that variable unset only for a local Anvil run with `--unlocked --sender`.

The script checks `block.chainid` and reverts with `NotBnbTestnet` on any chain other than `97`, `5611`, and `31337`.

Verify on BscScan through Etherscan API V2. `BSCSCAN_API_KEY` is a key from etherscan.io. `foundry.toml` already sets the chain id 97 URL.

```sh
forge verify-contract \
  --chain bsc_testnet \
  --watch \
  --constructor-args "$(cast abi-encode "constructor(address,address,address)" "$BSC_USDC_ADDRESS" "$BSC_TREASURY_ADDRESS" "$BSC_ADMIN_ADDRESS")" \
  "$BSC_ESCROW_ADDRESS" \
  src/CommitmentEscrow.sol:CommitmentEscrow

forge verify-contract \
  --chain bsc_testnet \
  --watch \
  "$BSC_USDC_ADDRESS" \
  src/MockUSDC.sol:MockUSDC
```

Compiler settings to match: solc `0.8.24`, optimizer on, 200 runs.

A local rehearsal with no key:

```sh
anvil
export BSC_VERIFIER_ADDRESS=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
unset BSC_DEPLOYER_PRIVATE_KEY
forge script script/DeployBnb.s.sol:DeployBnb \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --unlocked \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

## Faucets

Gas on BSC testnet is tBNB. The commitment token is `MockUSDC`, which anyone can `mint` after it is deployed. You do not need a USDC faucet for the demo. You do need tBNB for the deploy and for later transactions.

- Official web faucet: https://www.bnbchain.org/en/testnet-faucet. One claim per 24 hours. The page asks for a small amount of BNB on BSC mainnet before it sends tBNB.
- Discord: the BNB Chain Discord (https://discord.gg/bnbchain), channel `#testnet-faucet`, or a support ticket in that server. Official docs also list the Telegram bot `@bnbchain_official_bot`. Send the wallet address, for example: "I would like to get tBNB to my wallet 0xYourAddress". The documented limit is 0.3 tBNB per day.

Third-party faucets linked from the BNB Chain docs (QuickNode, Chainstack) often require an account or a mainnet balance. They are optional.

## Deployments

Not deployed. The deployer below has a zero tBNB balance, so the script has not been broadcast. A `forge script` simulation against BSC testnet (chain id 97, no broadcast) succeeded and estimated about 2.7 million gas. At the 0.1 gwei gas price the public RPC reported, the deploy itself is a small fraction of 0.001 tBNB. Fund the deployer with about 0.1 tBNB so the deploy and a short walkthrough have room.

The official faucet at https://www.bnbchain.org/en/testnet-faucet refused this fresh address: it requires at least 0.002 BNB on BSC mainnet. The legacy HTTP faucet is not an open API. Chainstack's faucet requires an API key and a mainnet balance. The Discord channel `#testnet-faucet` and the Telegram bot `@bnbchain_official_bot` are the routes that do not ask for mainnet BNB. Someone has to send that request; this environment cannot.

Treasury defaults to the deployer. The verifier address is already chosen and will receive `VERIFIER_ROLE` at deploy. It does not need tBNB for the deployment. A later `recordProof` does.

| | Address | Deploy tx | Block | BscScan | Verified |
| --- | --- | --- | --- | --- | --- |
| Deployer / admin | `0x7d72f42fa79C36212a471133869d55dCeDdac0Bb` | needs ~0.1 tBNB | | https://testnet.bscscan.com/address/0x7d72f42fa79C36212a471133869d55dCeDdac0Bb | |
| Treasury | same as deployer | | | | |
| Verifier (`VERIFIER_ROLE`) | `0xdAA493AA1380d24DEe3960A7816D20fE5Da11248` | | | https://testnet.bscscan.com/address/0xdAA493AA1380d24DEe3960A7816D20fE5Da11248 | |
| MockUSDC | not deployed | | | | |
| CommitmentEscrow | not deployed | | | | |
| `grantRole(VERIFIER_ROLE)` | | not sent | | | |

Network: BSC testnet, chain id `97`. RPC `https://bsc-testnet-dataseed.bnbchain.org`. Explorer https://testnet.bscscan.com.

opBNB testnet is configured and not deployed. The deployer and verifier keys are testnet-only. They are kept in a gitignored local file and are not in this repository.

## Judging criteria

Developer Track criteria from the BNB Chain event notes: design and usability, scalability, innovation, open source, and integration, plus a roadmap and a business model.

### Design and usability

One pool, one deposit call, no separate account. The first wallet opens the pool. A second wallet joins by using the same goal id and the same deadline. The existing Fuji walkthrough at [fuji.operatoruplift.com/app/fuji](https://fuji.operatoruplift.com/app/fuji) is the same sequence this BSC deployment is meant to serve: mint test USDC, deposit, submit one photo, wait for the deadline, settle, claim. The screen defaults the deadline to a few minutes so a live walkthrough can finish. On BSC the wallet is any EVM wallet pointed at chain id 97.

### Scalability

Settlement walks the participant list once. The list is capped at 64, and proof days are capped at 366, so the cost does not grow with use of the protocol, only with the size of one pool. Claims are pull payments: settle does not fan out token transfers, and a second settle reverts. Each proof is one transaction from the verifier. BSC testnet fees make a daily proof cheap enough to record. opBNB testnet is already in `foundry.toml` if a pool ever needs a higher-throughput chain. This submission does not claim a load test.

### Innovation

The new piece relative to a plain escrow is the agent boundary. An AI reviewer is the only account that can write a proof, and what it writes is a hash of its verdict, not a balance change. People who finish get their deposit back. People who do not finish leave the committed amount in the pool, and finishers share 96 percent of that amount. The contract enforces the split once. The agent cannot rewrite a day and cannot pay itself.

### Open source

This repository is MIT (`LICENSE`). Contracts, tests, the Fuji deploy, and this BNB deploy script are in the public git history. `forge test` is the check. Verification on BscScan publishes the same solc 0.8.24 bytecode. No key is committed. `.env` and `.local/` are gitignored.

### Integration

BNB Chain is the deployment target (BSC testnet, chain id 97). The escrow uses OpenZeppelin AccessControl, ReentrancyGuard, and SafeERC20. The token interface is ERC-20, 6 decimals, so a later mainnet deploy can point at a real stablecoin instead of `MockUSDC`. The photo-proof agent is the existing Operator Uplift reviewer: it already speaks `recordProof`. Pointing it at BSC is an address and RPC change, not a new protocol. Sponsor oracles and launchpads are not part of this commitment flow, and this submission does not claim those integrations.

### Roadmap and business model

Roadmap:

1. BSC testnet contracts, verified, with `VERIFIER_ROLE` granted. The deploy script and chain config are in this change. Broadcasting waits on tBNB for the deployer in the table above.
2. Point the existing web walkthrough at the BSC addresses (`NEXT_PUBLIC` escrow, test USDC, chain id `97`, and a server-side verifier key). The website is a separate repository.
3. Optional opBNB testnet deploy from the same script if proof volume wants lower fees.
4. Mainnet only with a real stablecoin. `MockUSDC` stays on testnet. A dedicated verifier key, separate from the admin, matches the Fuji deployment.

Business model: the treasury receives 4 percent of deposits from people who did not finish, plus rounding dust. That is the fee for running the verifier and the pool. Finishers receive their own deposit back in full, plus the finisher share. When nobody finishes, each person still receives 96 percent of their own deposit. The product earns a fee on unmet commitments. It does not take a position on the outcome, and it does not hold customer funds past settlement: every unit is assigned to a claim or to the treasury.

Community: pools are shared. Anyone can open a goal, anyone can join until the pool is full, and anyone can settle after the deadline. The rules are the source in this repo.
