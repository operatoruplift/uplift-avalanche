// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CommitmentEscrow} from "../src/CommitmentEscrow.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @notice Deploy MockUSDC and CommitmentEscrow.
///
/// The deployer key is read from FUJI_DEPLOYER_PRIVATE_KEY when that variable
/// is set and non-empty. When it is unset, forge uses `--unlocked --sender`
/// (local Anvil). This script never generates a key.
///
/// Required environment:
///   FUJI_TREASURY_ADDRESS   protocol share recipient
///   FUJI_VERIFIER_ADDRESS   receives VERIFIER_ROLE
/// Optional:
///   FUJI_DEPLOYER_PRIVATE_KEY
///
/// Fuji testnet (chain id 43113, funded deployer key). Do not point this
/// script at Avalanche mainnet. MockUSDC is a testnet faucet.
///   forge script script/Deploy.s.sol:DeployFuji \
///     --rpc-url "$FUJI_RPC_URL" --broadcast --private-key "$FUJI_DEPLOYER_PRIVATE_KEY" --slow
///
/// The `--private-key` flag and `vm.envUint` both read the same env var.
/// Prefer the env var inside this script so the key is not also required as a
/// process argument. Passing `--private-key` is still supported: if both are
/// set they must be the same key, and this script broadcasts with the env var.
contract DeployFuji is Script {
    function run() external {
        address treasury = vm.envAddress("FUJI_TREASURY_ADDRESS");
        address verifier = vm.envAddress("FUJI_VERIFIER_ADDRESS");

        if (_hasKey()) {
            vm.startBroadcast(vm.envUint("FUJI_DEPLOYER_PRIVATE_KEY"));
        } else {
            vm.startBroadcast();
        }

        address admin = msg.sender;
        MockUSDC usdc = new MockUSDC();
        CommitmentEscrow escrow = new CommitmentEscrow(address(usdc), treasury, admin);
        escrow.grantRole(escrow.VERIFIER_ROLE(), verifier);
        vm.stopBroadcast();

        console2.log("MockUSDC", address(usdc));
        console2.log("CommitmentEscrow", address(escrow));
        console2.log("admin", admin);
        console2.log("treasury", treasury);
        console2.log("verifier", verifier);
    }

    function _hasKey() internal view returns (bool) {
        if (!vm.envExists("FUJI_DEPLOYER_PRIVATE_KEY")) return false;
        return bytes(vm.envString("FUJI_DEPLOYER_PRIVATE_KEY")).length > 0;
    }
}
