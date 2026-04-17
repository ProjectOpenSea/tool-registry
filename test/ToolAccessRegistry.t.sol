// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";
import {ToolAccessRegistry} from "../src/ToolAccessRegistry.sol";
import {GatewayKeyRegistry} from "../src/GatewayKeyRegistry.sol";
import {IToolAccessRegistry, CollectionBinding, TokenStandard} from "../src/interfaces/IToolAccessRegistry.sol";
import {AccessMode} from "../src/interfaces/IToolRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {MockERC5643} from "./mocks/MockERC5643.sol";
import {RevertingERC721} from "./mocks/RevertingERC721.sol";
import {RevertingERC1155} from "./mocks/RevertingERC1155.sol";

contract ToolAccessRegistryTest is Test {
    ToolRegistry public registry;
    ToolAccessRegistry public accessRegistry;
    GatewayKeyRegistry public keyRegistry;
    MockERC721 public mockERC721;
    MockERC1155 public mockERC1155;
    MockERC5643 public mockERC5643;

    address creator = makeAddr("creator");
    address user = makeAddr("user");
    address other = makeAddr("other");
    string constant META_URI = "https://example.com/tool.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    function setUp() public {
        registry = new ToolRegistry();
        keyRegistry = new GatewayKeyRegistry(address(this));
        accessRegistry = new ToolAccessRegistry(address(registry), address(keyRegistry));
        registry.initialize(address(accessRegistry));

        mockERC721 = new MockERC721();
        mockERC1155 = new MockERC1155();
        mockERC5643 = new MockERC5643();
    }

    function _registerTool(AccessMode mode) internal returns (uint256) {
        vm.prank(creator);
        return registry.registerTool(META_URI, MANIFEST_HASH, mode);
    }

    // --- OPEN access ---

    function test_hasAccess_open_returnsTrue() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        assertTrue(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccess_open_returnsTrueForAnyAddress() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        assertTrue(accessRegistry.hasAccess(toolId, address(0)));
        assertTrue(accessRegistry.hasAccess(toolId, other));
    }

    // --- NFT_GATED access with ERC-721 ---

    function test_hasAccess_nftGated_erc721_noToken() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccess_nftGated_erc721_withToken() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        mockERC721.mint(user);
        assertTrue(accessRegistry.hasAccess(toolId, user));
    }

    // --- NFT_GATED access with ERC-1155 ---

    function test_hasAccess_nftGated_erc1155_noToken() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 42);

        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccess_nftGated_erc1155_withToken() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 42);

        mockERC1155.mint(user, 42, 1);
        assertTrue(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccess_nftGated_erc1155_wrongTokenId() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 42);

        mockERC1155.mint(user, 99, 1);
        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    // --- SUBSCRIPTION access ---
    // hasAccess() MUST return false for SUBSCRIPTION tools; use hasAccessWithProof.

    function test_hasAccess_subscription_alwaysReturnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        uint64 futureExpiry = uint64(block.timestamp + 365 days);
        mockERC5643.mint(user, futureExpiry);

        // Even with a valid, active subscription, basic hasAccess returns false
        // because it cannot disambiguate the caller's tokenId.
        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccessWithProof_subscription_active() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        uint64 futureExpiry = uint64(block.timestamp + 365 days);
        uint256 tokenId = mockERC5643.mint(user, futureExpiry);

        assertTrue(accessRegistry.hasAccessWithProof(toolId, user, tokenId));
    }

    function test_hasAccessWithProof_subscription_expired() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        uint64 pastExpiry = uint64(block.timestamp - 1);
        uint256 tokenId = mockERC5643.mint(user, pastExpiry);

        assertFalse(accessRegistry.hasAccessWithProof(toolId, user, tokenId));
    }

    function test_hasAccessWithProof_subscription_expiresExactlyNow() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        uint64 nowExpiry = uint64(block.timestamp);
        uint256 tokenId = mockERC5643.mint(user, nowExpiry);

        // expiresAt must be > block.timestamp, not >=
        assertFalse(accessRegistry.hasAccessWithProof(toolId, user, tokenId));
    }

    function test_hasAccessWithProof_subscription_noToken() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        // User holds no subscription token; any tokenId they pass fails the ownership check.
        assertFalse(accessRegistry.hasAccessWithProof(toolId, user, 0));
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
        assertTrue(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccess_multipleCollections_noneHeld() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        MockERC721 nft2 = new MockERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(nft2), TokenStandard.ERC721, 0);
        vm.stopPrank();

        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    // --- Revert resilience (M1) ---

    function test_hasAccess_nftGated_erc721_revertingCollectionDoesNotDoS() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        RevertingERC721 bad = new RevertingERC721();

        // Order matters: the reverting collection is bound FIRST so a
        // non-resilient loop would bail before reaching the legit binding.
        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(bad), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        vm.stopPrank();

        mockERC721.mint(user);
        assertTrue(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccess_nftGated_erc1155_revertingCollectionDoesNotDoS() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        RevertingERC1155 bad = new RevertingERC1155();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(bad), TokenStandard.ERC1155, 1);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 1);
        vm.stopPrank();

        mockERC1155.mint(user, 1, 1);
        assertTrue(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccess_nftGated_allRevertingReturnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        RevertingERC721 bad721 = new RevertingERC721();
        RevertingERC1155 bad1155 = new RevertingERC1155();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(bad721), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(bad1155), TokenStandard.ERC1155, 1);
        vm.stopPrank();

        // All bindings revert on balanceOf; hasAccess should return false,
        // not bubble up the inner revert.
        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    /// @dev Mirrors the three hasAccess resilience cases against
    ///      hasAccessWithProof. The impl routes both through `_checkAccess`,
    ///      so these pin the spec's per-function guarantee against a future
    ///      refactor that splits the paths.
    function test_hasAccessWithProof_nftGated_erc721_revertingCollectionDoesNotDoS() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        RevertingERC721 bad = new RevertingERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(bad), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        vm.stopPrank();

        mockERC721.mint(user);
        // proofTokenId is ignored for NFT_GATED; any value works.
        assertTrue(accessRegistry.hasAccessWithProof(toolId, user, 0));
    }

    function test_hasAccessWithProof_nftGated_erc1155_revertingCollectionDoesNotDoS() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        RevertingERC1155 bad = new RevertingERC1155();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(bad), TokenStandard.ERC1155, 1);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 1);
        vm.stopPrank();

        mockERC1155.mint(user, 1, 1);
        assertTrue(accessRegistry.hasAccessWithProof(toolId, user, 0));
    }

    function test_hasAccessWithProof_nftGated_allRevertingReturnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        RevertingERC721 bad721 = new RevertingERC721();
        RevertingERC1155 bad1155 = new RevertingERC1155();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(bad721), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(bad1155), TokenStandard.ERC1155, 1);
        vm.stopPrank();

        assertFalse(accessRegistry.hasAccessWithProof(toolId, user, 0));
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

    function test_addCollection_revertsOnErc1155Subscription() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IToolAccessRegistry.UnsupportedStandardForSubscription.selector, toolId, TokenStandard.ERC1155
            )
        );
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 42);
    }

    function test_addCollection_allowsErc721Subscription() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        CollectionBinding[] memory bindings = accessRegistry.getCollections(toolId);
        assertEq(bindings.length, 1);
        assertEq(uint256(bindings[0].tokenStandard), uint256(TokenStandard.ERC721));
    }

    function test_addCollection_allowsErc1155ForNftGated() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC1155), TokenStandard.ERC1155, 42);

        CollectionBinding[] memory bindings = accessRegistry.getCollections(toolId);
        assertEq(bindings.length, 1);
        assertEq(uint256(bindings[0].tokenStandard), uint256(TokenStandard.ERC1155));
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
        accessRegistry.removeCollection(toolId, 0, address(mockERC721));
        vm.stopPrank();

        CollectionBinding[] memory bindings = accessRegistry.getCollections(toolId);
        assertEq(bindings.length, 0);
    }

    function test_removeCollection_revertsOnInvalidIndex() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.CollectionNotFound.selector, toolId, 0));
        accessRegistry.removeCollection(toolId, 0, address(mockERC721));
    }

    function test_removeCollection_revertsIfNotCreator() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.NotToolCreator.selector, toolId, other));
        accessRegistry.removeCollection(toolId, 0, address(mockERC721));
    }

    function test_removeCollection_swapAndPop() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        MockERC721 nft2 = new MockERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(nft2), TokenStandard.ERC721, 0);

        accessRegistry.removeCollection(toolId, 0, address(mockERC721));
        vm.stopPrank();

        // Swap-and-pop: array shrinks, last element moves to index 0.
        CollectionBinding[] memory bindings = accessRegistry.getCollections(toolId);
        assertEq(bindings.length, 1);
        assertEq(bindings[0].collection, address(nft2));
    }

    function test_removeCollection_removedBindingNotConsultedForAccess() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        vm.stopPrank();

        mockERC721.mint(user);
        assertTrue(accessRegistry.hasAccess(toolId, user));

        vm.prank(creator);
        accessRegistry.removeCollection(toolId, 0, address(mockERC721));
        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    function test_removeCollection_revertsOnAlreadyRemoved() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        accessRegistry.removeCollection(toolId, 0, address(mockERC721));

        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.CollectionNotFound.selector, toolId, 0));
        accessRegistry.removeCollection(toolId, 0, address(mockERC721));
        vm.stopPrank();
    }

    function test_removeCollection_revertsOnMismatchedExpectedCollection() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        MockERC721 nft2 = new MockERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IToolAccessRegistry.CollectionMismatch.selector, toolId, 0, address(nft2), address(mockERC721)
            )
        );
        accessRegistry.removeCollection(toolId, 0, address(nft2));
        vm.stopPrank();
    }

    function test_removeCollection_freesSlot() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        MockERC721 nft = new MockERC721();

        vm.startPrank(creator);
        accessRegistry.addCollection(toolId, address(nft), TokenStandard.ERC721, 0);
        accessRegistry.removeCollection(toolId, 0, address(nft));

        // Should succeed: swap-and-pop fully removes, so slot is reusable.
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
        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    // --- Deactivated tool returns false (S2) ---

    function test_hasAccess_deactivatedTool_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        assertTrue(accessRegistry.hasAccess(toolId, user));

        vm.prank(creator);
        registry.deactivateTool(toolId);
        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    function test_hasAccess_deactivatedNftGated_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);
        mockERC721.mint(user);
        assertTrue(accessRegistry.hasAccess(toolId, user));

        vm.prank(creator);
        registry.deactivateTool(toolId);
        assertFalse(accessRegistry.hasAccess(toolId, user));
    }

    // --- Subscription with non-zero tokenId ---

    function test_addCollection_revertsOnErc721NonZeroTokenId() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.InvalidCollection.selector, address(mockERC721)));
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 42);
    }

    function test_addCollection_subscriptionRevertsOnErc721NonZeroTokenId() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        // Even though SUBSCRIPTION tools conceptually use token-level checks,
        // the tokenId stored in the binding is always ignored (the caller
        // supplies the tokenId via `hasAccessWithProof`). Rejecting nonzero
        // prevents dead state that would otherwise silently be ignored.
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.InvalidCollection.selector, address(mockERC5643)));
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 42);
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

        // hasAccess unconditionally returns false for SUBSCRIPTION tools
        assertFalse(accessRegistry.hasAccess(toolId, user));
        // hasAccessWithProof verifies the caller's specific tokenId
        assertTrue(accessRegistry.hasAccessWithProof(toolId, user, userTokenId));
    }

    function test_hasAccessWithProof_subscription_expiredProof() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        // Mint expired token to user
        uint256 tokenId = mockERC5643.mint(user, uint64(block.timestamp - 1));

        assertFalse(accessRegistry.hasAccessWithProof(toolId, user, tokenId));
    }

    function test_hasAccessWithProof_nftGated_ignoresProof() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC721), TokenStandard.ERC721, 0);

        mockERC721.mint(user);
        // NFT_GATED doesn't use tokenId for expiry, so proof is irrelevant
        assertTrue(accessRegistry.hasAccessWithProof(toolId, user, 999));
    }

    function test_hasAccessWithProof_open_returnsTrue() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        assertTrue(accessRegistry.hasAccessWithProof(toolId, user, 0));
    }

    function test_hasAccessWithProof_rejectsNonOwnerProof() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        accessRegistry.addCollection(toolId, address(mockERC5643), TokenStandard.ERC721, 0);

        // Attacker holds tokenId=0 (expired), victim holds tokenId=1 (active)
        mockERC5643.mint(user, uint64(block.timestamp - 1));
        uint256 victimTokenId = mockERC5643.mint(other, uint64(block.timestamp + 365 days));

        // Attacker tries to use victim's active tokenId as proof
        assertFalse(accessRegistry.hasAccessWithProof(toolId, user, victimTokenId));
    }

    function test_hasAccessWithProof_deactivated_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);
        vm.prank(creator);
        registry.deactivateTool(toolId);
        assertFalse(accessRegistry.hasAccessWithProof(toolId, user, 0));
    }

    // --- ERC-165 ---

    function test_supportsInterface_IToolAccessRegistry() public view {
        assertTrue(accessRegistry.supportsInterface(type(IToolAccessRegistry).interfaceId));
    }

    /// @dev Locks the hardcoded interface ID declared in the ERC spec.
    function test_interfaceId_IToolAccessRegistry_matchesSpec() public pure {
        assertEq(type(IToolAccessRegistry).interfaceId, bytes4(0xc11217e9));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(accessRegistry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_invalid() public view {
        assertFalse(accessRegistry.supportsInterface(0xdeadbeef));
    }
}
