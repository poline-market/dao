// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/PolineDAO.sol";
import "forge-std/Script.sol";

contract RedeployDAO is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address polineToken = vm.envAddress("POLINE_TOKEN");
        address circleRegistry = vm.envAddress("CIRCLE_REGISTRY");
        address stakingManager = vm.envAddress("STAKING_MANAGER");
        address oracleVoting = vm.envAddress("ORACLE_VOTING");

        console.log("Redeploying PolineDAO...");
        console.log("Deployer:", deployer);
        console.log("Token:", polineToken);

        vm.startBroadcast(deployerPrivateKey);

        PolineDAO dao = new PolineDAO(
            polineToken,
            circleRegistry,
            stakingManager,
            oracleVoting,
            deployer
        );

        console.log("PolineDAO deployed at:", address(dao));

        vm.stopBroadcast();

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Update PolinePurchase treasury:");
        console.log(
            "   cast send 0x6659beb09d82192feb66c8896f524fad6d01bd28 \\"
        );
        console.log("     'updateTreasury(address)' %s \\", address(dao));
        console.log("     --rpc-url https://rpc-amoy.polygon.technology \\");
        console.log("     --private-key $PRIVATE_KEY --legacy");
        console.log("\n2. Update frontend contracts.ts:");
        console.log("   polineDAO: '%s'", address(dao));
    }
}
