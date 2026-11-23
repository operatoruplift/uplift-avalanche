// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {CommitmentEscrow} from "../src/CommitmentEscrow.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract CommitmentEscrowTest is Test {
    uint256 internal constant ALICE_START = 1_000_000e6;
    uint256 internal constant BOB_START = 1_000_000e6;

    MockUSDC internal usdc;
    CommitmentEscrow internal escrow;
    address internal treasury = makeAddr("treasury");
    address internal admin = makeAddr("admin");
    address internal verifier = makeAddr("verifier");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    bytes32 internal goal = keccak256("demo-day");
    uint64 internal deadline;

    event ProofRecorded(
        bytes32 indexed goalId,
        address indexed user,
        uint32 day,
        bytes32 verdictHash,
        bool passed
    );

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new CommitmentEscrow(address(usdc), treasury, admin);
        bytes32 verifierRole = escrow.VERIFIER_ROLE();
        vm.prank(admin);
        escrow.grantRole(verifierRole, verifier);
        usdc.mint(alice, ALICE_START);
        usdc.mint(bob, BOB_START);
        vm.prank(alice);
        usdc.approve(address(escrow), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(escrow), type(uint256).max);
        deadline = uint64(block.timestamp + 7 days);
    }

    function test_mockUsdc_sixDecimalsAndPublicMint() public {
        assertEq(usdc.decimals(), 6);
        usdc.mint(alice, 1);
        assertEq(usdc.balanceOf(alice), ALICE_START + 1);
    }

    function test_happyPath_finisherRefundAndMissedSplit() public {
        uint256 aliceDeposit = 100e6;
        uint256 bobDeposit = 50e6;
        _open(2);
        _join(alice, aliceDeposit);
        _join(bob, bobDeposit);

        bytes32 verdict = keccak256("alice-day");
        _pass(alice, 0, verdict);
        _pass(alice, 1, keccak256("alice-day-2"));

        vm.warp(deadline);
        escrow.settle(goal);

        escrow.claimTreasury(goal);
        vm.prank(alice);
        escrow.claim(goal);
        vm.prank(bob);
        escrow.claim(goal);

        // Bob missed 50 USDC. 96 percent (48) is added to Alice's full refund.
        // 4 percent (2) goes to the treasury.
        assertEq(usdc.balanceOf(alice), ALICE_START - aliceDeposit + aliceDeposit + 48e6);
        assertEq(usdc.balanceOf(bob), BOB_START - bobDeposit);
        assertEq(usdc.balanceOf(treasury), 2e6);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_miss_unfinishedCallerReceivesNothingWhenSomeoneFinishes() public {
        _open(1);
        _join(alice, 80e6);
        _join(bob, 20e6);
        _pass(alice, 0, keccak256("ok"));
        vm.warp(deadline);
        escrow.settle(goal);

        assertEq(escrow.claimable(goal, bob), 0);
        assertEq(escrow.claimable(goal, alice), 80e6 + 19.2e6);
        (, , , , , uint256 missed, , uint256 treasuryAccrued, , bool nobody) = escrow.pools(goal);
        assertEq(missed, 20e6);
        assertEq(treasuryAccrued, 0.8e6);
        assertFalse(nobody);
    }

    function test_everyoneMisses_returnsNinetySixPercentToDepositors() public {
        uint256 aliceDeposit = 100e6;
        uint256 bobDeposit = 40e6;
        _open(1);
        _join(alice, aliceDeposit);
        _join(bob, bobDeposit);
        vm.warp(deadline);
        escrow.settle(goal);

        (, , , , , uint256 missed, uint256 finishers, uint256 treasuryAccrued, , bool nobody) = escrow.pools(goal);
        assertTrue(nobody);
        assertEq(finishers, 0);
        assertEq(missed, aliceDeposit + bobDeposit);
        assertEq(escrow.claimable(goal, alice), 96e6);
        assertEq(escrow.claimable(goal, bob), 38.4e6);
        assertEq(treasuryAccrued, 5.6e6);
        assertEq(escrow.claimable(goal, alice) + escrow.claimable(goal, bob) + treasuryAccrued, aliceDeposit + bobDeposit);

        vm.prank(alice);
        escrow.claim(goal);
        vm.prank(bob);
        escrow.claim(goal);
        escrow.claimTreasury(goal);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(usdc.balanceOf(treasury), 5.6e6);
    }

    function test_settleTwice_reverts() public {
        _open(1);
        _join(alice, 10e6);
        vm.warp(deadline);
        escrow.settle(goal);
        vm.expectRevert(CommitmentEscrow.AlreadySettled.selector);
        escrow.settle(goal);
        assertEq(usdc.balanceOf(address(escrow)), 10e6);
    }

    function test_settleBeforeDeadline_reverts() public {
        _open(1);
        _join(alice, 10e6);
        _pass(alice, 0, keccak256("early"));
        vm.expectRevert(CommitmentEscrow.TooEarly.selector);
        escrow.settle(goal);
    }

    function test_recordProof_nonVerifierReverts() public {
        _open(1);
        _join(alice, 10e6);
        bytes32 verifierRole = escrow.VERIFIER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, verifierRole)
        );
        vm.prank(alice);
        escrow.recordProof(goal, alice, 0, keccak256("nope"), true);
        assertEq(escrow.proofRecorded(goal, alice, 0), false);
    }

    function test_zeroAmount_reverts() public {
        _open(1);
        vm.prank(alice);
        vm.expectRevert(CommitmentEscrow.ZeroAmount.selector);
        escrow.createCommitment(goal, 0, deadline);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_duplicateProofDay_reverts() public {
        _open(1);
        _join(alice, 10e6);
        _pass(alice, 0, keccak256("first"));
        vm.expectRevert(CommitmentEscrow.DuplicateProof.selector);
        vm.prank(verifier);
        escrow.recordProof(goal, alice, 0, keccak256("second"), false);
        (uint256 amount, uint32 passed, uint32 recorded,,) = escrow.commitments(goal, alice);
        assertEq(amount, 10e6);
        assertEq(passed, 1);
        assertEq(recorded, 1);
    }

    function test_recordProof_emitsVerdict() public {
        _open(1);
        _join(alice, 10e6);
        bytes32 verdict = keccak256("verdict-json");
        vm.expectEmit(true, true, false, true, address(escrow));
        emit ProofRecorded(goal, alice, 0, verdict, true);
        vm.prank(verifier);
        escrow.recordProof(goal, alice, 0, verdict, true);
    }

    function test_claimTwice_reverts() public {
        _open(1);
        _join(alice, 10e6);
        _pass(alice, 0, keccak256("done"));
        vm.warp(deadline);
        escrow.settle(goal);
        vm.prank(alice);
        escrow.claim(goal);
        vm.prank(alice);
        vm.expectRevert(CommitmentEscrow.AlreadyClaimed.selector);
        escrow.claim(goal);
    }

    function testFuzz_splitConservesDeposits(uint128 rawAlice, uint128 rawBob, bool aliceFinishes, bool bobFinishes)
        public
    {
        uint256 aliceAmount = bound(uint256(rawAlice), 1, 1_000_000e6);
        uint256 bobAmount = bound(uint256(rawBob), 1, 1_000_000e6);
        _open(1);
        _join(alice, aliceAmount);
        _join(bob, bobAmount);
        if (aliceFinishes) _pass(alice, 0, keccak256("alice"));
        if (bobFinishes) _pass(bob, 0, keccak256("bob"));

        vm.warp(deadline);
        escrow.settle(goal);

        uint256 aliceDue = escrow.claimable(goal, alice);
        uint256 bobDue = escrow.claimable(goal, bob);
        (, , , , , uint256 missed, uint256 finishers, uint256 treasuryAccrued,, bool nobody) = escrow.pools(goal);
        assertEq(aliceDue + bobDue + treasuryAccrued, aliceAmount + bobAmount);

        if (aliceFinishes || bobFinishes) {
            assertFalse(nobody);
            assertEq(missed, (aliceFinishes ? 0 : aliceAmount) + (bobFinishes ? 0 : bobAmount));
            assertGe(treasuryAccrued, missed * escrow.PROTOCOL_SHARE_BPS() / escrow.BPS());
            if (aliceFinishes) assertGe(aliceDue, aliceAmount);
            else assertEq(aliceDue, 0);
            if (bobFinishes) assertGe(bobDue, bobAmount);
            else assertEq(bobDue, 0);
            assertEq(finishers, (aliceFinishes ? 1 : 0) + (bobFinishes ? 1 : 0));
        } else {
            assertTrue(nobody);
            assertEq(finishers, 0);
            assertEq(aliceDue, aliceAmount * escrow.FINISHER_SHARE_BPS() / escrow.BPS());
            assertEq(bobDue, bobAmount * escrow.FINISHER_SHARE_BPS() / escrow.BPS());
            assertGe(treasuryAccrued, (aliceAmount + bobAmount) * escrow.PROTOCOL_SHARE_BPS() / escrow.BPS());
        }

        vm.prank(alice);
        escrow.claim(goal);
        vm.prank(bob);
        escrow.claim(goal);
        escrow.claimTreasury(goal);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function _open(uint32 daysRequired) internal {
        escrow.openPool(goal, deadline, daysRequired);
    }

    function _join(address user, uint256 amount) internal {
        vm.prank(user);
        escrow.createCommitment(goal, amount, deadline);
    }

    function _pass(address user, uint32 day, bytes32 verdict) internal {
        vm.prank(verifier);
        escrow.recordProof(goal, user, day, verdict, true);
    }
}
