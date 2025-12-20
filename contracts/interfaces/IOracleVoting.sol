// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOracleVoting
 * @notice Interface for Oracle Voting system
 */
interface IOracleVoting {
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
        uint256 yesVotes;
        uint256 noVotes;
        EventStatus status;
        bool outcome;
        address creator;
    }

    function createEvent(string calldata description, uint256 votingPeriod) external returns (bytes32 eventId);
    function castVote(bytes32 eventId, bool vote) external;
    function resolveEvent(bytes32 eventId) external;
    function markDisputed(bytes32 eventId) external;
    function cancelEvent(bytes32 eventId) external;
    
    function getEvent(bytes32 eventId) external view returns (OracleEvent memory);
    function getEventCount() external view returns (uint256);
    function hasVoted(bytes32 eventId, address voter) external view returns (bool);
}
