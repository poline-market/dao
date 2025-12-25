// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/UserProfile.sol";

contract UserProfileTest is Test {
    UserProfile public userProfile;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    function setUp() public {
        userProfile = new UserProfile();
    }

    // ============ Avatar Tests ============

    function test_SetAvatar() public {
        vm.prank(alice);
        userProfile.setAvatar("ipfs://QmTest123", 1);

        UserProfile.Profile memory profile = userProfile.getProfile(alice);
        assertEq(profile.avatarURI, "ipfs://QmTest123");
        assertEq(profile.avatarType, 1);
        assertTrue(profile.updatedAt > 0);
    }

    function test_SetAvatarIdenticon() public {
        vm.prank(alice);
        userProfile.setAvatar("", 0);

        UserProfile.Profile memory profile = userProfile.getProfile(alice);
        assertEq(profile.avatarURI, "");
        assertEq(profile.avatarType, 0);
    }

    // ============ Name Tests ============

    function test_SetNameAndBio() public {
        vm.prank(alice);
        userProfile.setNameAndBio("Alice_DAO", "I love decentralization!");

        UserProfile.Profile memory profile = userProfile.getProfile(alice);
        assertEq(profile.displayName, "Alice_DAO");
        assertEq(profile.bio, "I love decentralization!");
    }

    function test_NameToAddressLookup() public {
        vm.prank(alice);
        userProfile.setNameAndBio("Alice_DAO", "");

        address found = userProfile.getAddressByName("alice_dao"); // lowercase
        assertEq(found, alice);

        found = userProfile.getAddressByName("ALICE_DAO"); // uppercase
        assertEq(found, alice);
    }

    function test_RevertNameAlreadyTaken() public {
        vm.prank(alice);
        userProfile.setNameAndBio("UniqueUser", "");

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                UserProfile.NameAlreadyTaken.selector,
                "UniqueUser"
            )
        );
        userProfile.setNameAndBio("UniqueUser", "");
    }

    function test_RevertNameTooShort() public {
        vm.prank(alice);
        vm.expectRevert(UserProfile.NameTooShort.selector);
        userProfile.setNameAndBio("AB", "");
    }

    function test_RevertNameTooLong() public {
        vm.prank(alice);
        vm.expectRevert(UserProfile.NameTooLong.selector);
        userProfile.setNameAndBio("ThisNameIsWayTooLongForTheSystem123", "");
    }

    function test_RevertInvalidCharacter() public {
        vm.prank(alice);
        vm.expectRevert(UserProfile.InvalidCharacter.selector);
        userProfile.setNameAndBio("Invalid@Name", "");
    }

    function test_NameChangeReleasesOld() public {
        vm.prank(alice);
        userProfile.setNameAndBio("OldName", "");

        vm.prank(alice);
        userProfile.setNameAndBio("NewName", "");

        // Old name should be available
        assertTrue(userProfile.isNameAvailable("OldName"));

        // New name should be taken
        assertFalse(userProfile.isNameAvailable("NewName"));
    }

    function test_IsNameAvailable() public {
        assertTrue(userProfile.isNameAvailable("AvailableName"));

        vm.prank(alice);
        userProfile.setNameAndBio("TakenName", "");

        assertFalse(userProfile.isNameAvailable("TakenName"));
        assertFalse(userProfile.isNameAvailable("takenname")); // case insensitive
    }

    // ============ Delegate Tests ============

    function test_SetDelegateInfo() public {
        vm.prank(alice);
        userProfile.setDelegateInfo(
            true,
            "I will vote responsibly for the community!"
        );

        UserProfile.Profile memory profile = userProfile.getProfile(alice);
        assertTrue(profile.isDelegate);
        assertEq(
            profile.delegateStatement,
            "I will vote responsibly for the community!"
        );
    }

    function test_DelegateStatusChanged() public {
        vm.prank(alice);
        userProfile.setDelegateInfo(true, "Statement");

        vm.prank(alice);
        userProfile.setDelegateInfo(false, "");

        UserProfile.Profile memory profile = userProfile.getProfile(alice);
        assertFalse(profile.isDelegate);
    }

    // ============ Preferences Tests ============

    function test_SetPreferences() public {
        string
            memory prefs = '{"theme":"dark","language":"pt-BR","currency":"BRL"}';

        vm.prank(alice);
        userProfile.setPreferences(prefs);

        UserProfile.Profile memory profile = userProfile.getProfile(alice);
        assertEq(profile.preferences, prefs);
    }

    // ============ Social Links Tests ============

    function test_SetSocialLinks() public {
        string memory links = '{"twitter":"@alice_dao","telegram":"@alice"}';

        vm.prank(alice);
        userProfile.setSocialLinks(links);

        UserProfile.Profile memory profile = userProfile.getProfile(alice);
        assertEq(profile.socialLinks, links);
    }

    // ============ Full Profile Tests ============

    function test_SetFullProfile() public {
        UserProfile.Profile memory newProfile = UserProfile.Profile({
            avatarURI: "ipfs://QmAvatar",
            displayName: "FullUser",
            bio: "Complete profile test",
            socialLinks: '{"twitter":"@full"}',
            preferences: '{"theme":"light"}',
            avatarType: 2,
            isDelegate: true,
            delegateStatement: "Full delegate",
            updatedAt: 0
        });

        vm.prank(alice);
        userProfile.setProfile(newProfile);

        UserProfile.Profile memory profile = userProfile.getProfile(alice);
        assertEq(profile.avatarURI, "ipfs://QmAvatar");
        assertEq(profile.displayName, "FullUser");
        assertEq(profile.bio, "Complete profile test");
        assertEq(profile.avatarType, 2);
        assertTrue(profile.isDelegate);
    }

    // ============ Batch Query Tests ============

    function test_GetProfiles() public {
        vm.prank(alice);
        userProfile.setNameAndBio("Alice", "");

        vm.prank(bob);
        userProfile.setNameAndBio("Bob123", "");

        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        UserProfile.Profile[] memory profiles = userProfile.getProfiles(users);

        assertEq(profiles.length, 2);
        assertEq(profiles[0].displayName, "Alice");
        assertEq(profiles[1].displayName, "Bob123");
    }

    // ============ Event Tests ============

    function test_EmitsProfileUpdated() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit UserProfile.ProfileUpdated(alice, block.timestamp);
        userProfile.setAvatar("test", 1);
    }

    function test_EmitsDelegateStatusChanged() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit UserProfile.DelegateStatusChanged(alice, true);
        userProfile.setDelegateInfo(true, "Statement");
    }

    function test_EmitsNameClaimed() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit UserProfile.NameClaimed(alice, "NewName");
        userProfile.setNameAndBio("NewName", "");
    }
}
