// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IToolRegistry, ToolConfig, AccessMode} from "./interfaces/IToolRegistry.sol";
import {IToolAccessRegistry} from "./interfaces/IToolAccessRegistry.sol";

contract ToolRegistry is IToolRegistry, ERC165 {
    uint256 private _nextToolId = 1;
    mapping(uint256 => ToolConfig) private _tools;

    IToolAccessRegistry public accessRegistry;
    address public immutable deployer;
    bool private _initialized;

    event Initialized(address accessRegistry);

    error AlreadyInitialized();
    error InvalidAccessRegistry();
    error NotDeployer();
    error NotInitialized();

    constructor() {
        deployer = msg.sender;
    }

    function initialize(address _accessRegistry) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (_initialized) revert AlreadyInitialized();
        if (_accessRegistry == address(0)) revert InvalidAccessRegistry();
        _initialized = true;
        accessRegistry = IToolAccessRegistry(_accessRegistry);

        emit Initialized(_accessRegistry);
    }

    function registerTool(string calldata metadataURI, AccessMode accessMode) external returns (uint256 toolId) {
        if (bytes(metadataURI).length == 0) revert InvalidMetadataURI();

        toolId = _nextToolId++;
        _tools[toolId] =
            ToolConfig({creator: msg.sender, metadataURI: metadataURI, accessMode: accessMode, active: true});

        emit ToolRegistered(toolId, msg.sender, accessMode);
    }

    function updateToolMetadata(uint256 toolId, string calldata newURI) external {
        _requireExists(toolId);
        _requireCreator(toolId);
        if (bytes(newURI).length == 0) revert InvalidMetadataURI();

        string memory oldURI = _tools[toolId].metadataURI;
        _tools[toolId].metadataURI = newURI;
        emit ToolMetadataUpdated(toolId, oldURI, newURI);
    }

    function deactivateTool(uint256 toolId) external {
        _requireExists(toolId);
        _requireCreator(toolId);
        if (!_tools[toolId].active) revert ToolAlreadyInactive(toolId);

        _tools[toolId].active = false;
        emit ToolDeactivated(toolId);
    }

    function reactivateTool(uint256 toolId) external {
        _requireExists(toolId);
        _requireCreator(toolId);
        if (_tools[toolId].active) revert ToolAlreadyActive(toolId);

        _tools[toolId].active = true;
        emit ToolReactivated(toolId);
    }

    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory) {
        _requireExists(toolId);
        return _tools[toolId];
    }

    function toolCount() external view returns (uint256) {
        return _nextToolId - 1;
    }

    function hasAccess(uint256 toolId, address account) external view returns (bool) {
        _requireExists(toolId);
        if (address(accessRegistry) == address(0)) revert NotInitialized();
        return accessRegistry.hasAccess(toolId, account);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IToolRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _requireExists(uint256 toolId) internal view {
        if (_tools[toolId].creator == address(0)) revert ToolNotFound(toolId);
    }

    function _requireCreator(uint256 toolId) internal view {
        if (_tools[toolId].creator != msg.sender) revert NotToolCreator(toolId, msg.sender);
    }
}
