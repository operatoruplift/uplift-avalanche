// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployBnb} from "../script/DeployBnb.s.sol";
import {CommitmentEscrow} from "../src/CommitmentEscrow.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @notice Runs the BSC deploy script in-process and checks the role grant.
///         The unlocked Anvil path is exercised with `forge script`, where
///         `msg.sender` is the `--sender`. These tests use a throwaway key.
contract DeployBnbTest is Test {
    address internal treasury = makeAddr("bnb-treasury");
    address internal verifier = makeAddr("bnb-verifier");
    uint256 internal deployerKey = 0xBEEF;

    function test_deployScript_onBscTestnet_grantsVerifier() public {
        _prepareEnv(97, treasury, deployerKey);
        DeployBnb script = new DeployBnb();
        script.run();
        _assertDeploy(script, vm.addr(deployerKey), treasury);
    }

    function test_deployScript_onOpBnbTestnet_defaultsTreasuryToAdmin() public {
        uint256 key = 0xCAFE;
        _prepareEnv(5611, address(0), key);
        DeployBnb script = new DeployBnb();
        script.run();

        address admin = vm.addr(key);
        assertEq(script.adminAddress(), admin);
        assertEq(script.treasuryAddress(), admin);
        CommitmentEscrow deployed = CommitmentEscrow(script.escrowAddress());
        assertEq(deployed.treasury(), admin);
        assertEq(address(deployed.usdc()), script.usdcAddress());
        assertTrue(deployed.hasRole(deployed.VERIFIER_ROLE(), verifier));
        assertTrue(deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_deployScript_refusesBscMainnet() public {
        _prepareEnv(56, treasury, deployerKey);
        DeployBnb script = new DeployBnb();
        vm.expectRevert(abi.encodeWithSelector(DeployBnb.NotBnbTestnet.selector, uint256(56)));
        script.run();
    }

    function test_deployScript_refusesFuji() public {
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
        assertEq(script.adminAddress(), admin);
        assertEq(script.treasuryAddress(), expectedTreasury);
        assertEq(token.decimals(), 6);
        assertEq(address(deployed.usdc()), script.usdcAddress());
        assertEq(deployed.treasury(), expectedTreasury);
        assertTrue(deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(deployed.hasRole(deployed.VERIFIER_ROLE(), verifier));
    }

    function test_deployScript_mockUsdcMintStaysPublic() public {
        _prepareEnv(97, treasury, deployerKey);
        DeployBnb script = new DeployBnb();
        script.run();
        MockUSDC token = MockUSDC(script.usdcAddress());
        token.mint(verifier, 1);
        assertEq(token.balanceOf(verifier), 1);
    }
}
