// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StorageRegistry
 * @dev Tracks IPFS/Filecoin uploads and manages storage budget funded by DAO treasury
 */
contract StorageRegistry {
    struct Upload {
        string cid;
        address uploader;
        uint256 timestamp;
        uint256 cost; // in wei
        UploadType uploadType;
        bytes32 entityId; // proposalId, eventId, etc.
    }

    enum UploadType {
        Comment,
        EventPhoto,
        ProposalMedia,
        CircleDocument,
        AccountDocument,
        ResellerDocument,
        PartnerDocument,
        GeneralDocument
    }

    // Storage tracking
    mapping(bytes32 => Upload[]) public uploads; // entityId => uploads
    Upload[] public allUploads;

    // Budget management
    uint256 public monthlyBudget;
    uint256 public currentMonthSpent;
    uint256 public lastResetTimestamp;

    // Access control
    address public governance;
    mapping(address => bool) public authorizedUploaders;

    // Events
    event FileUploaded(
        string cid,
        address indexed uploader,
        UploadType uploadType,
        bytes32 entityId,
        uint256 cost
    );

    event BudgetSet(uint256 newBudget, address indexed setter);
    event BudgetReset(uint256 resetTime, uint256 spent);
    event UploaderAuthorized(address indexed uploader, bool authorized);

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }

    modifier onlyAuthorized() {
        require(
            authorizedUploaders[msg.sender] || msg.sender == governance,
            "Not authorized"
        );
        _;
    }

    constructor(address _governance, uint256 _initialBudget) {
        governance = _governance;
        monthlyBudget = _initialBudget;
        lastResetTimestamp = block.timestamp;
    }

    /**
     * @dev Record upload with cost tracking
     */
    function recordUpload(
        bytes32 entityId,
        string memory cid,
        UploadType uploadType,
        uint256 cost
    ) external onlyAuthorized {
        // Reset budget if month has passed
        if (block.timestamp >= lastResetTimestamp + 30 days) {
            emit BudgetReset(block.timestamp, currentMonthSpent);
            currentMonthSpent = 0;
            lastResetTimestamp = block.timestamp;
        }

        // Check budget
        require(currentMonthSpent + cost <= monthlyBudget, "Budget exceeded");

        Upload memory upload = Upload({
            cid: cid,
            uploader: msg.sender,
            timestamp: block.timestamp,
            cost: cost,
            uploadType: uploadType,
            entityId: entityId
        });

        uploads[entityId].push(upload);
        allUploads.push(upload);
        currentMonthSpent += cost;

        emit FileUploaded(cid, msg.sender, uploadType, entityId, cost);
    }

    /**
     * @dev Get uploads for entity
     */
    function getUploads(
        bytes32 entityId
    ) external view returns (Upload[] memory) {
        return uploads[entityId];
    }

    /**
     * @dev Get total upload count
     */
    function getTotalUploads() external view returns (uint256) {
        return allUploads.length;
    }

    /**
     * @dev Get budget utilization
     */
    function getBudgetUtilization()
        external
        view
        returns (uint256 spent, uint256 budget, uint256 percentage)
    {
        spent = currentMonthSpent;
        budget = monthlyBudget;
        percentage = budget > 0 ? (spent * 100) / budget : 0;
    }

    /**
     * @dev Set monthly budget (governance only)
     */
    function setMonthlyBudget(uint256 _newBudget) external onlyGovernance {
        monthlyBudget = _newBudget;
        emit BudgetSet(_newBudget, msg.sender);
    }

    /**
     * @dev Authorize uploader
     */
    function setAuthorizedUploader(
        address uploader,
        bool authorized
    ) external onlyGovernance {
        authorizedUploaders[uploader] = authorized;
        emit UploaderAuthorized(uploader, authorized);
    }

    /**
     * @dev Update governance address
     */
    function setGovernance(address _newGovernance) external onlyGovernance {
        governance = _newGovernance;
    }
}
