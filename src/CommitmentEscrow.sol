// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CommitmentEscrow
/// @notice Refundable commitment deposits for one shared goal pool.
///
/// A pool is opened once with a deadline and a required number of proof days.
/// Any number of people (up to {MAX_PARTICIPANTS}) then call {createCommitment}
/// with the same deadline and pull a test USDC deposit into that pool.
///
/// Only {VERIFIER_ROLE} may record a proof. A participant finishes when the
/// number of passed proof days reaches the pool requirement. Days are numbered
/// from 0. Recording a day twice reverts, whether the first verdict passed or
/// not, so a recorded miss cannot be overwritten.
///
/// {settle} is callable by anyone once `block.timestamp >= deadline`. It does
/// not transfer tokens. It writes each pull-payment once:
///
///   - A finisher may claim their full deposit plus a pro-rata share of 96
///     percent of the deposits of people who did not finish.
///   - The other 4 percent of those missed deposits, plus any integer-division
///     dust, accrues to `treasury` and is pulled with {claimTreasury}.
///   - If nobody finished, there is no finisher to receive the 96 percent.
///     Each depositor may claim `amount * 9600 / 10000` of their own deposit,
///     and the remaining 4 percent plus dust goes to the treasury. Funds are
///     not left stuck in the contract.
///
/// A second {settle} reverts. Settlement math is applied once, so a repeat
/// call cannot move funds again. Claims are the same: the first pull pays,
/// the second reverts.
///
/// Proofs may be recorded after the deadline and before settlement, so a
/// verifier that is a block late can still land the last day. They cannot be
/// recorded after settlement.
contract CommitmentEscrow is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    uint256 public constant FINISHER_SHARE_BPS = 9_600;
    uint256 public constant PROTOCOL_SHARE_BPS = 400;
    uint256 public constant BPS = 10_000;
    uint32 public constant MAX_PROOF_DAYS = 366;
    uint256 public constant MAX_PARTICIPANTS = 64;

    IERC20 public immutable usdc;
    address public immutable treasury;

    struct Pool {
        uint64 deadline;
        uint32 requiredProofDays;
        uint256 totalDeposited;
        bool opened;
        bool settled;
        uint256 missedTotal;
        uint256 finisherCount;
        uint256 treasuryAccrued;
        bool treasuryClaimed;
        bool nobodyFinished;
    }

    struct Commitment {
        uint256 amount;
        uint32 proofsPassed;
        uint32 proofsRecorded;
        bool joined;
        bool claimed;
    }

    mapping(bytes32 goalId => Pool) public pools;
    mapping(bytes32 goalId => mapping(address user => Commitment)) public commitments;
    mapping(bytes32 goalId => mapping(address user => uint256)) public claimable;
    mapping(bytes32 goalId => address[]) private _participants;
    mapping(bytes32 goalId => mapping(address user => mapping(uint32 day => bool))) public proofRecorded;
    mapping(bytes32 goalId => mapping(address user => mapping(uint32 day => bytes32))) public verdictHashes;

    error ZeroAddress();
    error ZeroAmount();
    error ZeroDays();
    error TooManyDays();
    error DeadlineInPast();
    error PoolNotOpen();
    error PoolExists();
    error PoolClosed();
    error PoolFull();
    error TermsMismatch();
    error AlreadyJoined();
    error UnknownCommitment();
    error DayOutOfRange();
    error DuplicateProof();
    error TooEarly();
    error AlreadySettled();
    error NotSettled();
    error AlreadyClaimed();
    error TreasuryAlreadyClaimed();

    event PoolOpened(bytes32 indexed goalId, address indexed opener, uint64 deadline, uint32 requiredProofDays);
    event CommitmentCreated(bytes32 indexed goalId, address indexed user, uint256 amount, uint64 deadline);
    event ProofRecorded(
        bytes32 indexed goalId,
        address indexed user,
        uint32 day,
        bytes32 verdictHash,
        bool passed
    );
    event PoolSettled(
        bytes32 indexed goalId,
        uint256 finisherCount,
        uint256 missedTotal,
        uint256 treasuryAmount,
        bool nobodyFinished
    );
    event Claimed(bytes32 indexed goalId, address indexed user, uint256 amount);
    event TreasuryClaimed(bytes32 indexed goalId, address indexed treasury, uint256 amount);

    constructor(address usdc_, address treasury_, address admin) {
        if (usdc_ == address(0) || treasury_ == address(0) || admin == address(0)) revert ZeroAddress();
        usdc = IERC20(usdc_);
        treasury = treasury_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Open a goal pool. The first caller sets the terms. Later deposits
    ///         must pass the same deadline into {createCommitment}.
    /// @param requiredProofDays How many passed proof days finish the commitment.
    ///        This is fixed at pool creation. Days recorded later are `0 .. requiredProofDays-1`.
    function openPool(bytes32 goalId, uint64 deadline, uint32 requiredProofDays) external {
        if (requiredProofDays == 0) revert ZeroDays();
        if (requiredProofDays > MAX_PROOF_DAYS) revert TooManyDays();
        if (deadline <= block.timestamp) revert DeadlineInPast();
        Pool storage pool = pools[goalId];
        if (pool.opened) revert PoolExists();
        pool.opened = true;
        pool.deadline = deadline;
        pool.requiredProofDays = requiredProofDays;
        emit PoolOpened(goalId, msg.sender, deadline, requiredProofDays);
    }

    /// @notice Pull `amount` of the pool token into the goal pool.
    /// @dev `deadline` must equal the deadline stored at {openPool}. It does not
    ///      change the pool. Several addresses may join the same `goalId`.
    ///      One address joins a pool once.
    function createCommitment(bytes32 goalId, uint256 amount, uint64 deadline) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Pool storage pool = pools[goalId];
        if (!pool.opened) revert PoolNotOpen();
        if (pool.settled || block.timestamp >= pool.deadline) revert PoolClosed();
        if (deadline != pool.deadline) revert TermsMismatch();
        Commitment storage commitment = commitments[goalId][msg.sender];
        if (commitment.joined) revert AlreadyJoined();
        if (_participants[goalId].length >= MAX_PARTICIPANTS) revert PoolFull();

        commitment.joined = true;
        commitment.amount = amount;
        pool.totalDeposited += amount;
        _participants[goalId].push(msg.sender);

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit CommitmentCreated(goalId, msg.sender, amount, deadline);
    }

    /// @notice Record one proof day. Caller must hold {VERIFIER_ROLE}.
    /// @param day Zero-based day index. Must be `< requiredProofDays`.
    /// @param verdictHash keccak256 of the canonical verdict JSON. The contract
    ///        stores the hash the verifier submits. It does not re-hash the photo.
    /// @param passed Whether this day counts toward finishing.
    function recordProof(bytes32 goalId, address user, uint32 day, bytes32 verdictHash, bool passed)
        external
        onlyRole(VERIFIER_ROLE)
    {
        Pool storage pool = pools[goalId];
        if (!pool.opened) revert PoolNotOpen();
        if (pool.settled) revert AlreadySettled();
        Commitment storage commitment = commitments[goalId][user];
        if (!commitment.joined) revert UnknownCommitment();
        if (day >= pool.requiredProofDays) revert DayOutOfRange();
        if (proofRecorded[goalId][user][day]) revert DuplicateProof();

        proofRecorded[goalId][user][day] = true;
        verdictHashes[goalId][user][day] = verdictHash;
        commitment.proofsRecorded += 1;
        if (passed) commitment.proofsPassed += 1;
        emit ProofRecorded(goalId, user, day, verdictHash, passed);
    }

    /// @notice Freeze the pool and write pull-payment amounts. Callable by anyone
    ///         after the deadline. A second call reverts and moves nothing.
    function settle(bytes32 goalId) external nonReentrant {
        Pool storage pool = pools[goalId];
        if (!pool.opened) revert PoolNotOpen();
        if (block.timestamp < pool.deadline) revert TooEarly();
        if (pool.settled) revert AlreadySettled();

        address[] storage people = _participants[goalId];
        uint256 count = people.length;
        uint256 finisherDeposits;
        uint256 finisherCount;
        uint256 missed;

        for (uint256 i; i < count; ++i) {
            Commitment storage commitment = commitments[goalId][people[i]];
            if (commitment.proofsPassed >= pool.requiredProofDays) {
                finisherCount += 1;
                finisherDeposits += commitment.amount;
            } else {
                missed += commitment.amount;
            }
        }

        uint256 treasuryAmount;
        if (finisherCount == 0) {
            // No finisher exists to receive the 96 percent share. Return that
            // share to depositors pro-rata (which is each deposit times 9600/10000)
            // and send the rest, including dust, to the treasury.
            pool.nobodyFinished = true;
            pool.missedTotal = pool.totalDeposited;
            uint256 assigned;
            for (uint256 i; i < count; ++i) {
                Commitment storage commitment = commitments[goalId][people[i]];
                uint256 share = commitment.amount * FINISHER_SHARE_BPS / BPS;
                claimable[goalId][people[i]] = share;
                assigned += share;
            }
            treasuryAmount = pool.totalDeposited - assigned;
        } else {
            pool.missedTotal = missed;
            uint256 rewardPool = missed * FINISHER_SHARE_BPS / BPS;
            uint256 assignedRewards;
            for (uint256 i; i < count; ++i) {
                Commitment storage commitment = commitments[goalId][people[i]];
                if (commitment.proofsPassed >= pool.requiredProofDays) {
                    uint256 reward = rewardPool * commitment.amount / finisherDeposits;
                    claimable[goalId][people[i]] = commitment.amount + reward;
                    assignedRewards += reward;
                }
            }
            // Remainder is the 4 percent share plus any pro-rata dust.
            treasuryAmount = missed - assignedRewards;
        }

        pool.finisherCount = finisherCount;
        pool.treasuryAccrued = treasuryAmount;
        pool.settled = true;
        emit PoolSettled(goalId, finisherCount, pool.missedTotal, treasuryAmount, pool.nobodyFinished);
    }

    /// @notice Pull this caller's settlement amount. Finishers receive a refund
    ///         plus their share. People who missed receive zero when somebody
    ///         else finished, or 96 percent of their deposit when nobody finished.
    ///         A second call reverts.
    function claim(bytes32 goalId) external nonReentrant {
        Pool storage pool = pools[goalId];
        if (!pool.settled) revert NotSettled();
        Commitment storage commitment = commitments[goalId][msg.sender];
        if (!commitment.joined) revert UnknownCommitment();
        if (commitment.claimed) revert AlreadyClaimed();
        commitment.claimed = true;
        uint256 amount = claimable[goalId][msg.sender];
        if (amount > 0) usdc.safeTransfer(msg.sender, amount);
        emit Claimed(goalId, msg.sender, amount);
    }

    /// @notice Pull the protocol share to the immutable treasury. Anyone may
    ///         call it. The tokens are never sent to `msg.sender`.
    function claimTreasury(bytes32 goalId) external nonReentrant {
        Pool storage pool = pools[goalId];
        if (!pool.settled) revert NotSettled();
        if (pool.treasuryClaimed) revert TreasuryAlreadyClaimed();
        pool.treasuryClaimed = true;
        uint256 amount = pool.treasuryAccrued;
        if (amount > 0) usdc.safeTransfer(treasury, amount);
        emit TreasuryClaimed(goalId, treasury, amount);
    }

    function participantCount(bytes32 goalId) external view returns (uint256) {
        return _participants[goalId].length;
    }

    function participantAt(bytes32 goalId, uint256 index) external view returns (address) {
        return _participants[goalId][index];
    }

    function isFinisher(bytes32 goalId, address user) external view returns (bool) {
        Pool storage pool = pools[goalId];
        Commitment storage commitment = commitments[goalId][user];
        return commitment.joined && pool.requiredProofDays > 0
            && commitment.proofsPassed >= pool.requiredProofDays;
    }
}
