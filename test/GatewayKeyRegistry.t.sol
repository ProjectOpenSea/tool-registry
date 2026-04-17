// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GatewayKeyRegistry} from "../src/GatewayKeyRegistry.sol";
import {IGatewayKeyRegistry} from "../src/interfaces/IGatewayKeyRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

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

    function test_renounceOwnership_reverts() public {
        vm.prank(admin);
        vm.expectRevert(GatewayKeyRegistry.OwnershipCannotBeRenounced.selector);
        keyRegistry.renounceOwnership();

        assertEq(keyRegistry.owner(), admin);
    }

    function test_renounceOwnership_revertsIfNotOwner() public {
        // OZ Ownable's onlyOwner check runs first, so non-owners see
        // OwnableUnauthorizedAccount before the override's revert.
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        keyRegistry.renounceOwnership();
    }

    function test_transferOwnership_twoStep() public {
        // Ownable2Step: transferOwnership sets a pending owner that must accept
        // before taking effect. Protects against mistyped transfer targets.
        // The emitted OwnershipTransferStarted event is the observable hook
        // that downstream monitoring (multi-sig rotation alerts, governance
        // dashboards) uses to detect an in-flight admin rotation; pin it.
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit Ownable2Step.OwnershipTransferStarted(admin, other);
        keyRegistry.transferOwnership(other);
        assertEq(keyRegistry.pendingOwner(), other);
        assertEq(keyRegistry.owner(), admin);

        vm.prank(other);
        keyRegistry.acceptOwnership();
        assertEq(keyRegistry.owner(), other);
        assertEq(keyRegistry.pendingOwner(), address(0));
    }

    function test_transferOwnership_canCancelPendingTransfer() public {
        // Ownable2Step accepts address(0) as a pending-owner, which nobody can
        // accept from. This is the documented cancel mechanism: after a
        // mistyped transfer, the current owner clears the pending slot before
        // the wrong address accepts. M2's two-step safety depends on this.
        vm.startPrank(admin);
        keyRegistry.transferOwnership(other);
        assertEq(keyRegistry.pendingOwner(), other);

        keyRegistry.transferOwnership(address(0));
        assertEq(keyRegistry.pendingOwner(), address(0));
        assertEq(keyRegistry.owner(), admin);
        vm.stopPrank();

        // The originally-pending address can no longer accept.
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        keyRegistry.acceptOwnership();
    }

    function test_transferOwnership_pendingOwnerMustAccept() public {
        vm.prank(admin);
        keyRegistry.transferOwnership(other);

        // A non-pending-owner account cannot accept.
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        keyRegistry.acceptOwnership();

        assertEq(keyRegistry.owner(), admin);
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
