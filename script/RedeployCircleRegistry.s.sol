// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/CircleRegistry.sol";
import "forge-std/Script.sol";

/**
 * @title RedeployCircleRegistry
 * @notice Redeploy CircleRegistry with stakingManager reference for self-join feature
 */
contract RedeployCircleRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address stakingManager = vm.envAddress("STAKING_MANAGER");

        console.log("Redeploying CircleRegistry...");
        console.log("Deployer:", deployer);
        console.log("StakingManager:", stakingManager);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new CircleRegistry with stakingManager reference
        CircleRegistry circleRegistry = new CircleRegistry(
            deployer,
            stakingManager
        );
        console.log("CircleRegistry deployed at:", address(circleRegistry));

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

        vm.stopBroadcast();

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Update frontend contracts.ts:");
        console.log("   circleRegistry: '%s'", address(circleRegistry));
        console.log("\n2. Grant CIRCLE_ADMIN_ROLE to PolineDAO if needed:");
        console.log("   cast send %s \\", address(circleRegistry));
        console.log("     'grantRole(bytes32,address)' \\");
        console.log("     0x... $POLINE_DAO \\");
        console.log(
            "     --rpc-url $RPC_URL --private-key $PRIVATE_KEY --legacy"
        );
    }
}
