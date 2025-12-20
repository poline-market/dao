// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStakingManager
 * @notice Interface for Staking Manager
 */
interface IStakingManager {
    function stake(uint256 amount) external;
    function requestUnstake() external;
    function completeUnstake() external;
    function slashStake(address user, uint256 amount, string calldata reason) external;
    
    function isOracle(address user) external view returns (bool);
    function getStake(address user) external view returns (uint256);
    function totalStaked() external view returns (uint256);
    function canUnstake(address user) external view returns (bool);
}
