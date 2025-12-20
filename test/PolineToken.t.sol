// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/PolineToken.sol";

contract PolineTokenTest is Test {
    PolineToken public token;
    address public admin;
    address public user1;
    address public user2;

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.prank(admin);
        token = new PolineToken("Poline Governance", "POLINE", admin);
    }

    function test_InitialState() public view {
        assertEq(token.name(), "Poline Governance");
        assertEq(token.symbol(), "POLINE");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
        assertTrue(token.hasRole(token.SLASHER_ROLE(), admin));
    }

    function test_Mint() public {
        vm.prank(admin);
        token.mint(user1, 100 ether, "Initial allocation");

        assertEq(token.balanceOf(user1), 100 ether);
    }

    function test_MintOnlyMinter() public {
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user2, 100 ether, "Unauthorized mint");
    }

    function test_Slash() public {
        vm.startPrank(admin);
        token.mint(user1, 100 ether, "Initial allocation");
        token.slash(user1, 30 ether, "Penalty for wrong vote");
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 70 ether);
    }

    function test_SlashInsufficientBalance() public {
        vm.startPrank(admin);
        token.mint(user1, 50 ether, "Initial allocation");

        vm.expectRevert(
            abi.encodeWithSelector(
                PolineToken.InsufficientBalance.selector,
                user1,
                100 ether,
                50 ether
            )
        );
        token.slash(user1, 100 ether, "Too much");
        vm.stopPrank();
    }

    function test_TransferBlocked() public {
        vm.prank(admin);
        token.mint(user1, 100 ether, "Initial allocation");

        vm.prank(user1);
        vm.expectRevert(PolineToken.TransferNotAllowed.selector);
        token.transfer(user2, 50 ether);
    }

    function test_TransferFromBlocked() public {
        vm.prank(admin);
        token.mint(user1, 100 ether, "Initial allocation");

        vm.prank(user1);
        vm.expectRevert(PolineToken.TransferNotAllowed.selector);
        token.transferFrom(user1, user2, 50 ether);
    }

    function test_ApproveBlocked() public {
        vm.prank(user1);
        vm.expectRevert(PolineToken.TransferNotAllowed.selector);
        token.approve(user2, 50 ether);
    }

    function test_VotingPowerDelegation() public {
        vm.prank(admin);
        token.mint(user1, 100 ether, "Initial allocation");

        // Before delegation, voting power is 0
        assertEq(token.getVotes(user1), 0);

        // Self-delegate to activate voting power
        vm.prank(user1);
        token.delegate(user1);

        assertEq(token.getVotes(user1), 100 ether);
        assertEq(token.getVotingPower(user1), 100 ether);
    }

    function test_VotingPowerDelegateToOther() public {
        vm.prank(admin);
        token.mint(user1, 100 ether, "Initial allocation");

        vm.prank(user1);
        token.delegate(user2);

        assertEq(token.getVotes(user1), 0);
        assertEq(token.getVotes(user2), 100 ether);
    }
}
