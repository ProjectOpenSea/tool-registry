// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";
import {ToolAccessRegistry} from "../src/ToolAccessRegistry.sol";
import {IToolAccessRegistry, CollectionBinding, TokenStandard} from "../src/interfaces/IToolAccessRegistry.sol";
import {AccessMode} from "../src/interfaces/IToolRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {MockERC5643} from "./mocks/MockERC5643.sol";

contract ToolAccessRegistryTest is Test {
    ToolRegistry public registry;
    ToolAccessRegistry public accessRegistry;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    MockERC5643 public mockERC5643;

    address creator = makeAddr("creator");
    address user = makeAddr("user");
    address other = makeAddr("other");
    string constant META_URI = "https://example.com/tool.json";

    function setUp() public {
        registry = new ToolRegistry();
        accessRegistry = new ToolAccessRegistry(address(registry));
        registry.initialize(address(accessRegistry));

        mockERC721 = new MockERC721();
        mockERC1155 = new MockERC1155();
        mockERC5643 = new MockERC5643();
    }

    function _registerTool(AccessMode mode) internal returns (uint256) {
        vm.prank(creator);
        return registry.registerTool(META_URI, mode);
    }

    // --- OPEN access ---

    function test_hasAccess_open_returnsTrue() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        assertTrue(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_open_returnsTrueForAnyAddress() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        assertTrue(accessRegistry.hasAccess(address(0), toolId));
        assertTrue(accessRegistry.hasAccess(other, toolId));
    }

    // --- NFT_GATED access with ERC-721 ---

    function test_hasAccess_nftGated_erc721_noToken() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_nftGated_erc721_withToken() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        mockERC721.mint(user);
        assertTrue(accessRegistry.hasAccess(user, toolId));
    }

    // --- NFT_GATED access with ERC-1155 ---

    function test_hasAccess_nftGated_erc1155_noToken() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 42);

        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_nftGated_erc1155_withToken() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 42);

        mockERC1155.mint(user, 42, 1);
        assertTrue(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_nftGated_erc1155_wrongTokenId() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 42);

        mockERC1155.mint(user, 99, 1);
        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    // --- SUBSCRIPTION access ---

    function test_hasAccess_subscription_active() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        uint64 futureExpiry = uint64(block.timestamp + 365 days);
        mockERC5643.mint(user, futureExpiry);

        assertTrue(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_subscription_expired() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        uint64 pastExpiry = uint64(block.timestamp - 1);
        mockERC5643.mint(user, pastExpiry);

        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_subscription_expiresExactlyNow() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        uint64 nowExpiry = uint64(block.timestamp);
        mockERC5643.mint(user, nowExpiry);

        // expiresAt must be > block.timestamp, not >=
        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_subscription_noToken() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    // --- Multiple collections (OR logic) ---

    function test_hasAccess_multipleCollections_orLogic() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        MockERC721 nft2 = new MockERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(nft2), TokenStandard.ERC721, 0);
        vm.stopPrank();

        // User holds token from second collection only
        nft2.mint(user);
        assertTrue(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_multipleCollections_noneHeld() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        MockERC721 nft2 = new MockERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(nft2), TokenStandard.ERC721, 0);
        vm.stopPrank();

        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    // --- addCollection ---

    function test_addCollection_emitsEvent() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit IToolAccessRegistry.CollectionAdded(toolId, address(mockERC721), TokenStandard.ERC721);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
    }

    function test_addCollection_revertsIfNotCreator() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.NotToolCreator.selector, toolId, other));
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
    }

    function test_addCollection_revertsOnZeroAddress() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.InvalidCollection.selector, address(0)));
        accessRegistry.addCollection(toolId, address(0), TokenStandard.ERC721, 0);
    }

    function test_addCollection_revertsAtMaxCollections() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.startPrank(creator);
        for (uint256 i = 0; i < 20; i++) {
            MockERC721 nft = new MockERC721();
            accessRegistry.addCollection(toolId, address(nft), TokenStandard.ERC721, 0);
        }

        MockERC721 extraNft = new MockERC721();
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.MaxCollectionsReached.selector, toolId));
        accessRegistry.addCollection(toolId, address(extraNft), TokenStandard.ERC721, 0);
        vm.stopPrank();
    }

    function test_maxCollectionsValue() public view {
        assertEq(accessRegistry.MAX_COLLECTIONS(), 20);
    }

    // --- removeCollection ---

    function test_removeCollection() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        vm.expectEmit(true, true, false, false);
        emit IToolAccessRegistry.CollectionRemoved(toolId, address(mockERC721));
        accessRegistry.removeCollection(toolId, 0);
        vm.stopPrank();

        CollectionBinding[] memory bindings = accessRegistry.getCollections(toolId);
        assertEq(bindings.length, 1);
        assertFalse(bindings[0].active);
    }

    function test_removeCollection_revertsOnInvalidIndex() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.CollectionNotFound.selector, toolId, 0));
        accessRegistry.removeCollection(toolId, 0);
    }

    function test_removeCollection_revertsIfNotCreator() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.NotToolCreator.selector, toolId, other));
        accessRegistry.removeCollection(toolId, 0);
    }

    function test_removeCollection_softDelete() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        MockERC721 nft2 = new MockERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(nft2), TokenStandard.ERC721, 0);

        accessRegistry.removeCollection(toolId, 0);
        vm.stopPrank();

        CollectionBinding[] memory bindings = accessRegistry.getCollections(toolId);
        assertEq(bindings.length, 2);
        assertFalse(bindings[0].active);
        assertTrue(bindings[1].active);
    }

    function test_removeCollection_softDeletedBindingSkippedInAccess() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        vm.stopPrank();

        mockERC721.mint(user);
        assertTrue(accessRegistry.hasAccess(user, toolId));

        vm.prank(creator);
        accessRegistry.removeCollection(toolId, 0);
        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    function test_removeCollection_revertsOnAlreadyRemoved() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        accessRegistry.removeCollection(toolId, 0);

        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.CollectionNotFound.selector, toolId, 0));
        accessRegistry.removeCollection(toolId, 0);
        vm.stopPrank();
    }

    function test_removeCollection_softDeleteDoesNotExhaustSlotLimit() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        MockERC721 nft = new MockERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(nft), TokenStandard.ERC721, 0);
        accessRegistry.removeCollection(toolId, 0);

        // Should succeed — soft-deleted slot doesn't count toward limit
        accessRegistry.addCollection(toolId, address(nft), TokenStandard.ERC721, 0);
        vm.stopPrank();
    }

    // --- getCollections ---

    function test_getCollections_empty() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        CollectionBinding[] memory bindings = accessRegistry.getCollections(toolId);
        assertEq(bindings.length, 0);
    }

    // --- NFT_GATED with no bindings returns false ---

    function test_hasAccess_nftGated_noBindings() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    // --- Deactivated tool returns false (S2) ---

    function test_hasAccess_deactivatedTool_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        assertTrue(accessRegistry.hasAccess(user, toolId));

        vm.prank(creator);
        registry.deactivateTool(toolId);
        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    function test_hasAccess_deactivatedNftGated_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        mockERC721.mint(user);
        assertTrue(accessRegistry.hasAccess(user, toolId));

        vm.prank(creator);
        registry.deactivateTool(toolId);
        assertFalse(accessRegistry.hasAccess(user, toolId));
    }

    // --- Subscription with non-zero tokenId ---

    function test_hasAccess_subscription_nonZeroTokenId() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        // Mint tokenId 0 first (to someone else), then tokenId 1 to user
        mockERC5643.mint(other, uint64(block.timestamp - 1));
        uint256 userTokenId = mockERC5643.mint(user, uint64(block.timestamp + 365 days));

        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, userTokenId);

        assertTrue(accessRegistry.hasAccess(user, toolId));
    }

    // --- hasAccessWithProof (F5 fix) ---

    function test_hasAccessWithProof_subscription_userTokenId() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        // Bind with tokenId=0 (default), but user holds tokenId=1
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        // Mint tokenId=0 to someone else (expired)
        mockERC5643.mint(other, uint64(block.timestamp - 1));
        // Mint tokenId=1 to user (active)
        uint256 userTokenId = mockERC5643.mint(user, uint64(block.timestamp + 365 days));

        // Without proof: checks binding.tokenId=0 which is expired
        assertFalse(accessRegistry.hasAccess(user, toolId));
        // With proof: checks user's actual tokenId=1 which is active
        assertTrue(accessRegistry.hasAccessWithProof(user, toolId, userTokenId));
    }

    function test_hasAccessWithProof_subscription_expiredProof() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        // Mint expired token to user
        uint256 tokenId = mockERC5643.mint(user, uint64(block.timestamp - 1));

        assertFalse(accessRegistry.hasAccessWithProof(user, toolId, tokenId));
    }

    function test_hasAccessWithProof_nftGated_ignoresProof() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        mockERC721.mint(user);
        // NFT_GATED doesn't use tokenId for expiry, so proof is irrelevant
        assertTrue(accessRegistry.hasAccessWithProof(user, toolId, 999));
    }

    function test_hasAccessWithProof_open_returnsTrue() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        assertTrue(accessRegistry.hasAccessWithProof(user, toolId, 0));
    }

    function test_hasAccessWithProof_rejectsNonOwnerProof() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        // Attacker holds tokenId=0 (expired), victim holds tokenId=1 (active)
        mockERC5643.mint(user, uint64(block.timestamp - 1));
        uint256 victimTokenId = mockERC5643.mint(other, uint64(block.timestamp + 365 days));

        // Attacker tries to use victim's active tokenId as proof
        assertFalse(accessRegistry.hasAccessWithProof(user, toolId, victimTokenId));
    }

    function test_hasAccessWithProof_erc1155_checksSameTokenId() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 10);

        // User holds tokenId=10 but not tokenId=99
        mockERC1155.mint(user, 10, 1);

        // Proof with tokenId user doesn't own should fail
        assertFalse(accessRegistry.hasAccessWithProof(user, toolId, 99));
    }

    function test_hasAccessWithProof_deactivated_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        vm.prank(creator);
        registry.deactivateTool(toolId);
        assertFalse(accessRegistry.hasAccessWithProof(user, toolId, 0));
    }

    // --- ERC-165 ---

    function test_supportsInterface_IToolAccessRegistry() public view {
        assertTrue(accessRegistry.supportsInterface(type(IToolAccessRegistry).interfaceId));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(accessRegistry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_invalid() public view {
        assertFalse(accessRegistry.supportsInterface(0xdeadbeef));
    }
}
