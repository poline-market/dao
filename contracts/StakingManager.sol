// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IPolineToken.sol";

/**
 * @title StakingManager
 * @notice Manages staking for oracle participation
 * @dev Features:
 *      - Lock tokens to become oracle
 *      - Cooldown period for unstaking
 *      - Automatic slashing integration
 *      - Voting power while staked
 */
contract StakingManager is AccessControl, ReentrancyGuard {
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    IPolineToken public immutable polineToken;

    /// @notice Cooldown period before unstake completes
    uint256 public unstakeCooldown = 7 days;

    /// @notice Minimum stake to be an oracle
    uint256 public minimumStake = 100 ether; // 100 tokens

    struct StakeInfo {
        uint256 amount;
        uint256 stakedAt;
        uint256 unstakeRequestedAt;
        bool isOracle;
    }

    /// @notice User => stake info
    mapping(address => StakeInfo) public stakes;

    /// @notice Total staked in the contract
    uint256 public totalStaked;

    // Events
    event Staked(address indexed user, uint256 amount);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 amount);
    event OracleStatusChanged(address indexed user, bool isOracle);
    event Slashed(address indexed user, uint256 amount, string reason);
    event ParametersUpdated(uint256 cooldown, uint256 minStake);

    // Errors
    error InsufficientStake(uint256 required, uint256 provided);
    error NoStakeFound();
    error UnstakeNotRequested();
    error CooldownNotComplete(uint256 unlockTime, uint256 currentTime);
    error AlreadyUnstaking();
    error NotOracle();
    error ZeroAmount();

    constructor(address token, address admin) {
        polineToken = IPolineToken(token);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SLASHER_ROLE, admin);
    }

    /**
     * @notice Stake tokens to become an oracle
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        StakeInfo storage info = stakes[msg.sender];
        
        // Check if user is mid-unstake - cancel it
        if (info.unstakeRequestedAt != 0) {
            info.unstakeRequestedAt = 0;
        }

        uint256 newTotal = info.amount + amount;
        
        // Note: Since token is soulbound, we just record the stake
        // The token balance already represents their commitment
        info.amount = newTotal;
        info.stakedAt = block.timestamp;
        
        totalStaked += amount;

        // Auto-grant oracle status if meets minimum
        if (newTotal >= minimumStake && !info.isOracle) {
            info.isOracle = true;
            emit OracleStatusChanged(msg.sender, true);
        }

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Request to unstake tokens (starts cooldown)
     */
    function requestUnstake() external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        
        if (info.amount == 0) revert NoStakeFound();
        if (info.unstakeRequestedAt != 0) revert AlreadyUnstaking();

        info.unstakeRequestedAt = block.timestamp;
        
        uint256 unlockTime = block.timestamp + unstakeCooldown;
        emit UnstakeRequested(msg.sender, info.amount, unlockTime);
    }

    /**
     * @notice Complete unstake after cooldown
     */
    function completeUnstake() external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        
        if (info.unstakeRequestedAt == 0) revert UnstakeNotRequested();
        
        uint256 unlockTime = info.unstakeRequestedAt + unstakeCooldown;
        if (block.timestamp < unlockTime) {
            revert CooldownNotComplete(unlockTime, block.timestamp);
        }

        uint256 amount = info.amount;
        
        // Reset stake info
        info.amount = 0;
        info.stakedAt = 0;
        info.unstakeRequestedAt = 0;
        
        if (info.isOracle) {
            info.isOracle = false;
            emit OracleStatusChanged(msg.sender, false);
        }

        totalStaked -= amount;

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Cancel unstake request
     */
    function cancelUnstake() external {
        StakeInfo storage info = stakes[msg.sender];
        if (info.unstakeRequestedAt == 0) revert UnstakeNotRequested();
        
        info.unstakeRequestedAt = 0;
    }

    /**
     * @notice Slash a staker's tokens (called by oracle voting or disputes)
     * @param user User to slash
     * @param amount Amount to slash
     * @param reason Reason for slashing
     */
    function slashStake(
        address user,
        uint256 amount,
        string calldata reason
    ) external onlyRole(SLASHER_ROLE) {
        StakeInfo storage info = stakes[user];
        
        if (info.amount < amount) {
            amount = info.amount; // Slash remaining
        }

        info.amount -= amount;
        totalStaked -= amount;

        // Remove oracle status if below minimum
        if (info.amount < minimumStake && info.isOracle) {
            info.isOracle = false;
            emit OracleStatusChanged(user, false);
        }

        // Actually burn tokens
        polineToken.slash(user, amount, reason);

        emit Slashed(user, amount, reason);
    }

    /**
     * @notice Update staking parameters
     * @param newCooldown New cooldown period
     * @param newMinStake New minimum stake
     */
    function updateParameters(
        uint256 newCooldown,
        uint256 newMinStake
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        unstakeCooldown = newCooldown;
        minimumStake = newMinStake;
        emit ParametersUpdated(newCooldown, newMinStake);
    }

    // ============ View Functions ============

    /**
     * @notice Check if address is an active oracle
     */
    function isOracle(address user) external view returns (bool) {
        return stakes[user].isOracle;
    }

    /**
     * @notice Get stake amount for user
     */
    function getStake(address user) external view returns (uint256) {
        return stakes[user].amount;
    }

    /**
     * @notice Check if user can unstake now
     */
    function canUnstake(address user) external view returns (bool) {
        StakeInfo storage info = stakes[user];
        if (info.unstakeRequestedAt == 0) return false;
        return block.timestamp >= info.unstakeRequestedAt + unstakeCooldown;
    }

    /**
     * @notice Get time until unstake is available
     */
    function timeUntilUnstake(address user) external view returns (uint256) {
        StakeInfo storage info = stakes[user];
        if (info.unstakeRequestedAt == 0) return type(uint256).max;
        
        uint256 unlockTime = info.unstakeRequestedAt + unstakeCooldown;
        if (block.timestamp >= unlockTime) return 0;
        return unlockTime - block.timestamp;
    }
}
