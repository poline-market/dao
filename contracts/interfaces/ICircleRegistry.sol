// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICircleRegistry
 * @notice Interface for Circle Registry
 */
interface ICircleRegistry {
    struct Circle {
        bytes32 id;
        string name;
        uint256 proposalScope;
        uint256 requiredStake;
        bool active;
        uint256 createdAt;
    }

    function createCircle(string calldata name, uint256 proposalScope, uint256 requiredStake) external returns (bytes32);
    function updateCircle(bytes32 circleId, uint256 proposalScope, uint256 requiredStake) external;
    function deactivateCircle(bytes32 circleId) external;
    function addMember(bytes32 circleId, address member) external;
    function removeMember(bytes32 circleId, address member) external;
    
    function isMember(bytes32 circleId, address account) external view returns (bool);
    function getMembers(bytes32 circleId) external view returns (address[] memory);
    function getMemberCount(bytes32 circleId) external view returns (uint256);
    function hasScope(bytes32 circleId, uint256 scope) external view returns (bool);
    function circles(bytes32 circleId) external view returns (
        bytes32 id,
        string memory name,
        uint256 proposalScope,
        uint256 requiredStake,
        bool active,
        uint256 createdAt
    );
}
