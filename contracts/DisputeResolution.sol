// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IStakingManager.sol";
import "./interfaces/IOracleVoting.sol";

/**
 * @title DisputeResolution
 * @notice Court system for challenging oracle decisions (Kleros-style)
 * @dev Features:
 *      - Challenge resolved events with extra stake
 *      - Multiple escalation rounds
 *      - Juror selection based on reputation
 *      - Losers lose stake
 */
contract DisputeResolution is AccessControl, ReentrancyGuard {
    bytes32 public constant DISPUTE_ADMIN_ROLE = keccak256("DISPUTE_ADMIN_ROLE");

    IStakingManager public immutable stakingManager;
    IOracleVoting public immutable oracleVoting;

    /// @notice Minimum stake to open dispute
    uint256 public disputeStake = 200 ether;

    /// @notice Stake multiplier per escalation round (150 = 1.5x)
    uint256 public escalationMultiplier = 150; // 1.5x

    /// @notice Voting period for disputes
    uint256 public disputeVotingPeriod = 3 days;

    /// @notice Maximum escalation rounds
    uint256 public maxRounds = 3;

    enum DisputeStatus {
        Open,
        Voting,
        Resolved,
        Escalated,
        Cancelled
    }

    struct Dispute {
        bytes32 id;
        bytes32 eventId;
        address challenger;
        uint256 challengeStake;
        uint256 round;
        uint256 createdAt;
        uint256 votingDeadline;
        uint256 yesVotes;       // Votes to overturn
        uint256 noVotes;        // Votes to uphold
        DisputeStatus status;
        bool overturned;        // Final outcome: was original decision overturned?
    }

    struct DisputeVote {
        bool hasVoted;
        bool vote;              // true = overturn, false = uphold
        uint256 weight;
    }

    /// @notice Dispute ID => Dispute data
    mapping(bytes32 => Dispute) public disputes;

    /// @notice Event ID => current dispute ID (if any)
    mapping(bytes32 => bytes32) public eventDisputes;

    /// @notice Dispute ID => voter => vote
    mapping(bytes32 => mapping(address => DisputeVote)) public disputeVotes;

    /// @notice Dispute ID => list of voters
    mapping(bytes32 => address[]) public disputeVoters;

    /// @notice All dispute IDs
    bytes32[] public allDisputeIds;

    // Events
    event DisputeOpened(
        bytes32 indexed disputeId,
        bytes32 indexed eventId,
        address indexed challenger,
        uint256 stake,
        uint256 round
    );
    event DisputeVoteCast(
        bytes32 indexed disputeId,
        address indexed voter,
        bool vote,
        uint256 weight
    );
    event DisputeResolved(
        bytes32 indexed disputeId,
        bool overturned,
        uint256 forOverturn,
        uint256 againstOverturn
    );
    event DisputeEscalated(bytes32 indexed disputeId, uint256 newRound, uint256 newStake);
    event StakeSlashed(bytes32 indexed disputeId, address indexed user, uint256 amount);
    event ParametersUpdated(uint256 stake, uint256 multiplier, uint256 period, uint256 maxRnd);

    // Errors
    error EventNotResolved(bytes32 eventId);
    error DisputeAlreadyExists(bytes32 eventId);
    error DisputeNotFound(bytes32 disputeId);
    error InvalidStatus(DisputeStatus current, DisputeStatus required);
    error InsufficientStake(uint256 required, uint256 provided);
    error VotingNotOpen(bytes32 disputeId);
    error VotingEnded(bytes32 disputeId);
    error AlreadyVoted(bytes32 disputeId, address voter);
    error NotOracle(address account);
    error VotingStillActive(bytes32 disputeId, uint256 deadline);
    error MaxRoundsReached(uint256 round);
    error DisputeNotResolved(bytes32 disputeId);

    constructor(
        address _stakingManager,
        address _oracleVoting,
        address admin
    ) {
        stakingManager = IStakingManager(_stakingManager);
        oracleVoting = IOracleVoting(_oracleVoting);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DISPUTE_ADMIN_ROLE, admin);
    }

    /**
     * @notice Open a dispute on a resolved event
     * @param eventId Event to challenge
     * @return disputeId The new dispute ID
     */
    function openDispute(bytes32 eventId) external nonReentrant returns (bytes32 disputeId) {
        // Verify event is resolved
        IOracleVoting.OracleEvent memory evt = oracleVoting.getEvent(eventId);
        if (evt.status != IOracleVoting.EventStatus.Resolved) {
            revert EventNotResolved(eventId);
        }

        // Check no active dispute
        if (eventDisputes[eventId] != bytes32(0)) {
            bytes32 existingId = eventDisputes[eventId];
            Dispute storage existing = disputes[existingId];
            if (existing.status == DisputeStatus.Open || existing.status == DisputeStatus.Voting) {
                revert DisputeAlreadyExists(eventId);
            }
        }

        // Verify challenger has enough stake
        uint256 stake = stakingManager.getStake(msg.sender);
        if (stake < disputeStake) {
            revert InsufficientStake(disputeStake, stake);
        }

        disputeId = keccak256(abi.encodePacked(eventId, block.timestamp, msg.sender));

        disputes[disputeId] = Dispute({
            id: disputeId,
            eventId: eventId,
            challenger: msg.sender,
            challengeStake: disputeStake,
            round: 1,
            createdAt: block.timestamp,
            votingDeadline: block.timestamp + disputeVotingPeriod,
            yesVotes: 0,
            noVotes: 0,
            status: DisputeStatus.Voting,
            overturned: false
        });

        eventDisputes[eventId] = disputeId;
        allDisputeIds.push(disputeId);

        // Mark event as disputed
        oracleVoting.markDisputed(eventId);

        emit DisputeOpened(disputeId, eventId, msg.sender, disputeStake, 1);
    }

    /**
     * @notice Cast vote on a dispute
     * @param disputeId Dispute to vote on
     * @param vote true = overturn original decision, false = uphold
     */
    function castVote(bytes32 disputeId, bool vote) external nonReentrant {
        Dispute storage disp = disputes[disputeId];
        
        if (disp.createdAt == 0) revert DisputeNotFound(disputeId);
        if (disp.status != DisputeStatus.Voting) {
            revert InvalidStatus(disp.status, DisputeStatus.Voting);
        }
        if (block.timestamp > disp.votingDeadline) {
            revert VotingEnded(disputeId);
        }

        // Must be oracle
        if (!stakingManager.isOracle(msg.sender)) {
            revert NotOracle(msg.sender);
        }

        DisputeVote storage v = disputeVotes[disputeId][msg.sender];
        if (v.hasVoted) {
            revert AlreadyVoted(disputeId, msg.sender);
        }

        uint256 weight = stakingManager.getStake(msg.sender);

        v.hasVoted = true;
        v.vote = vote;
        v.weight = weight;

        if (vote) {
            disp.yesVotes += weight;
        } else {
            disp.noVotes += weight;
        }

        disputeVoters[disputeId].push(msg.sender);

        emit DisputeVoteCast(disputeId, msg.sender, vote, weight);
    }

    /**
     * @notice Resolve a dispute after voting ends
     * @param disputeId Dispute to resolve
     */
    function resolveDispute(bytes32 disputeId) external onlyRole(DISPUTE_ADMIN_ROLE) nonReentrant {
        Dispute storage disp = disputes[disputeId];
        
        if (disp.createdAt == 0) revert DisputeNotFound(disputeId);
        if (disp.status != DisputeStatus.Voting) {
            revert InvalidStatus(disp.status, DisputeStatus.Voting);
        }
        if (block.timestamp <= disp.votingDeadline) {
            revert VotingStillActive(disputeId, disp.votingDeadline);
        }

        bool overturned = disp.yesVotes > disp.noVotes;
        disp.overturned = overturned;
        disp.status = DisputeStatus.Resolved;

        // Slash losing side
        _slashLosers(disputeId, overturned);

        emit DisputeResolved(disputeId, overturned, disp.yesVotes, disp.noVotes);
    }

    /**
     * @notice Escalate dispute to higher round
     * @param disputeId Dispute to escalate
     */
    function escalateDispute(bytes32 disputeId) external nonReentrant {
        Dispute storage disp = disputes[disputeId];
        
        if (disp.createdAt == 0) revert DisputeNotFound(disputeId);
        if (disp.status != DisputeStatus.Resolved) {
            revert DisputeNotResolved(disputeId);
        }
        if (disp.round >= maxRounds) {
            revert MaxRoundsReached(disp.round);
        }

        // Calculate new stake requirement
        uint256 newStake = (disp.challengeStake * escalationMultiplier) / 100;

        // Verify escalator has enough stake
        uint256 stake = stakingManager.getStake(msg.sender);
        if (stake < newStake) {
            revert InsufficientStake(newStake, stake);
        }

        disp.round += 1;
        disp.challengeStake = newStake;
        disp.votingDeadline = block.timestamp + disputeVotingPeriod;
        disp.yesVotes = 0;
        disp.noVotes = 0;
        disp.status = DisputeStatus.Voting;

        // Clear previous votes
        delete disputeVoters[disputeId];

        emit DisputeEscalated(disputeId, disp.round, newStake);
    }

    /**
     * @notice Internal: slash voters on losing side
     */
    function _slashLosers(bytes32 disputeId, bool winningVote) internal {
        address[] storage voters = disputeVoters[disputeId];
        Dispute storage disp = disputes[disputeId];
        
        // Calculate slash percentage based on round (higher rounds = higher stakes)
        uint256 slashPct = 1000 + (disp.round * 500); // 10% + 5% per round

        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            DisputeVote storage v = disputeVotes[disputeId][voter];
            
            if (v.vote != winningVote) {
                uint256 slashAmount = (v.weight * slashPct) / 10000;
                if (slashAmount > 0) {
                    stakingManager.slashStake(voter, slashAmount, "Lost dispute vote");
                    emit StakeSlashed(disputeId, voter, slashAmount);
                }
            }
        }

        // If challenger lost (uphold original), slash challenger extra
        if (!winningVote) {
            uint256 challengerSlash = disp.challengeStake / 2;
            stakingManager.slashStake(disp.challenger, challengerSlash, "Lost dispute challenge");
            emit StakeSlashed(disputeId, disp.challenger, challengerSlash);
        }
    }

    /**
     * @notice Update dispute parameters
     */
    function updateParameters(
        uint256 newStake,
        uint256 newMultiplier,
        uint256 newPeriod,
        uint256 newMaxRounds
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        disputeStake = newStake;
        escalationMultiplier = newMultiplier;
        disputeVotingPeriod = newPeriod;
        maxRounds = newMaxRounds;
        emit ParametersUpdated(newStake, newMultiplier, newPeriod, newMaxRounds);
    }

    // ============ View Functions ============

    function getDispute(bytes32 disputeId) external view returns (Dispute memory) {
        return disputes[disputeId];
    }

    function getDisputeForEvent(bytes32 eventId) external view returns (bytes32) {
        return eventDisputes[eventId];
    }

    function getDisputeCount() external view returns (uint256) {
        return allDisputeIds.length;
    }

    function getVoters(bytes32 disputeId) external view returns (address[] memory) {
        return disputeVoters[disputeId];
    }
}
