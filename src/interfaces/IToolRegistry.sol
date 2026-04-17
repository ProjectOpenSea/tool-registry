// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Access control mode for a registered tool.
enum AccessMode {
    OPEN,
    NFT_GATED,
    SUBSCRIPTION
}

/// @notice Onchain configuration for a registered tool.
struct ToolConfig {
    address creator;
    string metadataURI;
    bytes32 manifestHash;
    AccessMode accessMode;
    bool active;
}

/// @title IToolRegistry
/// @notice Onchain registry for AI agent tools.
/// @dev ERC-165 interface ID computed from type(IToolRegistry).interfaceId
interface IToolRegistry {
    event ToolRegistered(uint256 indexed toolId, address indexed creator, AccessMode accessMode, bytes32 manifestHash);
    /// @notice Emitted when a tool's metadata URI and/or manifest hash is updated.
    /// @dev Emits prior and new URI and hash so indexers and gateways can diff
    ///      and commit without racing the creator. `manifestHash` is the binding
    ///      commitment; `metadataURI` alone is mutable pointer state.
    event ToolMetadataUpdated(uint256 indexed toolId, string oldURI, string newURI, bytes32 oldHash, bytes32 newHash);
    event ToolDeactivated(uint256 indexed toolId);
    event ToolReactivated(uint256 indexed toolId);

    error ToolNotFound(uint256 toolId);
    error NotToolCreator(uint256 toolId, address caller);
    error ToolAlreadyActive(uint256 toolId);
    error ToolAlreadyInactive(uint256 toolId);
    /// @notice The provided metadata URI is invalid.
    /// @dev Implementations MUST revert with this error when `metadataURI` is
    ///      the empty string. Implementations MAY additionally reject URIs
    ///      that fail implementation-specific validation.
    error InvalidMetadataURI();
    /// @notice The provided manifest hash is `bytes32(0)`.
    /// @dev keccak256 of any real content cannot produce bytes32(0), so a zero
    ///      hash is semantically meaningless as a commitment.
    error InvalidManifestHash();

    function registerTool(string calldata metadataURI, bytes32 manifestHash, AccessMode accessMode)
        external
        returns (uint256 toolId);
    function updateToolMetadata(uint256 toolId, string calldata newURI, bytes32 newHash) external;
    function deactivateTool(uint256 toolId) external;
    function reactivateTool(uint256 toolId) external;
    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory);
    /// @dev If the tool is not `active`, MUST return false regardless of mode.
    ///      For OPEN tools, MUST return true when active. For NFT_GATED,
    ///      delegates to the Access Registry. For SUBSCRIPTION tools, MUST
    ///      return false; `balanceOf` alone cannot disambiguate the tokenId
    ///      needed to check ERC-5643 expiration. Consumers MUST use
    ///      `IToolAccessRegistry.hasAccessWithProof` for SUBSCRIPTION tools.
    function hasAccess(uint256 toolId, address account) external view returns (bool);
    function toolCount() external view returns (uint256);
}
