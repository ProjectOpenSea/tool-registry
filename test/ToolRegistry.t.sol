// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";
import {ToolAccessRegistry} from "../src/ToolAccessRegistry.sol";
import {IToolRegistry, ToolConfig, AccessMode} from "../src/interfaces/IToolRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract ToolRegistryTest is Test {
    ToolRegistry public registry;
    ToolAccessRegistry public accessRegistry;

    address creator = makeAddr("creator");
    address other = makeAddr("other");
    string constant META_URI = "https://example.com/tool.json";
    string constant META_URI_2 = "ipfs://QmUpdated";

    function setUp() public {
        registry = new ToolRegistry();
        accessRegistry = new ToolAccessRegistry(address(registry));
        registry.initialize(address(accessRegistry));
    }

    function test_registerTool_open() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);
        assertEq(toolId, 1);

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(config.creator, creator);
        assertEq(config.metadataURI, META_URI);
        assertEq(uint256(config.accessMode), uint256(AccessMode.OPEN));
        assertTrue(config.active);
    }

    function test_registerTool_nftGated() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.NFT_GATED);
        assertEq(toolId, 1);

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(uint256(config.accessMode), uint256(AccessMode.NFT_GATED));
    }

    function test_registerTool_subscription() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.SUBSCRIPTION);
        assertEq(toolId, 1);

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(uint256(config.accessMode), uint256(AccessMode.SUBSCRIPTION));
    }

    function test_registerTool_autoIncrementingIds() public {
        vm.startPrank(creator);
        uint256 id1 = registry.registerTool(META_URI, AccessMode.OPEN);
        uint256 id2 = registry.registerTool(META_URI, AccessMode.OPEN);
        uint256 id3 = registry.registerTool(META_URI, AccessMode.OPEN);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
    }

    function test_registerTool_emitsEvent() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit IToolRegistry.ToolRegistered(1, creator, AccessMode.OPEN);
        registry.registerTool(META_URI, AccessMode.OPEN);
    }

    function test_registerTool_revertsOnEmptyURI() public {
        vm.prank(creator);
        vm.expectRevert(IToolRegistry.InvalidMetadataURI.selector);
        registry.registerTool("", AccessMode.OPEN);
    }

    function test_updateToolMetadata() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);

        vm.expectEmit(true, false, false, true);
        emit IToolRegistry.ToolMetadataUpdated(toolId, META_URI, META_URI_2);
        registry.updateToolMetadata(toolId, META_URI_2);
        vm.stopPrank();

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(config.metadataURI, META_URI_2);
    }

    function test_updateToolMetadata_revertsIfNotCreator() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.NotToolCreator.selector, toolId, other));
        registry.updateToolMetadata(toolId, META_URI_2);
    }

    function test_updateToolMetadata_revertsOnEmptyURI() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);
        vm.expectRevert(IToolRegistry.InvalidMetadataURI.selector);
        registry.updateToolMetadata(toolId, "");
        vm.stopPrank();
    }

    function test_updateToolMetadata_revertsIfNotFound() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 999));
        registry.updateToolMetadata(999, META_URI_2);
    }

    function test_deactivateTool() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);

        vm.expectEmit(true, false, false, false);
        emit IToolRegistry.ToolDeactivated(toolId);
        registry.deactivateTool(toolId);
        vm.stopPrank();

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertFalse(config.active);
    }

    function test_deactivateTool_revertsIfAlreadyInactive() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);
        registry.deactivateTool(toolId);

        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolAlreadyInactive.selector, toolId));
        registry.deactivateTool(toolId);
        vm.stopPrank();
    }

    function test_deactivateTool_revertsIfNotCreator() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.NotToolCreator.selector, toolId, other));
        registry.deactivateTool(toolId);
    }

    function test_reactivateTool() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);
        registry.deactivateTool(toolId);

        vm.expectEmit(true, false, false, false);
        emit IToolRegistry.ToolReactivated(toolId);
        registry.reactivateTool(toolId);
        vm.stopPrank();

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertTrue(config.active);
    }

    function test_reactivateTool_revertsIfAlreadyActive() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);

        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolAlreadyActive.selector, toolId));
        registry.reactivateTool(toolId);
        vm.stopPrank();
    }

    function test_reactivateTool_revertsIfNotCreator() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);
        vm.prank(creator);
        registry.deactivateTool(toolId);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.NotToolCreator.selector, toolId, other));
        registry.reactivateTool(toolId);
    }

    function test_getToolConfig_revertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 42));
        registry.getToolConfig(42);
    }

    function test_hasAccess_openToolReturnsTrue() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, AccessMode.OPEN);

        assertTrue(registry.hasAccess(toolId, other));
        assertTrue(registry.hasAccess(toolId, address(0)));
    }

    function test_hasAccess_revertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 999));
        registry.hasAccess(999, other);
    }

    function test_hasAccess_revertsIfNotInitialized() public {
        ToolRegistry uninitRegistry = new ToolRegistry();
        vm.prank(creator);
        uint256 toolId = uninitRegistry.registerTool(META_URI, AccessMode.OPEN);

        vm.expectRevert(ToolRegistry.NotInitialized.selector);
        uninitRegistry.hasAccess(toolId, other);
    }

    function test_initialize_emitsEvent() public {
        ToolRegistry fresh = new ToolRegistry();
        ToolAccessRegistry freshAccess = new ToolAccessRegistry(address(fresh));

        vm.expectEmit(false, false, false, true);
        emit ToolRegistry.Initialized(address(freshAccess));
        fresh.initialize(address(freshAccess));
    }

    function test_toolCount() public {
        assertEq(registry.toolCount(), 0);

        vm.startPrank(creator);
        registry.registerTool(META_URI, AccessMode.OPEN);
        assertEq(registry.toolCount(), 1);

        registry.registerTool(META_URI, AccessMode.NFT_GATED);
        assertEq(registry.toolCount(), 2);
        vm.stopPrank();
    }

    /// @dev Locks the normative behavior that toolCount() includes deactivated
    ///      tools and tool IDs are never reused.
    function test_toolCount_includesDeactivatedTools() public {
        vm.startPrank(creator);
        uint256 id1 = registry.registerTool(META_URI, AccessMode.OPEN);
        uint256 id2 = registry.registerTool(META_URI, AccessMode.OPEN);
        uint256 id3 = registry.registerTool(META_URI, AccessMode.OPEN);
        assertEq(registry.toolCount(), 3);

        registry.deactivateTool(id2);
        assertEq(registry.toolCount(), 3);

        registry.deactivateTool(id1);
        registry.deactivateTool(id3);
        assertEq(registry.toolCount(), 3);

        // New registration gets the next sequential ID (4), never reusing 1/2/3
        uint256 id4 = registry.registerTool(META_URI, AccessMode.OPEN);
        assertEq(id4, 4);
        assertEq(registry.toolCount(), 4);
        vm.stopPrank();
    }

    function test_supportsInterface_IToolRegistry() public view {
        assertTrue(registry.supportsInterface(type(IToolRegistry).interfaceId));
    }

    /// @dev Locks the hardcoded interface ID declared in the ERC spec. If this
    ///      fails, the spec's `IToolRegistry` ID must be updated to match the
    ///      value printed in the failure message.
    function test_interfaceId_IToolRegistry_matchesSpec() public pure {
        assertEq(type(IToolRegistry).interfaceId, bytes4(0x41a32136));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_invalid() public view {
        assertFalse(registry.supportsInterface(0xdeadbeef));
    }
}
