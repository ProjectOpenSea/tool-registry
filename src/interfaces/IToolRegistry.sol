// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Onchain configuration for a registered tool.
struct ToolConfig {
    address creator;
    string metadataURI;
    bytes32 manifestHash;
    address accessPredicate;
}

/// @title IToolRegistry
/// @notice Minimal onchain registry for AI agent tools.
/// @dev ERC-165 interface ID computed from type(IToolRegistry).interfaceId
interface IToolRegistry {
    event ToolRegistered(
        uint256 indexed toolId,
        address indexed creator,
        address indexed accessPredicate,
        string metadataURI,
        bytes32 manifestHash
    );
    event ToolMetadataUpdated(uint256 indexed toolId, string newURI, bytes32 newHash);
    event AccessPredicateUpdated(uint256 indexed toolId, address indexed newPredicate);

    error ToolNotFound(uint256 toolId);
    error NotToolCreator(uint256 toolId, address caller);
    error InvalidMetadataURI();
    error InvalidManifestHash();

    /// @notice The provided access predicate does not implement IAccessPredicate.
    /// @dev Reverts when the target contract claims ERC-165 support but either
    ///      reports `false` for the IAccessPredicate interface ID or reverts
    ///      when queried for it. Reverting on a supportsInterface query from a
    ///      self-declared ERC-165 contract is non-conformant, so the registry
    ///      treats it as a misconfigured predicate.
    error InvalidAccessPredicate(address predicate);

    function registerTool(string calldata metadataURI, bytes32 manifestHash, address accessPredicate)
        external
        returns (uint256 toolId);
    function updateToolMetadata(uint256 toolId, string calldata newURI, bytes32 newHash) external;
    function setAccessPredicate(uint256 toolId, address newPredicate) external;
    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory);
    function hasAccess(uint256 toolId, address account, bytes calldata data) external view returns (bool);
    function tryHasAccess(uint256 toolId, address account, bytes calldata data)
        external
        view
        returns (bool ok, bool granted);
    function toolCount() external view returns (uint256);

    /// @notice Returns a human-readable identifier for the registry implementation.
    /// @dev MUST return a non-empty string. Format is implementation-defined;
    ///      the reference implementation returns `"ToolRegistry"`. Consumers
    ///      SHOULD treat the value as opaque except for equality comparison.
    function name() external view returns (string memory);

    /// @notice Returns the implementation's version string.
    /// @dev MUST return a non-empty string. Format is implementation-defined;
    ///      the reference implementation uses `MAJOR.MINOR` (e.g. `"0.1"` for
    ///      pre-release, `"1.0"` for the first stable release, `"1.1"` /
    ///      `"2.0"` for subsequent revisions). The scheme intentionally omits
    ///      the patch component used in strict semver. Consumers SHOULD treat
    ///      the value as opaque except for equality comparison; ordering
    ///      semantics are implementation-defined.
    function version() external view returns (string memory);
}
