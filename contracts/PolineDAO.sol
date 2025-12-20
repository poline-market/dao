// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IPolineToken.sol";
import "./interfaces/ICircleRegistry.sol";
import "./interfaces/IStakingManager.sol";
import "./interfaces/IOracleVoting.sol";

/**
 * @title PolineDAO
 * @notice Main DAO orchestrator for Poline prediction market
 * @dev Features:
 *      - Proposal creation by circles
 *      - Snapshot-based voting
 *      - Automatic proposal execution
 *      - Parameter governance
 */
contract PolineDAO is AccessControl, ReentrancyGuard {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    IPolineToken public immutable polineToken;
    ICircleRegistry public immutable circleRegistry;
    IStakingManager public immutable stakingManager;
    IOracleVoting public immutable oracleVoting;

    /// @notice Minimum voting period for proposals
    uint256 public minVotingPeriod = 3 days;

    /// @notice Quorum percentage (basis points)
    uint256 public quorumPercentage = 2000; // 20%

    /// @notice Proposal threshold (tokens needed to propose)
    uint256 public proposalThreshold = 100 ether;

    /// @notice Timelock delay after voting passes
    uint256 public timelockDelay = 1 days;

    enum ProposalStatus {
        Pending,
        Active,
        Cancelled,
        Defeated,
        Succeeded,
        Queued,
        Executed
    }

    enum ProposalType {
        MarketRules, // Types of markets allowed
        TrustedSources, // Approved data sources
        AMMParameters, // AMM configuration
        Fees, // Fee structure
        DisputePolicy, // Dispute parameters
        CircleMembership, // Circle member changes
        ParameterChange // DAO parameter changes
    }

    struct Proposal {
        bytes32 id;
        address proposer;
        bytes32 circleId; // Circle that proposed
        ProposalType propType;
        string description;
        bytes callData; // Encoded function call
        address target; // Target contract
        uint256 createdAt;
        uint256 votingStarts;
        uint256 votingEnds;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        ProposalStatus status;
        uint256 executionTime; // When can be executed (after timelock)
    }

    struct Vote {
        bool hasVoted;
        uint8 support; // 0 = against, 1 = for, 2 = abstain
        uint256 weight;
    }

    /// @notice Proposal ID => proposal data
    mapping(bytes32 => Proposal) public proposals;

    /// @notice Proposal ID => voter => vote
    mapping(bytes32 => mapping(address => Vote)) public votes;

    /// @notice All proposal IDs
    bytes32[] public allProposalIds;

    // Events
    event ProposalCreated(
        bytes32 indexed proposalId,
        address indexed proposer,
        bytes32 indexed circleId,
        ProposalType propType,
        string description,
        uint256 votingStarts,
        uint256 votingEnds
    );
    event VoteCast(
        bytes32 indexed proposalId,
        address indexed voter,
        uint8 support,
        uint256 weight
    );
    event ProposalQueued(bytes32 indexed proposalId, uint256 executionTime);
    event ProposalExecuted(bytes32 indexed proposalId);
    event ProposalCancelled(bytes32 indexed proposalId);
    event ParametersUpdated(
        uint256 minPeriod,
        uint256 quorum,
        uint256 threshold,
        uint256 timelock
    );

    // Errors
    error ProposalNotFound(bytes32 proposalId);
    error InvalidStatus(ProposalStatus current, ProposalStatus required);
    error InsufficientVotingPower(uint256 required, uint256 actual);
    error NotCircleMember(bytes32 circleId, address account);
    error CircleNotAuthorized(bytes32 circleId, ProposalType propType);
    error VotingNotActive(bytes32 proposalId);
    error AlreadyVoted(bytes32 proposalId, address voter);
    error QuorumNotReached(bytes32 proposalId);
    error TimelockNotPassed(uint256 executionTime, uint256 currentTime);
    error ExecutionFailed(bytes32 proposalId);

    constructor(
        address _token,
        address _circleRegistry,
        address _stakingManager,
        address _oracleVoting,
        address admin
    ) {
        polineToken = IPolineToken(_token);
        circleRegistry = ICircleRegistry(_circleRegistry);
        stakingManager = IStakingManager(_stakingManager);
        oracleVoting = IOracleVoting(_oracleVoting);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PROPOSER_ROLE, admin);
        _grantRole(EXECUTOR_ROLE, admin);
    }

    /**
     * @notice Allow contract to receive POL (for treasury from PolinePurchase)
     */
    receive() external payable {}

    /**
     * @notice Create a new proposal
     * @param circleId Circle creating the proposal
     * @param propType Type of proposal
     * @param description Human-readable description
     * @param target Contract to call if passed
     * @param callData Encoded function call
     * @param votingPeriod Duration for voting
     * @return proposalId The new proposal ID
     */
    function propose(
        bytes32 circleId,
        ProposalType propType,
        string calldata description,
        address target,
        bytes calldata callData,
        uint256 votingPeriod
    ) external nonReentrant returns (bytes32 proposalId) {
        // Check proposer is circle member
        if (!circleRegistry.isMember(circleId, msg.sender)) {
            revert NotCircleMember(circleId, msg.sender);
        }

        // Check circle has authority for this type
        uint256 requiredScope = _proposalTypeToScope(propType);
        if (!circleRegistry.hasScope(circleId, requiredScope)) {
            revert CircleNotAuthorized(circleId, propType);
        }

        // Check proposer voting power
        uint256 votingPower = polineToken.getVotes(msg.sender);
        if (votingPower < proposalThreshold) {
            revert InsufficientVotingPower(proposalThreshold, votingPower);
        }

        if (votingPeriod < minVotingPeriod) {
            votingPeriod = minVotingPeriod;
        }

        proposalId = keccak256(
            abi.encodePacked(
                description,
                target,
                callData,
                block.timestamp,
                msg.sender
            )
        );

        uint256 votingStarts = block.timestamp;
        uint256 votingEnds = votingStarts + votingPeriod;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            circleId: circleId,
            propType: propType,
            description: description,
            callData: callData,
            target: target,
            createdAt: block.timestamp,
            votingStarts: votingStarts,
            votingEnds: votingEnds,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            status: ProposalStatus.Active,
            executionTime: 0
        });

        allProposalIds.push(proposalId);

        emit ProposalCreated(
            proposalId,
            msg.sender,
            circleId,
            propType,
            description,
            votingStarts,
            votingEnds
        );
    }

    /**
     * @notice Cast vote on a proposal
     * @param proposalId Proposal to vote on
     * @param support 0 = against, 1 = for, 2 = abstain
     */
    function castVote(bytes32 proposalId, uint8 support) external nonReentrant {
        Proposal storage prop = proposals[proposalId];

        if (prop.createdAt == 0) revert ProposalNotFound(proposalId);
        if (prop.status != ProposalStatus.Active) {
            revert InvalidStatus(prop.status, ProposalStatus.Active);
        }
        if (
            block.timestamp < prop.votingStarts ||
            block.timestamp > prop.votingEnds
        ) {
            revert VotingNotActive(proposalId);
        }

        Vote storage v = votes[proposalId][msg.sender];
        if (v.hasVoted) {
            revert AlreadyVoted(proposalId, msg.sender);
        }

        uint256 weight = polineToken.getVotes(msg.sender);

        v.hasVoted = true;
        v.support = support;
        v.weight = weight;

        if (support == 0) {
            prop.againstVotes += weight;
        } else if (support == 1) {
            prop.forVotes += weight;
        } else {
            prop.abstainVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Queue a successful proposal for execution
     * @param proposalId Proposal to queue
     */
    function queue(bytes32 proposalId) external nonReentrant {
        Proposal storage prop = proposals[proposalId];

        if (prop.createdAt == 0) revert ProposalNotFound(proposalId);
        if (prop.status != ProposalStatus.Active) {
            revert InvalidStatus(prop.status, ProposalStatus.Active);
        }
        if (block.timestamp <= prop.votingEnds) {
            revert VotingNotActive(proposalId);
        }

        // Check quorum
        uint256 totalVotes = prop.forVotes +
            prop.againstVotes +
            prop.abstainVotes;
        uint256 totalSupply = stakingManager.totalStaked();
        uint256 requiredQuorum = (totalSupply * quorumPercentage) / 10000;

        if (totalVotes < requiredQuorum) {
            prop.status = ProposalStatus.Defeated;
            revert QuorumNotReached(proposalId);
        }

        // Check if passed
        if (prop.forVotes <= prop.againstVotes) {
            prop.status = ProposalStatus.Defeated;
            return;
        }

        prop.status = ProposalStatus.Queued;
        prop.executionTime = block.timestamp + timelockDelay;

        emit ProposalQueued(proposalId, prop.executionTime);
    }

    /**
     * @notice Execute a queued proposal
     * @param proposalId Proposal to execute
     */
    function execute(
        bytes32 proposalId
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        Proposal storage prop = proposals[proposalId];

        if (prop.createdAt == 0) revert ProposalNotFound(proposalId);
        if (prop.status != ProposalStatus.Queued) {
            revert InvalidStatus(prop.status, ProposalStatus.Queued);
        }
        if (block.timestamp < prop.executionTime) {
            revert TimelockNotPassed(prop.executionTime, block.timestamp);
        }

        prop.status = ProposalStatus.Executed;

        // Execute the call
        (bool success, ) = prop.target.call(prop.callData);
        if (!success) {
            revert ExecutionFailed(proposalId);
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal (by proposer or admin)
     * @param proposalId Proposal to cancel
     */
    function cancel(bytes32 proposalId) external {
        Proposal storage prop = proposals[proposalId];

        if (prop.createdAt == 0) revert ProposalNotFound(proposalId);

        require(
            msg.sender == prop.proposer ||
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized"
        );

        prop.status = ProposalStatus.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    /**
     * @notice Update DAO parameters
     */
    function updateParameters(
        uint256 newMinPeriod,
        uint256 newQuorum,
        uint256 newThreshold,
        uint256 newTimelock
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minVotingPeriod = newMinPeriod;
        quorumPercentage = newQuorum;
        proposalThreshold = newThreshold;
        timelockDelay = newTimelock;
        emit ParametersUpdated(
            newMinPeriod,
            newQuorum,
            newThreshold,
            newTimelock
        );
    }

    // ============ Internal Functions ============

    /**
     * @notice Map proposal type to required circle scope
     */
    function _proposalTypeToScope(
        ProposalType propType
    ) internal pure returns (uint256) {
        if (propType == ProposalType.MarketRules) return 1 << 1; // GOVERNANCE
        if (propType == ProposalType.TrustedSources) return 1 << 0; // ORACLE
        if (propType == ProposalType.AMMParameters) return 1 << 2; // PROTOCOL_RULES
        if (propType == ProposalType.Fees) return 1 << 2; // PROTOCOL_RULES
        if (propType == ProposalType.DisputePolicy) return 1 << 3; // DISPUTE
        if (propType == ProposalType.CircleMembership) return 1 << 1; // GOVERNANCE
        return 1 << 1; // Default: GOVERNANCE
    }

    // ============ View Functions ============

    function getProposal(
        bytes32 proposalId
    ) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getProposalCount() external view returns (uint256) {
        return allProposalIds.length;
    }

    function getVote(
        bytes32 proposalId,
        address voter
    ) external view returns (Vote memory) {
        return votes[proposalId][voter];
    }

    function hasVoted(
        bytes32 proposalId,
        address voter
    ) external view returns (bool) {
        return votes[proposalId][voter].hasVoted;
    }

    function getProposalState(
        bytes32 proposalId
    ) external view returns (ProposalStatus) {
        return proposals[proposalId].status;
    }
}
