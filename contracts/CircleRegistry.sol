// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IStakingManager.sol";

/**
 * @title CircleRegistry
 * @notice Manages holacracy circles for Poline DAO governance
 * @dev Circles have:
 *      - Limited powers (proposal scopes)
 *      - Members with stake requirements
 *      - Voting within their scope
 */
contract CircleRegistry is AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant CIRCLE_ADMIN_ROLE = keccak256("CIRCLE_ADMIN_ROLE");

    /// @notice Reference to StakingManager for stake verification
    IStakingManager public stakingManager;

    /// @notice Proposal scope flags (bitmask)
    uint256 public constant SCOPE_ORACLE = 1 << 0; // Resolve events
    uint256 public constant SCOPE_GOVERNANCE = 1 << 1; // Define rules
    uint256 public constant SCOPE_PROTOCOL_RULES = 1 << 2; // AMM params, fees
    uint256 public constant SCOPE_DISPUTE = 1 << 3; // Dispute resolution
    uint256 public constant SCOPE_COMMUNITY = 1 << 4; // Growth decisions

    struct Circle {
        bytes32 id;
        string name;
        uint256 proposalScope; // Bitmask of allowed proposal types
        uint256 requiredStake; // Minimum stake to join
        bool active;
        uint256 createdAt;
    }

    /// @notice Circle ID => Circle data
    mapping(bytes32 => Circle) public circles;

    /// @notice Circle ID => set of member addresses
    mapping(bytes32 => EnumerableSet.AddressSet) private _circleMembers;

    /// @notice All circle IDs
    EnumerableSet.Bytes32Set private _circleIds;

    /// @notice Member => circles they belong to
    mapping(address => EnumerableSet.Bytes32Set) private _memberCircles;

    // Events
    event CircleCreated(
        bytes32 indexed circleId,
        string name,
        uint256 proposalScope,
        uint256 requiredStake
    );
    event CircleUpdated(
        bytes32 indexed circleId,
        uint256 proposalScope,
        uint256 requiredStake
    );
    event CircleDeactivated(bytes32 indexed circleId);
    event MemberAdded(bytes32 indexed circleId, address indexed member);
    event MemberRemoved(bytes32 indexed circleId, address indexed member);

    // Errors
    error CircleAlreadyExists(bytes32 circleId);
    error CircleNotFound(bytes32 circleId);
    error CircleNotActive(bytes32 circleId);
    error MemberAlreadyInCircle(bytes32 circleId, address member);
    error MemberNotInCircle(bytes32 circleId, address member);
    error InvalidScope(uint256 scope);
    error EmptyName();
    error InsufficientStake(uint256 required, uint256 actual);

    constructor(address admin, address _stakingManager) {
        stakingManager = IStakingManager(_stakingManager);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CIRCLE_ADMIN_ROLE, admin);
    }

    /**
     * @notice Create a new circle
     * @param name Human-readable circle name
     * @param proposalScope Bitmask of allowed proposal types
     * @param requiredStake Minimum stake to join circle
     * @return circleId The new circle's ID
     */
    function createCircle(
        string calldata name,
        uint256 proposalScope,
        uint256 requiredStake
    ) external onlyRole(CIRCLE_ADMIN_ROLE) returns (bytes32 circleId) {
        if (bytes(name).length == 0) revert EmptyName();
        if (proposalScope == 0) revert InvalidScope(proposalScope);

        circleId = keccak256(
            abi.encodePacked(name, block.timestamp, msg.sender)
        );

        if (circles[circleId].createdAt != 0) {
            revert CircleAlreadyExists(circleId);
        }

        circles[circleId] = Circle({
            id: circleId,
            name: name,
            proposalScope: proposalScope,
            requiredStake: requiredStake,
            active: true,
            createdAt: block.timestamp
        });

        _circleIds.add(circleId);

        emit CircleCreated(circleId, name, proposalScope, requiredStake);
    }

    /**
     * @notice Update circle parameters
     * @param circleId Circle to update
     * @param proposalScope New proposal scope
     * @param requiredStake New required stake
     */
    function updateCircle(
        bytes32 circleId,
        uint256 proposalScope,
        uint256 requiredStake
    ) external onlyRole(CIRCLE_ADMIN_ROLE) {
        Circle storage circle = circles[circleId];
        if (circle.createdAt == 0) revert CircleNotFound(circleId);
        if (!circle.active) revert CircleNotActive(circleId);

        circle.proposalScope = proposalScope;
        circle.requiredStake = requiredStake;

        emit CircleUpdated(circleId, proposalScope, requiredStake);
    }

    /**
     * @notice Deactivate a circle
     * @param circleId Circle to deactivate
     */
    function deactivateCircle(
        bytes32 circleId
    ) external onlyRole(CIRCLE_ADMIN_ROLE) {
        Circle storage circle = circles[circleId];
        if (circle.createdAt == 0) revert CircleNotFound(circleId);

        circle.active = false;
        emit CircleDeactivated(circleId);
    }

    /**
     * @notice Add member to a circle
     * @param circleId Circle to join
     * @param member Address to add
     */
    function addMember(
        bytes32 circleId,
        address member
    ) external onlyRole(CIRCLE_ADMIN_ROLE) {
        Circle storage circle = circles[circleId];
        if (circle.createdAt == 0) revert CircleNotFound(circleId);
        if (!circle.active) revert CircleNotActive(circleId);

        if (!_circleMembers[circleId].add(member)) {
            revert MemberAlreadyInCircle(circleId, member);
        }

        _memberCircles[member].add(circleId);
        emit MemberAdded(circleId, member);
    }

    /**
     * @notice Remove member from a circle
     * @param circleId Circle to leave
     * @param member Address to remove
     */
    function removeMember(
        bytes32 circleId,
        address member
    ) external onlyRole(CIRCLE_ADMIN_ROLE) {
        if (!_circleMembers[circleId].remove(member)) {
            revert MemberNotInCircle(circleId, member);
        }

        _memberCircles[member].remove(circleId);
        emit MemberRemoved(circleId, member);
    }

    /**
     * @notice Join a circle if you have sufficient stake
     * @dev Anyone with enough stake can join - no admin approval needed
     * @param circleId Circle to join
     */
    function joinCircle(bytes32 circleId) external {
        Circle storage circle = circles[circleId];
        if (circle.createdAt == 0) revert CircleNotFound(circleId);
        if (!circle.active) revert CircleNotActive(circleId);

        // Verify user has sufficient stake
        uint256 userStake = stakingManager.getStake(msg.sender);
        if (userStake < circle.requiredStake) {
            revert InsufficientStake(circle.requiredStake, userStake);
        }

        // Add user to circle
        if (!_circleMembers[circleId].add(msg.sender)) {
            revert MemberAlreadyInCircle(circleId, msg.sender);
        }

        _memberCircles[msg.sender].add(circleId);
        emit MemberAdded(circleId, msg.sender);
    }

    /**
     * @notice Leave a circle voluntarily
     * @param circleId Circle to leave
     */
    function leaveCircle(bytes32 circleId) external {
        if (!_circleMembers[circleId].remove(msg.sender)) {
            revert MemberNotInCircle(circleId, msg.sender);
        }

        _memberCircles[msg.sender].remove(circleId);
        emit MemberRemoved(circleId, msg.sender);
    }

    // ============ View Functions ============

    /**
     * @notice Check if address is member of a circle
     */
    function isMember(
        bytes32 circleId,
        address account
    ) external view returns (bool) {
        return _circleMembers[circleId].contains(account);
    }

    /**
     * @notice Get all members of a circle
     */
    function getMembers(
        bytes32 circleId
    ) external view returns (address[] memory) {
        return _circleMembers[circleId].values();
    }

    /**
     * @notice Get member count of a circle
     */
    function getMemberCount(bytes32 circleId) external view returns (uint256) {
        return _circleMembers[circleId].length();
    }

    /**
     * @notice Get all circles an address belongs to
     */
    function getCirclesForMember(
        address member
    ) external view returns (bytes32[] memory) {
        return _memberCircles[member].values();
    }

    /**
     * @notice Get all active circle IDs
     */
    function getAllCircles() external view returns (bytes32[] memory) {
        return _circleIds.values();
    }

    /**
     * @notice Get total number of circles
     */
    function getCircleCount() external view returns (uint256) {
        return _circleIds.length();
    }

    /**
     * @notice Check if circle has specific scope
     * @param circleId Circle to check
     * @param scope Scope flag to check
     */
    function hasScope(
        bytes32 circleId,
        uint256 scope
    ) external view returns (bool) {
        return (circles[circleId].proposalScope & scope) != 0;
    }
}
