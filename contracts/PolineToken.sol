// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PolineToken
 * @notice Governance token for Poline DAO - Soulbound (non-transferable)
 * @dev Features:
 *      - Voting power via ERC20Votes
 *      - Non-transferable (soulbound) for reputation
 *      - Slashing mechanism for penalties
 *      - Minting controlled by DAO roles
 */
contract PolineToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    /// @notice Emitted when tokens are slashed from an account
    event Slashed(address indexed account, uint256 amount, string reason);

    /// @notice Emitted when tokens are minted to an account
    event TokensMinted(address indexed to, uint256 amount, string reason);

    error TransferNotAllowed();
    error InsufficientBalance(address account, uint256 requested, uint256 available);

    constructor(
        string memory name_,
        string memory symbol_,
        address admin
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(SLASHER_ROLE, admin);
    }

    /**
     * @notice Mint new tokens (only MINTER_ROLE)
     * @param to Recipient address
     * @param amount Amount to mint
     * @param reason Reason for minting (for events/audit)
     */
    function mint(address to, uint256 amount, string calldata reason) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit TokensMinted(to, amount, reason);
    }

    /**
     * @notice Slash tokens from an account (burn) - only SLASHER_ROLE
     * @param account Account to slash
     * @param amount Amount to slash
     * @param reason Reason for slashing
     */
    function slash(address account, uint256 amount, string calldata reason) external onlyRole(SLASHER_ROLE) {
        uint256 balance = balanceOf(account);
        if (balance < amount) {
            revert InsufficientBalance(account, amount, balance);
        }
        _burn(account, amount);
        emit Slashed(account, amount, reason);
    }

    /**
     * @notice Get current voting power of an account
     * @param account Address to check
     * @return Voting power (delegated votes)
     */
    function getVotingPower(address account) external view returns (uint256) {
        return getVotes(account);
    }

    // ============ SOULBOUND: Block all transfers ============

    /**
     * @dev Override to block transfers - token is soulbound
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }

    /**
     * @dev Override to block transferFrom - token is soulbound
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }

    /**
     * @dev Override to block approve - no point if can't transfer
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert TransferNotAllowed();
    }

    // ============ Required Overrides for ERC20Votes ============

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
