// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPolineToken
 * @notice Interface for Poline governance token
 */
interface IPolineToken {
    function mint(address to, uint256 amount, string calldata reason) external;
    function slash(address account, uint256 amount, string calldata reason) external;
    function getVotingPower(address account) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function delegate(address delegatee) external;
    function getVotes(address account) external view returns (uint256);
}
