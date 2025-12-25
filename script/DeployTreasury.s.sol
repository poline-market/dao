// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/TreasuryManager.sol";
import "../contracts/StorageRegistry.sol";

/**
 * @title DeployTreasury
 * @notice Deploy TreasuryManager and StorageRegistry contracts
 *
 * == DOCKER DEPLOYMENT COMMANDS ==
 *
 * 1. Build contracts:
 *    docker run --rm --entrypoint forge -v C:\Users\User\Documents\poline\dao:/app -w /app --env-file .env ghcr.io/foundry-rs/foundry:latest build
 *
 * 2. Deploy to Polygon Amoy Testnet:
 *    docker run --rm --entrypoint forge -v C:\Users\User\Documents\poline\dao:/app -w /app --env-file .env -e POLINE_DAO=0xcce1f7890c3611bd96404460af9cfd74a99fec13 ghcr.io/foundry-rs/foundry:latest script script/DeployTreasury.s.sol:DeployTreasury --rpc-url https://rpc-amoy.polygon.technology --broadcast --legacy
 *
 * 3. Deploy with verification:
 *    docker run --rm --entrypoint forge -v C:\Users\User\Documents\poline\dao:/app -w /app --env-file .env -e POLINE_DAO=0xcce1f7890c3611bd96404460af9cfd74a99fec13 ghcr.io/foundry-rs/foundry:latest script script/DeployTreasury.s.sol:DeployTreasury --rpc-url https://rpc-amoy.polygon.technology --broadcast --legacy --verify
 *
 * == DEPLOYED CONTRACTS (Polygon Amoy) ==
 * PolineToken:       0x1Ae28C576Bc48652BDf316cCfBA09f74F3E890e9
 * StakingManager:    0x0289E2C7129BFBcCa50465eCF631aBb0EeA39A10
 * CircleRegistry:    0x24BeA193279A2dDf20aCd82F0e801BbC65a9Fb11
 * OracleVoting:      0xb7E76E16E28100664dC1649b73e1788224c59bD5
 * DisputeResolution: 0x350632960846D2583F9f7e123Ec33de48448d0c4
 * PolineDAO:         0xcce1f7890c3611bd96404460af9cfd74a99fec13
 * PolinePurchase:    0x6659beb09d82192feb66c8896f524fad6d01bd28
 * TreasuryManager:   0xB62fDe7ca44403854bb98DAa80edD3357EF27A18
 * StorageRegistry:   0x9DFd21872D1aaaAc289527f17048072deE1C1e82
 */
contract DeployTreasury is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Read PolineDAO address from environment variable
        address polineDAO = vm.envAddress("POLINE_DAO");

        console.log("Deploying Treasury contracts...");
        console.log("Deployer:", deployer);
        console.log("PolineDAO:", polineDAO);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy TreasuryManager (governance = PolineDAO)
        TreasuryManager treasuryManager = new TreasuryManager(polineDAO);
        console.log("TreasuryManager deployed at:", address(treasuryManager));

        // 2. Deploy StorageRegistry (governance = PolineDAO)
        StorageRegistry storageRegistry = new StorageRegistry(
            polineDAO, // governance
            0.1 ether // initial budget (can be changed via governance)
        );
        console.log("StorageRegistry deployed at:", address(storageRegistry));

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("TreasuryManager:", address(treasuryManager));
        console.log("StorageRegistry:", address(storageRegistry));
        console.log(
            "\nUpdate CONTRACTS in votes/src/lib/contracts.ts with these addresses"
        );
    }
}
