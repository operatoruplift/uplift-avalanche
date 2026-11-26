# Operator Uplift on BNB Chain

Developer Track paste sheet for HackQuest. Paste each section into the matching field. Plain text. The build is BNB Smart Chain testnet only.

## One-liner

Operator Uplift locks a refundable test USDC commitment deposit on BNB Chain testnet and returns it, plus a pro-rata share of missed deposits, when you finish the goal.

## Description

Operator Uplift is an accountability app with more than 2,000 users. People set a goal, put a deposit into a shared pool, and check in with a photo. This repository is the public escrow for that product, now aimed at BNB Smart Chain testnet (chain id 97).

A pool has one deadline and one required number of proof days. Anyone can join until the cap of 64. A verifier writes each day's verdict hash on-chain. After the deadline, anyone can settle. Finishers claim their own deposit back plus a pro-rata share of 96 percent of the deposits from people who missed. The treasury receives 4 percent of those missed deposits. That 4 percent is the protocol revenue. If nobody finishes, each person can still claim 96 percent of their own deposit, so funds are not stuck.

The demo is https://binance.operatoruplift.com. The same contracts are already verified on Avalanche Fuji. This submission uses test USDC. It does not move live funds. Contract addresses for BNB Chain testnet go in DEPLOYMENTS.md when a funded deployer broadcasts script/Deploy.s.sol:DeployBscTestnet. The command is in README.md.

## How it uses BNB Chain

CommitmentEscrow and MockUSDC deploy to BNB Smart Chain testnet, chain id 97, through the public RPC https://data-seed-prebsc-1-s1.bnbchain.org:8545. Gas is test BNB. Deposits, settlement, and claims are transactions on BNB Chain. MetaMask switches to chain id 97. The photo stays off-chain. The contract stores a keccak256 verdict hash and a pass bit, written by an address that holds VERIFIER_ROLE. Source verification targets BscScan (Etherscan API v2, chain id 97), with Sourcify as the no-key fallback. The website reads NEXT_PUBLIC_BSC_ESCROW_ADDRESS and NEXT_PUBLIC_BSC_USDC_ADDRESS, plus the BSC_* server variables, using the same pattern as the existing FUJI_* names.

## Design and usability

The demo is a wallet flow. Connect MetaMask, mint test USDC from the public faucet function, open a pool or join one by goal name, submit one photo, then settle and claim. There is no separate account on the escrow screen. A short deadline lets a judge finish the walkthrough at the booth. Claims are pull payments, so settle and claim are separate transactions and the wallet balance shows the result. The rule for a miss is visible before anyone deposits: finishers share the missed deposits, and the treasury takes 4 percent.

## Scalability

Each goal is its own pool. Settlement loops over that pool only, and the pool holds at most 64 deposits, so gas is bounded. Settle writes the claim amounts once and does not move tokens. Each person pulls their own claim, so one pool does not force every participant into the same transfer. Pools do not share state, so more goals do not make one settlement heavier. The same bytecode runs on BNB Smart Chain testnet and Avalanche Fuji. A later mainnet deployment reuses the contract behind a real stablecoin after review.

## Innovation

Goal apps usually keep the streak in a database, where the operator can edit it. Operator Uplift puts the deposit and the proof hash on BNB Chain. The refund rule is the same for every address in the pool. Finishers receive pro-rata pool rewards from missed deposits, weighted by what they themselves deposited. The protocol takes 4 percent of missed deposits and nothing from a pool where everyone finishes. Photos are not stored on-chain. The chain keeps the hash of the verdict, so the settlement record can be checked without publishing the picture.

## Open source

This repository is MIT licensed and public at https://github.com/operatoruplift/uplift-avalanche. It includes the Solidity contracts, Foundry tests, the BSC testnet deploy script, the Fuji deploy script, and a local Anvil rehearsal that must pass before a broadcast. No private key is committed. .env.example lists every variable name and leaves the secrets empty. The browser app lives in a separate repository. The contract source is written to be verified on BscScan (optimizer 200, solc 0.8.24).

## Integration

The project is integrated with BNB Smart Chain testnet, chain id 97. foundry.toml names the public dataseed and the BscScan verifier. The deploy entry point is script/Deploy.s.sol:DeployBscTestnet, and it reverts on chain id 56 so the faucet token cannot be broadcast to BNB Smart Chain mainnet by that command. The demo at https://binance.operatoruplift.com reads the BSC contract addresses. An off-chain vision review calls recordProof with the verifier key. Avalanche Fuji (chain id 43113) is a second live deployment of the same contracts, already verified on Snowtrace, so the BNB Chain work is a second network rather than a one-off copy.

## Roadmap

Broadcast the BSC testnet deploy, verify the source, and record the addresses. Point binance.operatoruplift.com at those contracts. Invite the existing Operator Uplift community to a public testnet challenge with a short deadline. Add a second verifier key so proof recording is not a single operator. After review, deploy on BNB Chain mainnet with a real stablecoin, keep MockUSDC on testnet, and keep the 4 percent fee and the 64 person cap. Then add team pools and a public finish-rate page.

## Business model

Sustainable protocol revenue is the 4 percent treasury fee on missed deposits. Finishers are not charged a fee on their own deposit. They receive the full deposit back, plus pro-rata pool rewards equal to 96 percent of the missed deposits, weighted by each finisher's deposit. If everyone finishes, the treasury receives nothing from that pool. If nobody finishes, each depositor can claim 96 percent of their own deposit and the treasury still receives 4 percent. The hackathon build collects this in test USDC on BNB Chain testnet. A mainnet version would collect the same fee in a real stablecoin. Optional later revenue is a paid product for private team pools and extra verifier tools. The on-chain fee does not depend on that subscription. Distribution is the existing community of more than 2,000 Operator Uplift users, plus the pools they open with friends.
