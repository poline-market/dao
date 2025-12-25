// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/UserProfile.sol";

/**
 * @title DeployUserProfile
 * @notice Individual deployment script for UserProfile contract
 * @dev Use this for deploying UserProfile separately from full redeploy
 */
contract DeployUserProfile is Script {
    function run() external {
        vm.startBroadcast();

        UserProfile userProfile = new UserProfile();
        console.log("UserProfile deployed at:", address(userProfile));

        vm.stopBroadcast();

        console.log("\n=== UserProfile Deployment Complete ===");
        console.log("UserProfile:", address(userProfile));
    }
}
