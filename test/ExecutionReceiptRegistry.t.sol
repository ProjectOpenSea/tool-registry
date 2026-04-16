// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExecutionReceiptRegistry} from "../src/ExecutionReceiptRegistry.sol";
import {IExecutionReceiptRegistry, ExecutionReceipt} from "../src/interfaces/IExecutionReceiptRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ExecutionReceiptRegistryTest is Test {
    ExecutionReceiptRegistry public receiptRegistry;

    address admin = makeAddr("admin");
    address other = makeAddr("other");

    function setUp() public {
        receiptRegistry = new ExecutionReceiptRegistry(admin);
    }

    function _buildReceipt(bytes32 invocationId, uint256 toolId) internal view returns (ExecutionReceipt memory) {
        return ExecutionReceipt({
            invocationId: invocationId,
            toolId: toolId,
            caller: address(this),
            inputHash: keccak256("input"),
            outputHash: keccak256("output"),
            success: true,
            chargeAmount: 100,
            maxPrice: 1000,
            timestamp: block.timestamp
        });
    }

    function _hashReceipt(ExecutionReceipt memory receipt) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                receipt.invocationId,
                receipt.toolId,
                receipt.caller,
                receipt.inputHash,
                receipt.outputHash,
                receipt.success,
                receipt.chargeAmount,
                receipt.maxPrice,
                receipt.timestamp
            )
        );
    }

    function _hashLeaf(bytes32 data, uint256 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes1(0x00), data, index));
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly {
            let ptr := mload(0x40)
            mstore8(ptr, 0x01)
            mstore(add(ptr, 1), a)
            mstore(add(ptr, 33), b)
            value := keccak256(ptr, 65)
        }
    }

    function test_postBatch() public {
        bytes32 root = keccak256("root");
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IExecutionReceiptRegistry.BatchPosted(0, root, 5);
        receiptRegistry.postBatch(root, 5);

        assertEq(receiptRegistry.batchCount(), 1);
    }

    function test_postBatch_multiple() public {
        vm.startPrank(admin);
        receiptRegistry.postBatch(keccak256("root1"), 3);
        receiptRegistry.postBatch(keccak256("root2"), 7);
        vm.stopPrank();

        assertEq(receiptRegistry.batchCount(), 2);
    }

    function test_postBatch_revertsOnEmpty() public {
        vm.prank(admin);
        vm.expectRevert(IExecutionReceiptRegistry.EmptyBatch.selector);
        receiptRegistry.postBatch(keccak256("root"), 0);
    }

    function test_postBatch_revertsIfNotAdmin() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        receiptRegistry.postBatch(keccak256("root"), 5);
    }

    function test_batchCount_initiallyZero() public view {
        assertEq(receiptRegistry.batchCount(), 0);
    }

    function test_getBatch() public {
        bytes32 root = keccak256("root");
        vm.prank(admin);
        receiptRegistry.postBatch(root, 5);

        (bytes32 merkleRoot, uint256 receiptCount) = receiptRegistry.getBatch(0);
        assertEq(merkleRoot, root);
        assertEq(receiptCount, 5);
    }

    function test_getBatch_revertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IExecutionReceiptRegistry.BatchNotFound.selector, 0));
        receiptRegistry.getBatch(0);
    }

    function test_verifyReceipt_singleLeaf() public {
        // Build a single-leaf Merkle tree
        ExecutionReceipt memory receipt = _buildReceipt(bytes32(uint256(1)), 1);
        bytes32 receiptHash = _hashReceipt(receipt);
        bytes32 leaf = _hashLeaf(receiptHash, 0);
        // For a single-leaf tree, the root is the leaf itself
        bytes32 root = leaf;

        vm.prank(admin);
        receiptRegistry.postBatch(root, 1);

        bytes32[] memory proof = new bytes32[](0);
        assertTrue(receiptRegistry.verifyReceipt(receiptHash, proof, 0, 0));
    }

    function test_verifyReceipt_twoLeaves() public {
        ExecutionReceipt memory receipt0 = _buildReceipt(bytes32(uint256(1)), 1);
        ExecutionReceipt memory receipt1 = _buildReceipt(bytes32(uint256(2)), 2);

        bytes32 hash0 = _hashReceipt(receipt0);
        bytes32 hash1 = _hashReceipt(receipt1);

        bytes32 leaf0 = _hashLeaf(hash0, 0);
        bytes32 leaf1 = _hashLeaf(hash1, 1);

        bytes32 root;
        if (leaf0 <= leaf1) {
            root = _efficientHash(leaf0, leaf1);
        } else {
            root = _efficientHash(leaf1, leaf0);
        }

        vm.prank(admin);
        receiptRegistry.postBatch(root, 2);

        // Verify receipt 0 with leaf1 as proof
        bytes32[] memory proof0 = new bytes32[](1);
        proof0[0] = leaf1;
        assertTrue(receiptRegistry.verifyReceipt(hash0, proof0, 0, 0));

        // Verify receipt 1 with leaf0 as proof
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf0;
        assertTrue(receiptRegistry.verifyReceipt(hash1, proof1, 0, 1));
    }

    function test_verifyReceipt_invalidProof() public {
        bytes32 root = keccak256("realRoot");
        vm.prank(admin);
        receiptRegistry.postBatch(root, 1);

        bytes32[] memory proof = new bytes32[](0);
        // A random receipt hash won't match
        assertFalse(receiptRegistry.verifyReceipt(keccak256("fake"), proof, 0, 0));
    }

    function test_verifyReceipt_batchNotFound() public {
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(abi.encodeWithSelector(IExecutionReceiptRegistry.BatchNotFound.selector, 0));
        receiptRegistry.verifyReceipt(keccak256("hash"), proof, 0, 0);
    }

    function test_supportsInterface_IExecutionReceiptRegistry() public view {
        assertTrue(receiptRegistry.supportsInterface(type(IExecutionReceiptRegistry).interfaceId));
    }

    /// @dev Locks the hardcoded interface ID declared in the ERC spec.
    function test_interfaceId_IExecutionReceiptRegistry_matchesSpec() public pure {
        assertEq(type(IExecutionReceiptRegistry).interfaceId, bytes4(0x9e391f7c));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(receiptRegistry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_invalid() public view {
        assertFalse(receiptRegistry.supportsInterface(0xdeadbeef));
    }
}
