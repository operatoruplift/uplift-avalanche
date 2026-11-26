// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployBnb} from "../script/DeployBnb.s.sol";
import {CommitmentEscrow} from "../src/CommitmentEscrow.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @notice Runs the BSC deploy script in-process and checks the role grant.
///         The unlocked Anvil path is exercised with `forge script`, where
///         `msg.sender` is the `--sender`. These checks use a throwaway key.
///
///         The script reads its inputs from the process environment, and
///         `vm.setEnv` changes that environment for every test in the run.
///         Forge runs test functions in parallel, so two functions that set
///         different values overwrite each other. The opBNB check uses another
///         key and an empty treasury, and as a test of its own it failed
///         intermittently, including once in CI on main. Every scenario
///         therefore runs, in order, inside the one test function below. Keep
///         it that way: a second test function that calls `vm.setEnv` with a
///         BSC_ name brings the race back.
contract DeployBnbTest is Test {
    address internal treasury = makeAddr("bnb-treasury");
    address internal verifier = makeAddr("bnb-verifier");
    uint256 internal deployerKey = 0xBEEF;

    function test_deployScript_scenariosInOrder() public {
        _onBscTestnet_grantsVerifier();
        _onOpBnbTestnet_defaultsTreasuryToAdmin();
        _refusesBscMainnet();
        _refusesFuji();
        _mockUsdcMintStaysPublic();
    }

    function _onBscTestnet_grantsVerifier() internal {
        _prepareEnv(97, treasury, deployerKey);
        DeployBnb script = new DeployBnb();
        script.run();
        _assertDeploy(script, vm.addr(deployerKey), treasury);
    }

    function _onOpBnbTestnet_defaultsTreasuryToAdmin() internal {
        uint256 key = 0xCAFE;
        _prepareEnv(5611, address(0), key);
        DeployBnb script = new DeployBnb();
        script.run();

        address admin = vm.addr(key);
        assertEq(script.adminAddress(), admin, "opBNB: admin is the key's address");
        assertEq(script.treasuryAddress(), admin, "opBNB: treasury defaults to the admin");
        CommitmentEscrow deployed = CommitmentEscrow(script.escrowAddress());
        assertEq(deployed.treasury(), admin, "opBNB: escrow treasury");
        assertEq(address(deployed.usdc()), script.usdcAddress(), "opBNB: escrow token");
        assertTrue(deployed.hasRole(deployed.VERIFIER_ROLE(), verifier), "opBNB: verifier role");
        assertTrue(deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), admin), "opBNB: admin role");
    }

    function _refusesBscMainnet() internal {
        _prepareEnv(56, treasury, deployerKey);
        DeployBnb script = new DeployBnb();
        vm.expectRevert(abi.encodeWithSelector(DeployBnb.NotBnbTestnet.selector, uint256(56)));
        script.run();
    }

    function _refusesFuji() internal {
        _prepareEnv(43113, treasury, deployerKey);
        DeployBnb script = new DeployBnb();
        vm.expectRevert(abi.encodeWithSelector(DeployBnb.NotBnbTestnet.selector, uint256(43113)));
        script.run();
    }

    function _prepareEnv(uint256 chainId, address treasury_, uint256 key) internal {
        vm.chainId(chainId);
        vm.setEnv("BSC_DEPLOYER_PRIVATE_KEY", vm.toString(key));
        vm.setEnv("BSC_VERIFIER_ADDRESS", vm.toString(verifier));
        vm.setEnv("BSC_TREASURY_ADDRESS", treasury_ == address(0) ? "" : vm.toString(treasury_));
    }

    function _assertDeploy(DeployBnb script, address admin, address expectedTreasury) internal view {
        MockUSDC token = MockUSDC(script.usdcAddress());
        CommitmentEscrow deployed = CommitmentEscrow(script.escrowAddress());
        assertEq(script.adminAddress(), admin, "BSC: admin is the key's address");
        assertEq(script.treasuryAddress(), expectedTreasury, "BSC: treasury from the environment");
        assertEq(token.decimals(), 6, "BSC: token decimals");
        assertEq(address(deployed.usdc()), script.usdcAddress(), "BSC: escrow token");
        assertEq(deployed.treasury(), expectedTreasury, "BSC: escrow treasury");
        assertTrue(deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), admin), "BSC: admin role");
        assertTrue(deployed.hasRole(deployed.VERIFIER_ROLE(), verifier), "BSC: verifier role");
    }

    function _mockUsdcMintStaysPublic() internal {
        _prepareEnv(97, treasury, deployerKey);
        DeployBnb script = new DeployBnb();
        script.run();
        MockUSDC token = MockUSDC(script.usdcAddress());
        token.mint(verifier, 1);
        assertEq(token.balanceOf(verifier), 1, "public mint");
    }
}
