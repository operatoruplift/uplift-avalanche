// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CommitmentEscrow} from "../src/CommitmentEscrow.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @notice Shared deploy for MockUSDC and CommitmentEscrow.
///
/// The deployer key is read from `<PREFIX>_DEPLOYER_PRIVATE_KEY` when that
/// variable is set and non-empty. When it is unset, forge uses
/// `--unlocked --sender` (local Anvil). This script never generates a key.
///
/// Required environment, with PREFIX set to FUJI or BSC:
///   <PREFIX>_TREASURY_ADDRESS   protocol share recipient
///   <PREFIX>_VERIFIER_ADDRESS   receives VERIFIER_ROLE
/// Optional:
///   <PREFIX>_DEPLOYER_PRIVATE_KEY
///
/// Local Anvil (chain id 31337) is allowed for both entry points. Any other
/// chain id is refused, including BNB Smart Chain mainnet (56) and Avalanche
/// mainnet (43114). MockUSDC is a testnet faucet.
abstract contract DeployCommitment is Script {
    error WrongChain(uint256 got, uint256 expected);

    function _deploy(string memory prefix, uint256 expectedChainId) internal {
        uint256 chainId = block.chainid;
        if (chainId != expectedChainId && chainId != 31337) {
            console2.log("refusing chain", chainId);
            revert WrongChain(chainId, expectedChainId);
        }

        address treasury = vm.envAddress(string.concat(prefix, "_TREASURY_ADDRESS"));
        address verifier = vm.envAddress(string.concat(prefix, "_VERIFIER_ADDRESS"));
        string memory keyName = string.concat(prefix, "_DEPLOYER_PRIVATE_KEY");

        if (_hasKey(keyName)) {
            vm.startBroadcast(vm.envUint(keyName));
        } else {
            vm.startBroadcast();
        }

        address admin = msg.sender;
        MockUSDC usdc = new MockUSDC();
        CommitmentEscrow escrow = new CommitmentEscrow(address(usdc), treasury, admin);
        escrow.grantRole(escrow.VERIFIER_ROLE(), verifier);
        vm.stopBroadcast();

        console2.log("chainId", chainId);
        console2.log("MockUSDC", address(usdc));
        console2.log("CommitmentEscrow", address(escrow));
        console2.log("admin", admin);
        console2.log("treasury", treasury);
        console2.log("verifier", verifier);
    }

    function _hasKey(string memory keyName) internal view returns (bool) {
        if (!vm.envExists(keyName)) return false;
        return bytes(vm.envString(keyName)).length > 0;
    }
}

/// @notice Avalanche Fuji testnet (chain id 43113).
///
///   forge script script/Deploy.s.sol:DeployFuji \
///     --rpc-url "$FUJI_RPC_URL" --broadcast --slow
///
/// The script reads FUJI_DEPLOYER_PRIVATE_KEY from the environment when it is
/// non-empty. Passing `--private-key` is still supported. If both are set they
/// must be the same key, and this script broadcasts with the env var.
contract DeployFuji is DeployCommitment {
    function run() external {
        _deploy("FUJI", 43113);
    }
}

/// @notice BNB Smart Chain testnet (chain id 97).
///
///   forge script script/Deploy.s.sol:DeployBscTestnet \
///     --rpc-url bsc-testnet --broadcast --slow
///
/// Reads BSC_TREASURY_ADDRESS, BSC_VERIFIER_ADDRESS, and, when set,
/// BSC_DEPLOYER_PRIVATE_KEY. Do not point this script at BNB Smart Chain
/// mainnet. MockUSDC is a testnet faucet.
contract DeployBscTestnet is DeployCommitment {
    function run() external {
        _deploy("BSC", 97);
    }
}
