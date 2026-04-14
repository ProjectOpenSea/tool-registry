// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IExecutionReceiptRegistry} from "./interfaces/IExecutionReceiptRegistry.sol";

contract ExecutionReceiptRegistry is IExecutionReceiptRegistry, ERC165, Ownable {
    struct Batch {
        bytes32 merkleRoot;
        uint256 receiptCount;
    }

    Batch[] private _batches;

    constructor(address admin) Ownable(admin) {}

    function postBatch(bytes32 merkleRoot, uint256 receiptCount) external onlyOwner {
        if (receiptCount == 0) revert EmptyBatch();

        uint256 batchId = _batches.length;
        _batches.push(Batch({merkleRoot: merkleRoot, receiptCount: receiptCount}));

        emit BatchPosted(batchId, merkleRoot, receiptCount);
    }

    function verifyReceipt(bytes32 receiptHash, bytes32[] calldata proof, uint256 batchId, uint256 index)
        external
        view
        returns (bool valid)
    {
        if (batchId >= _batches.length) revert BatchNotFound(batchId);

        bytes32 computedHash = _hashLeaf(receiptHash, index);
        uint256 proofLen = proof.length;
        for (uint256 i; i < proofLen;) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = _efficientHash(computedHash, proofElement);
            } else {
                computedHash = _efficientHash(proofElement, computedHash);
            }
            unchecked {
                ++i;
            }
        }

        return computedHash == _batches[batchId].merkleRoot;
    }

    function getBatch(uint256 batchId) external view returns (bytes32 merkleRoot, uint256 receiptCount) {
        if (batchId >= _batches.length) revert BatchNotFound(batchId);
        Batch storage b = _batches[batchId];
        return (b.merkleRoot, b.receiptCount);
    }

    function batchCount() external view returns (uint256) {
        return _batches.length;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IExecutionReceiptRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Leaf prefix 0x00 prevents second-preimage attacks where a
    ///      crafted leaf collides with an internal node hash.
    function _hashLeaf(bytes32 data, uint256 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes1(0x00), data, index));
    }

    /// @dev Internal-node prefix 0x01 completes domain separation with
    ///      the 0x00 leaf prefix, following the OpenZeppelin convention.
    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly {
            let ptr := mload(0x40)
            mstore8(ptr, 0x01)
            mstore(add(ptr, 1), a)
            mstore(add(ptr, 33), b)
            value := keccak256(ptr, 65)
        }
    }
}
