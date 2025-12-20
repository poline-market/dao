// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/PolineToken.sol";
import "../contracts/StakingManager.sol";

contract StakingManagerTest is Test {
    PolineToken public token;
    StakingManager public staking;
    address public admin;
    address public user1;
    address public user2;

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(admin);
        token = new PolineToken("Poline", "POLINE", admin);
        staking = new StakingManager(address(token), admin);

        // Grant slasher role to staking manager
        token.grantRole(token.SLASHER_ROLE(), address(staking));

        // Mint tokens to users
        token.mint(user1, 500 ether, "Initial");
        token.mint(user2, 500 ether, "Initial");
        vm.stopPrank();
    }

    function test_Stake() public {
        vm.prank(user1);
        staking.stake(100 ether);

        assertEq(staking.getStake(user1), 100 ether);
        assertTrue(staking.isOracle(user1));
        assertEq(staking.totalStaked(), 100 ether);
    }

    function test_StakeMinimumForOracle() public {
        vm.prank(user1);
        staking.stake(50 ether); // Below minimum (100 ether default)

        assertEq(staking.getStake(user1), 50 ether);
        assertFalse(staking.isOracle(user1)); // Not oracle yet

        vm.prank(user1);
        staking.stake(50 ether); // Now at 100 ether

        assertTrue(staking.isOracle(user1)); // Now is oracle
    }

    function test_RequestUnstake() public {
        vm.prank(user1);
        staking.stake(100 ether);

        vm.prank(user1);
        staking.requestUnstake();

        assertFalse(staking.canUnstake(user1)); // Cooldown not passed
    }

    function test_CompleteUnstake() public {
        vm.prank(user1);
        staking.stake(100 ether);

        vm.prank(user1);
        staking.requestUnstake();

        // Fast forward past cooldown (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(user1);
        staking.completeUnstake();

        assertEq(staking.getStake(user1), 0);
        assertFalse(staking.isOracle(user1));
        assertEq(staking.totalStaked(), 0);
    }

    function test_CompleteUnstakeBeforeCooldownReverts() public {
        vm.prank(user1);
        staking.stake(100 ether);

        vm.prank(user1);
        staking.requestUnstake();

        // Only wait 1 day
        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vm.expectRevert();
        staking.completeUnstake();
    }

    function test_CancelUnstake() public {
        vm.startPrank(user1);
        staking.stake(100 ether);
        staking.requestUnstake();
        staking.cancelUnstake();
        vm.stopPrank();

        assertEq(staking.timeUntilUnstake(user1), type(uint256).max);
    }

    function test_SlashStake() public {
        vm.prank(user1);
        staking.stake(100 ether);

        vm.prank(admin);
        staking.slashStake(user1, 30 ether, "Wrong vote");

        assertEq(staking.getStake(user1), 70 ether);
        assertEq(token.balanceOf(user1), 470 ether); // 500 - 30 slashed
    }

    function test_SlashBelowMinimumRemovesOracle() public {
        vm.prank(user1);
        staking.stake(100 ether);

        assertTrue(staking.isOracle(user1));

        vm.prank(admin);
        staking.slashStake(user1, 50 ether, "Wrong vote");

        assertFalse(staking.isOracle(user1)); // Below minimum now
    }

    function test_UpdateParameters() public {
        vm.prank(admin);
        staking.updateParameters(14 days, 200 ether);

        assertEq(staking.unstakeCooldown(), 14 days);
        assertEq(staking.minimumStake(), 200 ether);
    }

    function test_TimeUntilUnstake() public {
        vm.startPrank(user1);
        staking.stake(100 ether);
        staking.requestUnstake();
        vm.stopPrank();

        uint256 timeLeft = staking.timeUntilUnstake(user1);
        assertGt(timeLeft, 0);
        assertLe(timeLeft, 7 days);
    }
}
