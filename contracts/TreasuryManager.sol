// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TreasuryManager
 * @dev Framework for DAO-controlled budget allocation
 *
 * KEY PRINCIPLE:
 * - Contract provides MECHANISM only
 * - DAO decides ALL VALUES via governance votes
 * - No hardcoded budgets or allocations
 * - Complete community control
 *
 * Example:
 * 1. DAO proposes: "Create Marketing budget"
 * 2. Vote passes
 * 3. DAO proposes: "Allocate X ETH to Marketing"
 * 4. Vote passes
 * 5. Funds transferred to Marketing wallet
 */
contract TreasuryManager {
    struct BudgetWallet {
        address walletAddress;
        address manager;
        uint256 totalAllocated; // Lifetime allocation
        uint256 totalSpent; // Tracked if wallet reports
        uint256 lastAllocationTime;
        bool active;
    }

    struct Allocation {
        bytes32 allocationId;
        BudgetType budgetType;
        uint256 amount; // DAO decides amount
        uint256 timestamp;
        bool transferred;
    }

    enum BudgetType {
        Storage,
        Accounts,
        Resellers,
        Partners,
        Development,
        Marketing,
        Legal,
        Infrastructure,
        Operations,
        Community
    }

    mapping(BudgetType => BudgetWallet) public budgetWallets;
    mapping(bytes32 => Allocation) public allocations;
    bytes32[] public allAllocationIds;

    address public governance;

    event BudgetWalletCreated(
        BudgetType indexed budgetType,
        address indexed walletAddress,
        address indexed manager
    );

    event AllocationProposed(
        bytes32 indexed allocationId,
        BudgetType indexed budgetType,
        uint256 amount
    );

    event FundsTransferred(
        bytes32 indexed allocationId,
        address indexed wallet,
        uint256 amount
    );

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }

    constructor(address _governance) {
        governance = _governance;
    }

    /**
     * @dev Create budget wallet (DAO votes on address and manager)
     */
    function setBudgetWallet(
        BudgetType budgetType,
        address walletAddress,
        address manager
    ) external onlyGovernance {
        require(walletAddress != address(0), "Invalid wallet");

        budgetWallets[budgetType] = BudgetWallet({
            walletAddress: walletAddress,
            manager: manager,
            totalAllocated: 0,
            totalSpent: 0,
            lastAllocationTime: 0,
            active: true
        });

        emit BudgetWalletCreated(budgetType, walletAddress, manager);
    }

    /**
     * @dev Allocate and transfer funds (called when DAO proposal is executed)
     * @notice When a budget allocation proposal passes voting and is executed,
     *         this function creates the allocation record AND transfers the funds
     */
    function proposeAllocation(
        BudgetType budgetType,
        uint256 amount
    ) external onlyGovernance returns (bytes32) {
        require(budgetWallets[budgetType].active, "Wallet not active");
        require(
            address(this).balance >= amount,
            "Insufficient treasury balance"
        );

        bytes32 allocationId = keccak256(
            abi.encodePacked(budgetType, amount, block.timestamp)
        );

        allocations[allocationId] = Allocation({
            allocationId: allocationId,
            budgetType: budgetType,
            amount: amount,
            timestamp: block.timestamp,
            transferred: true // Mark as transferred immediately
        });

        allAllocationIds.push(allocationId);

        // Update budget wallet and transfer funds
        BudgetWallet storage wallet = budgetWallets[budgetType];
        wallet.totalAllocated += amount;
        wallet.lastAllocationTime = block.timestamp;

        (bool success, ) = wallet.walletAddress.call{value: amount}("");
        require(success, "Transfer failed");

        emit AllocationProposed(allocationId, budgetType, amount);
        emit FundsTransferred(allocationId, wallet.walletAddress, amount);

        return allocationId;
    }

    /**
     * @dev Transfer approved funds
     */
    function transferToBudget(bytes32 allocationId) external onlyGovernance {
        Allocation storage allocation = allocations[allocationId];
        require(!allocation.transferred, "Already transferred");

        BudgetWallet storage wallet = budgetWallets[allocation.budgetType];
        require(wallet.active, "Wallet not active");
        require(
            address(this).balance >= allocation.amount,
            "Insufficient balance"
        );

        allocation.transferred = true;
        wallet.totalAllocated += allocation.amount;
        wallet.lastAllocationTime = block.timestamp;

        (bool success, ) = wallet.walletAddress.call{value: allocation.amount}(
            ""
        );
        require(success, "Transfer failed");

        emit FundsTransferred(
            allocationId,
            wallet.walletAddress,
            allocation.amount
        );
    }

    /**
     * @dev Get budget info
     */
    function getBudgetWallet(
        BudgetType budgetType
    )
        external
        view
        returns (
            address walletAddress,
            address manager,
            uint256 totalAllocated,
            uint256 currentBalance,
            bool active
        )
    {
        BudgetWallet memory wallet = budgetWallets[budgetType];
        return (
            wallet.walletAddress,
            wallet.manager,
            wallet.totalAllocated,
            wallet.walletAddress.balance,
            wallet.active
        );
    }

    /**
     * @dev Change manager (DAO votes on new manager)
     */
    function setBudgetManager(
        BudgetType budgetType,
        address newManager
    ) external onlyGovernance {
        budgetWallets[budgetType].manager = newManager;
    }

    /**
     * @dev Deactivate budget
     */
    function deactivateBudget(BudgetType budgetType) external onlyGovernance {
        budgetWallets[budgetType].active = false;
    }

    receive() external payable {}
}
