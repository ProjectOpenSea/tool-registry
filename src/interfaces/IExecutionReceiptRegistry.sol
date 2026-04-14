// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Canonical offchain schema for execution receipts. The registry does
///         not validate field semantics onchain — receipts are hashed offchain
///         and verified via Merkle proof against a posted root.
struct ExecutionReceipt {
    bytes32 invocationId;
    uint256 toolId;
    address caller;
    bytes32 inputHash;
    bytes32 outputHash;
    bool success;
    uint256 chargeAmount;
    uint256 maxPrice;
    uint256 timestamp;
}

/// @title IExecutionReceiptRegistry
/// @notice Batch-posted Merkle roots of tool execution receipts.
/// @dev ERC-165 interface ID computed from type(IExecutionReceiptRegistry).interfaceId
interface IExecutionReceiptRegistry {
    event BatchPosted(uint256 indexed batchId, bytes32 merkleRoot, uint256 receiptCount);

    error EmptyBatch();
    error BatchNotFound(uint256 batchId);
    error InvalidProof();
    error Unauthorized();

    function postBatch(bytes32 merkleRoot, uint256 receiptCount) external;

    function verifyReceipt(bytes32 receiptHash, bytes32[] calldata proof, uint256 batchId, uint256 index)
        external
        view
        returns (bool valid);

    function getBatch(uint256 batchId) external view returns (bytes32 merkleRoot, uint256 receiptCount);

    function batchCount() external view returns (uint256);
}
