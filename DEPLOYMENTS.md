# Deployment records

Same contracts on two testnets. BNB Smart Chain testnet is the hackathon network. Avalanche Fuji is the earlier deployment and is already verified.

Compiler for both: solc `v0.8.24+commit.e11b9ed9`, optimizer on, 200 runs.

## BNB Smart Chain testnet (chain id 97)

Status: pending a funded deployer key. This repository does not contain a key, and this checkout did not broadcast.

A testnet-only deployer and verifier were prepared for this deployment. Their addresses, and the test BNB the deployer still needs, are in the deployment table in [docs/BNB_BANGKOK.md](docs/BNB_BANGKOK.md#deployments).

RPC: `https://data-seed-prebsc-1-s1.bnbchain.org:8545`  
Foundry alias: `bsc-testnet`  
Explorer: https://testnet.bscscan.com

When a funded key is available, export `BSC_TREASURY_ADDRESS`, `BSC_VERIFIER_ADDRESS`, and `BSC_DEPLOYER_PRIVATE_KEY`, then run:

```sh
forge script script/Deploy.s.sol:DeployBscTestnet \
  --rpc-url bsc-testnet \
  --broadcast \
  --slow
```

`script/DeployBnb.s.sol:DeployBnb` is the other entry point for the same deployment. It takes `--rpc-url bsc_testnet` and uses the deployer as the treasury when `BSC_TREASURY_ADDRESS` is empty. Use one of the two.

Either script prints `MockUSDC`, `CommitmentEscrow`, `admin`, `treasury`, and `verifier`. Record those here, commit the receipts from `broadcast/Deploy.s.sol/97/` or `broadcast/DeployBnb.s.sol/97/` (the gitignore already keeps both directories), and verify with the commands in the README. Fill in:

### MockUSDC

- Address: pending
- Deploy tx: pending
- BscScan: pending
- Verified: pending

### CommitmentEscrow

- Address: pending
- Deploy tx: pending
- Constructor args: token = MockUSDC address, treasury = `BSC_TREASURY_ADDRESS` (the deployer when `DeployBnb` ran with it empty), admin = deployer
- BscScan: pending
- Verified: pending

### Role grant

- `grantRole(VERIFIER_ROLE, BSC_VERIFIER_ADDRESS)` is in both deploy scripts
- Tx: pending

After the broadcast, set these on the website host for https://binance.operatoruplift.com:

- `NEXT_PUBLIC_BSC_ESCROW_ADDRESS`
- `NEXT_PUBLIC_BSC_USDC_ADDRESS`
- `NEXT_PUBLIC_BSC_CHAIN_ID=97`
- `NEXT_PUBLIC_BSC_RPC_URL=https://data-seed-prebsc-1-s1.bnbchain.org:8545`
- `BSC_ESCROW_ADDRESS` (same escrow address, server side)
- `BSC_RPC_URL`
- `BSC_VERIFIER_ADDRESS`
- `BSC_VERIFIER_PRIVATE_KEY` (server only, never `NEXT_PUBLIC_`)

## Avalanche Fuji (chain id 43113)

Deployed and verified on Fuji testnet on 23 Nov 2026, about 11:57 PM ICT (Asia/Saigon).

RPC: `https://api.avax-test.network/ext/bc/C/rpc`

Deployer / treasury / admin: `0x6707fA33c6aF7F10AD229239C466b72322c9F435`  
Verifier (granted `VERIFIER_ROLE`): `0x47FEbfc801ccB311C8f1D245296a0F350b728C5A`

### MockUSDC

- Address: `0x70Ef2264cFFAA7DE4e160C3d584DB5B941eE707e`
- Deploy tx: `0x6960236dfd6336b34ccc4feaccf32c15c615fe2f0365c6f4e4e5579cddd8911a`
- Block: 61527709
- Snowtrace: https://testnet.snowtrace.io/address/0x70Ef2264cFFAA7DE4e160C3d584DB5B941eE707e
- Verified: yes

### CommitmentEscrow

- Address: `0xBd806A533435029AF2d5eE514D002367Aa4886a3`
- Deploy tx: `0xca8c20996c8038831494c1c0114c9d35c2b6ed7a59aafa53ac0a0397c53000b0`
- Constructor args: token `0x70Ef2264cFFAA7DE4e160C3d584DB5B941eE707e`, treasury and admin both `0x6707fA33c6aF7F10AD229239C466b72322c9F435`
- Block: 61527711
- Snowtrace: https://testnet.snowtrace.io/address/0xBd806A533435029AF2d5eE514D002367Aa4886a3
- Verified: yes

### Role grant

- `grantRole(VERIFIER_ROLE, 0x47FEbfc801ccB311C8f1D245296a0F350b728C5A)`
- Tx: `0x3be90c13dbdc18ae02a2d4f2df0cee522d4732afff18a1bf52c6c3b0e6059e9f`
- Block: 61527713

### Smoke test

Ran on Fuji right after deploy, about 11:58 PM to 12:01 AM ICT (Asia/Saigon). Goal id `keccak256("fuji-smoke-2026-11-23")` = `0xca5867083fdd6b4753ba32e3226671edfc478f34c1bca74b75a5f9b61c038e72`. Pool: 1 proof day, deadline unix `1795453294`, deposit 1,000,000 units (1 test USDC, 6 decimals). Verdict hash `keccak256("fuji-smoke-passed")`, day 0, passed.

| Step | Tx hash | Result |
| --- | --- | --- |
| mint (deployer, 1 test USDC) | `0xa260effb04aac78cac5fbb970f8977ba233e4a8f3101b3596e2bf95403bbc45b` | ok |
| openPool | `0x66eee494383bea74803f91f4e5489f221705eace5e29cec9321278cc1468531c` | ok |
| approve | `0x100ae94b4acde0ccef1ee85336d37832d4a4dec733ef64b4f886d9f03dfba281` | ok |
| createCommitment | `0x71a2ddacbb697ef7939f5859099345aede924434d97ae83171e4aa44d909660c` | ok; deployer USDC balance then 0 |
| recordProof (verifier, passed) | `0x8bc3387533ac91cbe2802244e83982787c0971bd21e98ddfd80e737d7e33b56a` | ok; finisher |
| settle | `0xbcc26a8049f9ff907f67795a602ae2439bd821d328ba208c3ca94079a3a46961` | ok, after deadline |
| claim | `0x36639bd9ac27e2aefd8dbefbff58d2e6a5626099266051f53cb47598e1cbae04` | ok; deployer USDC balance 1,000,000 (full refund) |

Outcome: success. The finisher got the full test deposit back. Settle and claim both ran.
