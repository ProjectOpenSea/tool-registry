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
    AccessMode accessMode;
    bool active;
}

/// @title IToolRegistry
/// @notice Onchain registry for AI agent tools.
/// @dev ERC-165 interface ID computed from type(IToolRegistry).interfaceId
interface IToolRegistry {
    event ToolRegistered(uint256 indexed toolId, address indexed creator, AccessMode accessMode);
    event ToolMetadataUpdated(uint256 indexed toolId, string newURI);
    event ToolDeactivated(uint256 indexed toolId);
    event ToolReactivated(uint256 indexed toolId);

    error ToolNotFound(uint256 toolId);
    error NotToolCreator(uint256 toolId, address caller);
    error ToolAlreadyActive(uint256 toolId);
    error ToolAlreadyInactive(uint256 toolId);
    error InvalidMetadataURI();

    function registerTool(string calldata metadataURI, AccessMode accessMode) external returns (uint256 toolId);
    function updateToolMetadata(uint256 toolId, string calldata newURI) external;
    function deactivateTool(uint256 toolId) external;
    function reactivateTool(uint256 toolId) external;
    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory);
    function hasAccess(uint256 toolId, address account) external view returns (bool);
    function toolCount() external view returns (uint256);
}
