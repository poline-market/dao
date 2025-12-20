// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IStakingManager.sol";

/**
 * @title OracleVoting
 * @notice Voting system for resolving prediction market events
 * @dev Features:
 *      - Stake-weighted voting (YES/NO)
 *      - Consensus-based resolution
 *      - Automatic slashing of minority voters
 *      - Deadline-based resolution
 */
contract OracleVoting is AccessControl, ReentrancyGuard {
    bytes32 public constant EVENT_CREATOR_ROLE = keccak256("EVENT_CREATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    IStakingManager public immutable stakingManager;

    /// @notice Slashing percentage for wrong votes (in basis points, 10000 = 100%)
    uint256 public slashPercentage = 1000; // 10% default

    /// @notice Minimum voting period
    uint256 public minimumVotingPeriod = 1 days;

    /// @notice Quorum percentage (basis points) of oracle stake needed
    uint256 public quorumPercentage = 3000; // 30%

    enum EventStatus {
        Pending,
        Voting,
        Resolved,
        Disputed,
        Cancelled
    }

    struct OracleEvent {
        bytes32 id;
        string description;
        uint256 createdAt;
        uint256 votingDeadline;
        uint256 yesVotes;       // Stake-weighted YES votes
        uint256 noVotes;        // Stake-weighted NO votes
        EventStatus status;
        bool outcome;           // true = YES, false = NO
        address creator;
    }

    struct Vote {
        bool hasVoted;
        bool vote;              // true = YES, false = NO
        uint256 weight;         // Voting weight at time of vote
    }

    /// @notice Event ID => Event data
    mapping(bytes32 => OracleEvent) public events;

    /// @notice Event ID => voter => vote info
    mapping(bytes32 => mapping(address => Vote)) public votes;

    /// @notice Event ID => list of voters
    mapping(bytes32 => address[]) public eventVoters;

    /// @notice All event IDs
    bytes32[] public allEventIds;

    // Events
    event EventCreated(bytes32 indexed eventId, string description, uint256 votingDeadline);
    event VoteCast(bytes32 indexed eventId, address indexed voter, bool vote, uint256 weight);
    event EventResolved(bytes32 indexed eventId, bool outcome, uint256 yesVotes, uint256 noVotes);
    event VoterSlashed(bytes32 indexed eventId, address indexed voter, uint256 amount);
    event EventDisputed(bytes32 indexed eventId, address indexed disputer);
    event EventCancelled(bytes32 indexed eventId);
    event ParametersUpdated(uint256 slashPct, uint256 minPeriod, uint256 quorumPct);

    // Errors
    error EventAlreadyExists(bytes32 eventId);
    error EventNotFound(bytes32 eventId);
    error InvalidStatus(EventStatus current, EventStatus required);
    error VotingPeriodTooShort(uint256 provided, uint256 minimum);
    error VotingNotOpen(bytes32 eventId);
    error VotingEnded(bytes32 eventId);
    error AlreadyVoted(bytes32 eventId, address voter);
    error NotOracle(address account);
    error QuorumNotReached(uint256 required, uint256 actual);
    error VotingStillActive(bytes32 eventId, uint256 deadline);

    constructor(address _stakingManager, address admin) {
        stakingManager = IStakingManager(_stakingManager);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EVENT_CREATOR_ROLE, admin);
        _grantRole(RESOLVER_ROLE, admin);
    }

    /**
     * @notice Create a new event to be resolved
     * @param description Event description
     * @param votingPeriod Time window for voting (seconds)
     * @return eventId The new event ID
     */
    function createEvent(
        string calldata description,
        uint256 votingPeriod
    ) external onlyRole(EVENT_CREATOR_ROLE) returns (bytes32 eventId) {
        if (votingPeriod < minimumVotingPeriod) {
            revert VotingPeriodTooShort(votingPeriod, minimumVotingPeriod);
        }

        eventId = keccak256(abi.encodePacked(description, block.timestamp, msg.sender));
        
        if (events[eventId].createdAt != 0) {
            revert EventAlreadyExists(eventId);
        }

        uint256 deadline = block.timestamp + votingPeriod;

        events[eventId] = OracleEvent({
            id: eventId,
            description: description,
            createdAt: block.timestamp,
            votingDeadline: deadline,
            yesVotes: 0,
            noVotes: 0,
            status: EventStatus.Voting,
            outcome: false,
            creator: msg.sender
        });

        allEventIds.push(eventId);

        emit EventCreated(eventId, description, deadline);
    }

    /**
     * @notice Cast a vote on an event
     * @param eventId Event to vote on
     * @param vote true = YES, false = NO
     */
    function castVote(bytes32 eventId, bool vote) external nonReentrant {
        OracleEvent storage evt = events[eventId];
        
        if (evt.createdAt == 0) revert EventNotFound(eventId);
        if (evt.status != EventStatus.Voting) {
            revert InvalidStatus(evt.status, EventStatus.Voting);
        }
        if (block.timestamp > evt.votingDeadline) {
            revert VotingEnded(eventId);
        }

        // Must be oracle
        if (!stakingManager.isOracle(msg.sender)) {
            revert NotOracle(msg.sender);
        }

        Vote storage voterInfo = votes[eventId][msg.sender];
        if (voterInfo.hasVoted) {
            revert AlreadyVoted(eventId, msg.sender);
        }

        // Get voting weight from stake
        uint256 weight = stakingManager.getStake(msg.sender);

        voterInfo.hasVoted = true;
        voterInfo.vote = vote;
        voterInfo.weight = weight;

        if (vote) {
            evt.yesVotes += weight;
        } else {
            evt.noVotes += weight;
        }

        eventVoters[eventId].push(msg.sender);

        emit VoteCast(eventId, msg.sender, vote, weight);
    }

    /**
     * @notice Resolve an event after voting ends
     * @param eventId Event to resolve
     */
    function resolveEvent(bytes32 eventId) external onlyRole(RESOLVER_ROLE) nonReentrant {
        OracleEvent storage evt = events[eventId];
        
        if (evt.createdAt == 0) revert EventNotFound(eventId);
        if (evt.status != EventStatus.Voting) {
            revert InvalidStatus(evt.status, EventStatus.Voting);
        }
        if (block.timestamp <= evt.votingDeadline) {
            revert VotingStillActive(eventId, evt.votingDeadline);
        }

        // Check quorum
        uint256 totalVotes = evt.yesVotes + evt.noVotes;
        uint256 totalStaked = stakingManager.totalStaked();
        uint256 requiredQuorum = (totalStaked * quorumPercentage) / 10000;
        
        if (totalVotes < requiredQuorum) {
            revert QuorumNotReached(requiredQuorum, totalVotes);
        }

        // Determine outcome
        bool outcome = evt.yesVotes > evt.noVotes;
        evt.outcome = outcome;
        evt.status = EventStatus.Resolved;

        // Slash minority voters
        _slashMinorityVoters(eventId, outcome);

        emit EventResolved(eventId, outcome, evt.yesVotes, evt.noVotes);
    }

    /**
     * @notice Internal: slash voters who voted against consensus
     */
    function _slashMinorityVoters(bytes32 eventId, bool winningVote) internal {
        address[] storage voters = eventVoters[eventId];
        
        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            Vote storage v = votes[eventId][voter];
            
            if (v.vote != winningVote) {
                uint256 slashAmount = (v.weight * slashPercentage) / 10000;
                if (slashAmount > 0) {
                    stakingManager.slashStake(voter, slashAmount, "Voted against consensus");
                    emit VoterSlashed(eventId, voter, slashAmount);
                }
            }
        }
    }

    /**
     * @notice Mark event as disputed (called by DisputeResolution)
     * @param eventId Event to dispute
     */
    function markDisputed(bytes32 eventId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OracleEvent storage evt = events[eventId];
        if (evt.createdAt == 0) revert EventNotFound(eventId);
        
        evt.status = EventStatus.Disputed;
        emit EventDisputed(eventId, msg.sender);
    }

    /**
     * @notice Cancel an event
     * @param eventId Event to cancel
     */
    function cancelEvent(bytes32 eventId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OracleEvent storage evt = events[eventId];
        if (evt.createdAt == 0) revert EventNotFound(eventId);
        
        evt.status = EventStatus.Cancelled;
        emit EventCancelled(eventId);
    }

    /**
     * @notice Update voting parameters
     */
    function updateParameters(
        uint256 newSlashPct,
        uint256 newMinPeriod,
        uint256 newQuorumPct
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        slashPercentage = newSlashPct;
        minimumVotingPeriod = newMinPeriod;
        quorumPercentage = newQuorumPct;
        emit ParametersUpdated(newSlashPct, newMinPeriod, newQuorumPct);
    }

    // ============ View Functions ============

    function getEvent(bytes32 eventId) external view returns (OracleEvent memory) {
        return events[eventId];
    }

    function getEventCount() external view returns (uint256) {
        return allEventIds.length;
    }

    function getVoters(bytes32 eventId) external view returns (address[] memory) {
        return eventVoters[eventId];
    }

    function getVote(bytes32 eventId, address voter) external view returns (Vote memory) {
        return votes[eventId][voter];
    }

    function hasVoted(bytes32 eventId, address voter) external view returns (bool) {
        return votes[eventId][voter].hasVoted;
    }
}
