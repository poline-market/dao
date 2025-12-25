// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/PolineToken.sol";
import "../contracts/CircleRegistry.sol";
import "../contracts/StakingManager.sol";
import "../contracts/OracleVoting.sol";
import "../contracts/DisputeResolution.sol";
import "../contracts/PolineDAO.sol";
import "../contracts/PolinePurchase.sol";
import "../contracts/TreasuryManager.sol";

/**
 * @title Deploy
 * @notice Deployment script for Poline DAO contracts
 */
contract Deploy is Script {
    function run() external {
        // When using --private-key flag, Foundry handles the key automatically
        // Get deployer address from the key passed via command line
        address deployer = msg.sender;

        vm.startBroadcast();

        // 1. Deploy Token
        PolineToken token = new PolineToken(
            "Poline Governance",
            "POLINE",
            deployer
        );
        console.log("PolineToken deployed at:", address(token));

        // 2. Deploy Staking Manager (before CircleRegistry, since it needs the reference)
        StakingManager stakingManager = new StakingManager(
            address(token),
            deployer
        );
        console.log("StakingManager deployed at:", address(stakingManager));

        // 3. Deploy Circle Registry (with stakingManager reference for joinCircle feature)
        CircleRegistry circleRegistry = new CircleRegistry(
            deployer,
            address(stakingManager)
        );
        console.log("CircleRegistry deployed at:", address(circleRegistry));

        // 4. Deploy Oracle Voting
        OracleVoting oracleVoting = new OracleVoting(
            address(stakingManager),
            address(circleRegistry),
            deployer
        );
        console.log("OracleVoting deployed at:", address(oracleVoting));

        // 5. Deploy Dispute Resolution
        DisputeResolution disputeResolution = new DisputeResolution(
            address(stakingManager),
            address(oracleVoting),
            deployer
        );
        console.log(
            "DisputeResolution deployed at:",
            address(disputeResolution)
        );

        // 6. Deploy DAO
        PolineDAO dao = new PolineDAO(
            address(token),
            address(circleRegistry),
            address(stakingManager),
            address(oracleVoting),
            deployer
        );
        console.log("PolineDAO deployed at:", address(dao));

        // Grant roles
        token.grantRole(token.MINTER_ROLE(), address(dao));
        token.grantRole(token.SLASHER_ROLE(), address(stakingManager));
        stakingManager.grantRole(
            stakingManager.SLASHER_ROLE(),
            address(oracleVoting)
        );
        stakingManager.grantRole(
            stakingManager.SLASHER_ROLE(),
            address(disputeResolution)
        );

        // Create default circles
        bytes32 oracleCircle = circleRegistry.createCircle(
            "Oracle",
            1, // SCOPE_ORACLE
            100 ether
        );
        console.log("Oracle Circle created");

        bytes32 governanceCircle = circleRegistry.createCircle(
            "Governance",
            2, // SCOPE_GOVERNANCE
            200 ether
        );
        console.log("Governance Circle created");

        bytes32 protocolCircle = circleRegistry.createCircle(
            "Protocol Rules",
            4, // SCOPE_PROTOCOL_RULES
            150 ether
        );
        console.log("Protocol Rules Circle created");

        bytes32 disputeCircle = circleRegistry.createCircle(
            "Dispute Resolution",
            8, // SCOPE_DISPUTE
            300 ether
        );
        console.log("Dispute Resolution Circle created");

        bytes32 communityCircle = circleRegistry.createCircle(
            "Community",
            16, // SCOPE_COMMUNITY
            50 ether
        );
        console.log("Community Circle created");

        // 7. Deploy PolinePurchase (must be after DAO for treasury reference)
        PolinePurchase purchase = new PolinePurchase(
            address(token),
            address(dao), // Treasury is the DAO
            0.001 ether // Initial price: 0.001 POL per POLINE
        );
        console.log("PolinePurchase deployed at:", address(purchase));

        // Grant MINTER_ROLE to PolinePurchase so it can mint tokens on purchase
        token.grantRole(token.MINTER_ROLE(), address(purchase));
        console.log("MINTER_ROLE granted to PolinePurchase");

        // 8. Deploy TreasuryManager (DAO is the governance)
        TreasuryManager treasury = new TreasuryManager(address(dao));
        console.log("TreasuryManager deployed at:", address(treasury));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Token:", address(token));
        console.log("StakingManager:", address(stakingManager));
        console.log("CircleRegistry:", address(circleRegistry));
        console.log("OracleVoting:", address(oracleVoting));
        console.log("DisputeResolution:", address(disputeResolution));
        console.log("PolineDAO:", address(dao));
        console.log("PolinePurchase:", address(purchase));
        console.log("TreasuryManager:", address(treasury));
    }
}
