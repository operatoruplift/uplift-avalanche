// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CommitmentEscrow} from "../src/CommitmentEscrow.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @notice Deploy MockUSDC and CommitmentEscrow on a BNB Chain testnet.
///
/// The deployer key is read from BSC_DEPLOYER_PRIVATE_KEY when that variable
/// is set and non-empty. When it is unset, forge uses `--unlocked --sender`
/// (local Anvil). This script never generates a key.
///
/// Required environment:
///   BSC_VERIFIER_ADDRESS   receives VERIFIER_ROLE
/// Optional:
///   BSC_DEPLOYER_PRIVATE_KEY
///   BSC_TREASURY_ADDRESS   protocol share recipient; defaults to the deployer
///
/// MockUSDC has a public mint. It is a testnet faucet. This script reverts
/// unless the chain id is BSC testnet (97), opBNB testnet (5611), or local
/// Anvil (31337). Do not point it at BNB Smart Chain mainnet.
///
/// BSC testnet (chain id 97, funded deployer key):
///   forge script script/DeployBnb.s.sol:DeployBnb \
///     --rpc-url bsc_testnet --broadcast --slow
///
/// The `--private-key` flag and `vm.envUint` both read the same env var.
/// Prefer the env var inside this script so the key is not also required as a
/// process argument. Passing `--private-key` is still supported: if both are
/// set they must be the same key, and this script broadcasts with the env var.
contract DeployBnb is Script {
    error NotBnbTestnet(uint256 chainId);

    /// @dev Set during `run` so a forge test can read the deployment. Forge
    ///      script output for operators is the `console2` lines below.
    address public usdcAddress;
    address public escrowAddress;
    address public adminAddress;
    address public treasuryAddress;

    function run() external {
        uint256 chainId = block.chainid;
        if (chainId != 97 && chainId != 5611 && chainId != 31337) revert NotBnbTestnet(chainId);

        address verifier = vm.envAddress("BSC_VERIFIER_ADDRESS");
        address treasury = _optionalAddress("BSC_TREASURY_ADDRESS");

        // The admin has to be the broadcast signer. With a key, that signer is
        // the key's address. `forge script` does not make `msg.sender` that
        // address inside a unit test, so derive it from the key. With no key,
        // `forge script --unlocked --sender` sets `msg.sender` to the sender.
        address admin;
        if (_hasKey()) {
            uint256 key = vm.envUint("BSC_DEPLOYER_PRIVATE_KEY");
            admin = vm.addr(key);
            vm.startBroadcast(key);
        } else {
            vm.startBroadcast();
            admin = msg.sender;
        }
        if (treasury == address(0)) treasury = admin;
        MockUSDC usdc = new MockUSDC();
        CommitmentEscrow escrow = new CommitmentEscrow(address(usdc), treasury, admin);
        escrow.grantRole(escrow.VERIFIER_ROLE(), verifier);
        vm.stopBroadcast();

        usdcAddress = address(usdc);
        escrowAddress = address(escrow);
        adminAddress = admin;
        treasuryAddress = treasury;

        console2.log("chainId", chainId);
        console2.log("MockUSDC", address(usdc));
        console2.log("CommitmentEscrow", address(escrow));
        console2.log("admin", admin);
        console2.log("treasury", treasury);
        console2.log("verifier", verifier);
    }

    function _optionalAddress(string memory name) internal view returns (address) {
        if (!vm.envExists(name)) return address(0);
        string memory raw = vm.envString(name);
        if (bytes(raw).length == 0) return address(0);
        return vm.parseAddress(raw);
    }

    function _hasKey() internal view returns (bool) {
        if (!vm.envExists("BSC_DEPLOYER_PRIVATE_KEY")) return false;
        return bytes(vm.envString("BSC_DEPLOYER_PRIVATE_KEY")).length > 0;
    }
}
