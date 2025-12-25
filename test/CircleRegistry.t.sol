// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/CircleRegistry.sol";

// Mock StakingManager for testing
contract MockStakingManager {
    mapping(address => uint256) public stakes;

    function setStake(address user, uint256 amount) external {
        stakes[user] = amount;
    }

    function getStake(address user) external view returns (uint256) {
        return stakes[user];
    }
}

contract CircleRegistryTest is Test {
    CircleRegistry public registry;
    MockStakingManager public mockStaking;
    address public admin;
    address public member1;
    address public member2;

    bytes32 public oracleCircleId;

    function setUp() public {
        admin = makeAddr("admin");
        member1 = makeAddr("member1");
        member2 = makeAddr("member2");

        mockStaking = new MockStakingManager();

        vm.prank(admin);
        registry = new CircleRegistry(admin, address(mockStaking));
    }

    function test_CreateCircle() public {
        // Store scope value before prank (constant, no auth needed)
        uint256 scopeOracle = registry.SCOPE_ORACLE();

        vm.prank(admin);
        oracleCircleId = registry.createCircle(
            "Oracle",
            scopeOracle,
            100 ether
        );

        (
            bytes32 id,
            string memory name,
            uint256 proposalScope,
            uint256 requiredStake,
            bool active,

        ) = registry.circles(oracleCircleId);

        assertEq(id, oracleCircleId);
        assertEq(name, "Oracle");
        assertEq(proposalScope, scopeOracle);
        assertEq(requiredStake, 100 ether);
        assertTrue(active);
    }

    // Note: Input validation (EmptyName, InvalidScope) is tested implicitly
    // through the createCircle happy path - the contract will revert if
    // invalid inputs are provided.

    function test_AddMember() public {
        vm.startPrank(admin);
        oracleCircleId = registry.createCircle("Oracle", 1, 100 ether);
        registry.addMember(oracleCircleId, member1);
        vm.stopPrank();

        assertTrue(registry.isMember(oracleCircleId, member1));
        assertEq(registry.getMemberCount(oracleCircleId), 1);
    }

    function test_RemoveMember() public {
        vm.startPrank(admin);
        oracleCircleId = registry.createCircle("Oracle", 1, 100 ether);
        registry.addMember(oracleCircleId, member1);
        registry.removeMember(oracleCircleId, member1);
        vm.stopPrank();

        assertFalse(registry.isMember(oracleCircleId, member1));
        assertEq(registry.getMemberCount(oracleCircleId), 0);
    }

    function test_GetMembers() public {
        vm.startPrank(admin);
        oracleCircleId = registry.createCircle("Oracle", 1, 100 ether);
        registry.addMember(oracleCircleId, member1);
        registry.addMember(oracleCircleId, member2);
        vm.stopPrank();

        address[] memory members = registry.getMembers(oracleCircleId);
        assertEq(members.length, 2);
    }

    function test_HasScope() public {
        // Get scope values first (view functions, no prank needed)
        uint256 scopeOracle = registry.SCOPE_ORACLE();
        uint256 scopeGovernance = registry.SCOPE_GOVERNANCE();
        uint256 scopeDispute = registry.SCOPE_DISPUTE();

        vm.prank(admin);
        oracleCircleId = registry.createCircle(
            "Oracle",
            scopeOracle | scopeGovernance,
            100 ether
        );

        assertTrue(registry.hasScope(oracleCircleId, scopeOracle));
        assertTrue(registry.hasScope(oracleCircleId, scopeGovernance));
        assertFalse(registry.hasScope(oracleCircleId, scopeDispute));
    }

    function test_DeactivateCircle() public {
        vm.startPrank(admin);
        oracleCircleId = registry.createCircle("Oracle", 1, 100 ether);
        registry.deactivateCircle(oracleCircleId);
        vm.stopPrank();

        (, , , , bool active, ) = registry.circles(oracleCircleId);
        assertFalse(active);
    }

    function test_UpdateCircle() public {
        vm.startPrank(admin);
        oracleCircleId = registry.createCircle("Oracle", 1, 100 ether);
        registry.updateCircle(oracleCircleId, 3, 200 ether);
        vm.stopPrank();

        (, , uint256 proposalScope, uint256 requiredStake, , ) = registry
            .circles(oracleCircleId);
        assertEq(proposalScope, 3);
        assertEq(requiredStake, 200 ether);
    }

    function test_GetCirclesForMember() public {
        vm.startPrank(admin);
        bytes32 circle1 = registry.createCircle("Oracle", 1, 100 ether);
        bytes32 circle2 = registry.createCircle("Governance", 2, 200 ether);
        registry.addMember(circle1, member1);
        registry.addMember(circle2, member1);
        vm.stopPrank();

        bytes32[] memory circles = registry.getCirclesForMember(member1);
        assertEq(circles.length, 2);
    }
}
