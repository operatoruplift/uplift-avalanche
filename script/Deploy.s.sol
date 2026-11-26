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
///   <PREFIX>_ADMIN_ADDRESS      escrow admin when the deployer key is unset
///
/// The escrow admin is the address of `<PREFIX>_DEPLOYER_PRIVATE_KEY` when
/// that key is set (`vm.addr`). Foundry 1.10 reverts if the script reads
/// `msg.sender` inside a broadcast while `--sender` is omitted, and older
/// Foundry builds would otherwise record the default sender
/// `0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38` as admin. When the key is
/// unset, admin is `<PREFIX>_ADMIN_ADDRESS` if that is set, and otherwise
/// `msg.sender` (local Anvil `--unlocked --sender`).
///
/// Local Anvil (chain id 31337) is allowed for both entry points. Any other
/// chain id is refused, including BNB Smart Chain mainnet (56) and Avalanche
/// mainnet (43114). MockUSDC is a testnet faucet.
abstract contract DeployCommitment is Script {
    error WrongChain(uint256 got, uint256 expected);
    error AdminMismatch(address configured, address signer);

    function _deploy(string memory prefix, uint256 expectedChainId) internal {
        uint256 chainId = block.chainid;
        if (chainId != expectedChainId && chainId != 31337) {
            console2.log("refusing chain", chainId);
            revert WrongChain(chainId, expectedChainId);
        }

        address treasury = vm.envAddress(string.concat(prefix, "_TREASURY_ADDRESS"));
        address verifier = vm.envAddress(string.concat(prefix, "_VERIFIER_ADDRESS"));
        string memory keyName = string.concat(prefix, "_DEPLOYER_PRIVATE_KEY");
        string memory adminName = string.concat(prefix, "_ADMIN_ADDRESS");
        bool hasKey = _isSet(keyName);
        // Resolve admin before startBroadcast. Reading msg.sender inside the
        // broadcast is what Foundry 1.10 rejects when --sender is omitted.
        address admin = _admin(hasKey, keyName, adminName);

        if (hasKey) {
            vm.startBroadcast(vm.envUint(keyName));
        } else {
            vm.startBroadcast();
        }

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

    function _admin(bool hasKey, string memory keyName, string memory adminName) internal view returns (address) {
        if (hasKey) {
            address signer = vm.addr(vm.envUint(keyName));
            if (_isSet(adminName)) {
                address configured = vm.envAddress(adminName);
                if (configured != signer) revert AdminMismatch(configured, signer);
            }
            return signer;
        }
        if (_isSet(adminName)) return vm.envAddress(adminName);
        return msg.sender;
    }

    function _isSet(string memory name) internal view returns (bool) {
        if (!vm.envExists(name)) return false;
        return bytes(vm.envString(name)).length > 0;
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
///     --rpc-url bsc-testnet --broadcast --sender $BSC_DEPLOYER_ADDRESS --slow
///
/// Reads BSC_TREASURY_ADDRESS, BSC_VERIFIER_ADDRESS, and, when set,
/// BSC_DEPLOYER_PRIVATE_KEY. Admin is vm.addr of that key, or
/// BSC_ADMIN_ADDRESS when the key is unset. Do not point this script at
/// BNB Smart Chain mainnet. MockUSDC is a testnet faucet.
contract DeployBscTestnet is DeployCommitment {
    function run() external {
        _deploy("BSC", 97);
    }
}
