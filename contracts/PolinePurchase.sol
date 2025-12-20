// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IPolineToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PolinePurchase
 * @notice Allows users to purchase POLINE tokens with MATIC
 * @dev This contract must have MINTER_ROLE on PolineToken
 *      Collected MATIC goes to the DAO treasury
 */
contract PolinePurchase is Ownable, ReentrancyGuard {
    IPolineToken public immutable polineToken;
    address public treasury;

    /// @notice Price in wei per POLINE token (18 decimals)
    /// @dev Default: 0.001 MATIC per POLINE (can be changed by owner)
    uint256 public pricePerToken;

    /// @notice Minimum purchase amount to prevent spam
    uint256 public minimumPurchase;

    /// @notice Maximum purchase per transaction to prevent whales
    uint256 public maximumPurchase;

    /// @notice Total MATIC collected
    uint256 public totalCollected;

    /// @notice Total POLINE sold
    uint256 public totalSold;

    event TokensPurchased(
        address indexed buyer,
        uint256 amount,
        uint256 cost,
        string reason
    );
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event LimitsUpdated(uint256 minimum, uint256 maximum);

    error InsufficientPayment(uint256 required, uint256 provided);
    error BelowMinimum(uint256 amount, uint256 minimum);
    error AboveMaximum(uint256 amount, uint256 maximum);
    error InvalidAddress();
    error TransferFailed();

    constructor(
        address _polineToken,
        address _treasury,
        uint256 _initialPrice
    ) Ownable(msg.sender) {
        if (_polineToken == address(0) || _treasury == address(0)) {
            revert InvalidAddress();
        }

        polineToken = IPolineToken(_polineToken);
        treasury = _treasury;
        pricePerToken = _initialPrice;

        // Default limits
        minimumPurchase = 10 * 10 ** 18; // 10 POLINE minimum
        maximumPurchase = 10000 * 10 ** 18; // 10k POLINE maximum per tx
    }

    /**
     * @notice Buy POLINE tokens with MATIC
     * @param amount Amount of POLINE tokens to purchase (in wei, 18 decimals)
     */
    function buyTokens(uint256 amount) external payable nonReentrant {
        // Validate amount
        if (amount < minimumPurchase) {
            revert BelowMinimum(amount, minimumPurchase);
        }
        if (amount > maximumPurchase) {
            revert AboveMaximum(amount, maximumPurchase);
        }

        // Calculate cost
        uint256 cost = (amount * pricePerToken) / 10 ** 18;
        if (msg.value < cost) {
            revert InsufficientPayment(cost, msg.value);
        }

        // Mint tokens to buyer
        polineToken.mint(msg.sender, amount, "Token purchase");

        // Update stats
        totalCollected += cost;
        totalSold += amount;

        // Transfer MATIC to treasury
        (bool success, ) = treasury.call{value: cost}("");
        if (!success) {
            revert TransferFailed();
        }

        // Refund excess MATIC
        if (msg.value > cost) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - cost}(
                ""
            );
            require(refundSuccess, "Refund failed");
        }

        emit TokensPurchased(msg.sender, amount, cost, "Purchase");
    }

    /**
     * @notice Calculate cost for a given amount of tokens
     * @param amount Amount of POLINE tokens (in wei)
     * @return cost Cost in MATIC (in wei)
     */
    function calculateCost(
        uint256 amount
    ) external view returns (uint256 cost) {
        return (amount * pricePerToken) / 10 ** 18;
    }

    /**
     * @notice Calculate how many tokens can be bought with given MATIC
     * @param maticAmount Amount of MATIC (in wei)
     * @return amount Amount of POLINE tokens (in wei)
     */
    function calculateTokens(
        uint256 maticAmount
    ) external view returns (uint256 amount) {
        return (maticAmount * 10 ** 18) / pricePerToken;
    }

    // ============ Admin Functions ============

    /**
     * @notice Update price per token (only owner)
     * @param newPrice New price in wei per POLINE token
     */
    function updatePrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be > 0");
        uint256 oldPrice = pricePerToken;
        pricePerToken = newPrice;
        emit PriceUpdated(oldPrice, newPrice);
    }

    /**
     * @notice Update treasury address (only owner)
     * @param newTreasury New treasury address
     */
    function updateTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) {
            revert InvalidAddress();
        }
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Update purchase limits (only owner)
     * @param minimum Minimum purchase amount
     * @param maximum Maximum purchase amount
     */
    function updateLimits(uint256 minimum, uint256 maximum) external onlyOwner {
        require(minimum > 0 && minimum < maximum, "Invalid limits");
        minimumPurchase = minimum;
        maximumPurchase = maximum;
        emit LimitsUpdated(minimum, maximum);
    }

    /**
     * @notice Emergency withdrawal (only owner, if MATIC gets stuck)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Withdrawal failed");
    }
}
