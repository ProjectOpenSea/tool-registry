// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GatewayKeyRegistry} from "../src/GatewayKeyRegistry.sol";
import {IGatewayKeyRegistry} from "../src/interfaces/IGatewayKeyRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GatewayKeyRegistryTest is Test {
    GatewayKeyRegistry public keyRegistry;

    address admin = makeAddr("admin");
    address keyAddr = makeAddr("gatewayKey");
    address keyAddr2 = makeAddr("gatewayKey2");
    address other = makeAddr("other");

    function setUp() public {
        keyRegistry = new GatewayKeyRegistry(admin);
    }

    function test_addGatewayKey() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IGatewayKeyRegistry.GatewayKeyAdded(keyAddr);
        keyRegistry.addGatewayKey(keyAddr);

        assertTrue(keyRegistry.isValidGatewayKey(keyAddr));
    }

    function test_addGatewayKey_revertsIfNotAdmin() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        keyRegistry.addGatewayKey(keyAddr);
    }

    function test_addGatewayKey_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IGatewayKeyRegistry.InvalidKey.selector);
        keyRegistry.addGatewayKey(address(0));
    }

    function test_addGatewayKey_revertsIfAlreadyRegistered() public {
        vm.startPrank(admin);
        keyRegistry.addGatewayKey(keyAddr);

        vm.expectRevert(abi.encodeWithSelector(IGatewayKeyRegistry.KeyAlreadyRegistered.selector, keyAddr));
        keyRegistry.addGatewayKey(keyAddr);
        vm.stopPrank();
    }

    function test_removeGatewayKey() public {
        vm.startPrank(admin);
        keyRegistry.addGatewayKey(keyAddr);

        vm.expectEmit(true, false, false, false);
        emit IGatewayKeyRegistry.GatewayKeyRemoved(keyAddr);
        keyRegistry.removeGatewayKey(keyAddr);
        vm.stopPrank();

        assertFalse(keyRegistry.isValidGatewayKey(keyAddr));
    }

    function test_removeGatewayKey_revertsIfNotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGatewayKeyRegistry.KeyNotRegistered.selector, keyAddr));
        keyRegistry.removeGatewayKey(keyAddr);
    }

    function test_removeGatewayKey_revertsIfNotAdmin() public {
        vm.prank(admin);
        keyRegistry.addGatewayKey(keyAddr);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        keyRegistry.removeGatewayKey(keyAddr);
    }

    function test_isValidGatewayKey_falseByDefault() public view {
        assertFalse(keyRegistry.isValidGatewayKey(keyAddr));
    }

    function test_multipleKeys() public {
        vm.startPrank(admin);
        keyRegistry.addGatewayKey(keyAddr);
        keyRegistry.addGatewayKey(keyAddr2);
        vm.stopPrank();

        assertTrue(keyRegistry.isValidGatewayKey(keyAddr));
        assertTrue(keyRegistry.isValidGatewayKey(keyAddr2));

        vm.prank(admin);
        keyRegistry.removeGatewayKey(keyAddr);

        assertFalse(keyRegistry.isValidGatewayKey(keyAddr));
        assertTrue(keyRegistry.isValidGatewayKey(keyAddr2));
    }

    function test_reAddKeyAfterRemoval() public {
        vm.startPrank(admin);
        keyRegistry.addGatewayKey(keyAddr);
        keyRegistry.removeGatewayKey(keyAddr);
        keyRegistry.addGatewayKey(keyAddr);
        vm.stopPrank();

        assertTrue(keyRegistry.isValidGatewayKey(keyAddr));
    }

    function test_supportsInterface_IGatewayKeyRegistry() public view {
        assertTrue(keyRegistry.supportsInterface(type(IGatewayKeyRegistry).interfaceId));
    }

    /// @dev Locks the hardcoded interface ID declared in the ERC spec.
    function test_interfaceId_IGatewayKeyRegistry_matchesSpec() public pure {
        assertEq(type(IGatewayKeyRegistry).interfaceId, bytes4(0xf5c37176));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(keyRegistry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_invalid() public view {
        assertFalse(keyRegistry.supportsInterface(0xdeadbeef));
    }
}
