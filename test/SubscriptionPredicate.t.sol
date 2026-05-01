// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SubscriptionPredicate} from "../examples/SubscriptionPredicate.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {ISubscription} from "../src/interfaces/IRequirementTypes.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";

/// @dev Contract that does NOT implement ISubscriptionNFT.
contract NotASubscriptionNFT {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

/// @dev Minimal mock subscription NFT with configurable expiration, tier, and owner lookup.
contract MockSubscriptionNFT {
    mapping(address => uint256) private _tokens;
    mapping(uint256 => uint64) private _expirations;
    mapping(uint256 => uint8) private _tiers;

    function setSubscription(address owner, uint256 tokenId, uint64 expiration, uint8 tier) external {
        _tokens[owner] = tokenId;
        _expirations[tokenId] = expiration;
        _tiers[tokenId] = tier;
    }

    function clearSubscription(address owner, uint256 tokenId) external {
        delete _tokens[owner];
        delete _expirations[tokenId];
        delete _tiers[tokenId];
    }

    function tokenOfOwner(address owner) external view returns (uint256) {
        return _tokens[owner];
    }

    function expiresAt(uint256 tokenId) external view returns (uint64) {
        return _expirations[tokenId];
    }

    function tierOf(uint256 tokenId) external view returns (uint8) {
        return _tiers[tokenId];
    }
}

contract SubscriptionPredicateTest is Test {
    ToolRegistry public registry;
    SubscriptionPredicate public predicate;
    MockSubscriptionNFT public nft;

    address creator = makeAddr("creator");
    address subscriber = makeAddr("subscriber");
    address nonSubscriber = makeAddr("nonSubscriber");
    string constant META_URI = "https://example.com/tool.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    uint256 toolId;

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new SubscriptionPredicate(address(registry));
        nft = new MockSubscriptionNFT();

        // Register a tool with this predicate
        vm.prank(creator);
        toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
    }

    // --- constructor ---

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert("SubscriptionPredicate: zero registry");
        new SubscriptionPredicate(address(0));
    }

    function test_constructor_setsRegistry() public view {
        assertEq(address(predicate.registry()), address(registry));
    }

    // --- configureToolGating ---

    function test_configureToolGating_success() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 1);

        SubscriptionPredicate.ToolGatingConfig memory config = predicate.getToolGatingConfig(toolId);
        assertEq(config.collection, address(nft));
        assertEq(config.minTier, 1);
    }

    function test_configureToolGating_emitsEvent() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit SubscriptionPredicate.ToolGatingConfigured(toolId, address(nft), 2);
        predicate.configureToolGating(toolId, address(nft), 2);
    }

    function test_configureToolGating_revertsIfNotCreator() public {
        vm.prank(nonSubscriber);
        vm.expectRevert(abi.encodeWithSelector(SubscriptionPredicate.NotToolCreator.selector, toolId, nonSubscriber));
        predicate.configureToolGating(toolId, address(nft), 1);
    }

    function test_configureToolGating_revertsIfToolDoesNotUseThisPredicate() public {
        // Register a tool with no predicate (open access)
        vm.prank(creator);
        uint256 openToolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(SubscriptionPredicate.ToolDoesNotUseThisPredicate.selector, openToolId));
        predicate.configureToolGating(openToolId, address(nft), 1);
    }

    function test_configureToolGating_revertsOnZeroCollection() public {
        vm.prank(creator);
        vm.expectRevert(SubscriptionPredicate.ZeroCollection.selector);
        predicate.configureToolGating(toolId, address(0), 1);
    }

    function test_configureToolGating_revertsOnEOACollection() public {
        address eoa = makeAddr("eoa");
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(SubscriptionPredicate.CollectionNotAContract.selector, eoa));
        predicate.configureToolGating(toolId, eoa, 1);
    }

    function test_configureToolGating_revertsOnNonSubscriptionNFTContract() public {
        NotASubscriptionNFT bogus = new NotASubscriptionNFT();
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionPredicate.CollectionNotSubscriptionNFT.selector, address(bogus))
        );
        predicate.configureToolGating(toolId, address(bogus), 1);
    }

    function test_configureToolGating_revertsAfterPredicateSwap() public {
        vm.startPrank(creator);
        predicate.configureToolGating(toolId, address(nft), 1);

        // Swap tool away from this predicate
        registry.setAccessPredicate(toolId, address(0));

        // Now configuring should revert
        vm.expectRevert(abi.encodeWithSelector(SubscriptionPredicate.ToolDoesNotUseThisPredicate.selector, toolId));
        predicate.configureToolGating(toolId, address(nft), 2);
        vm.stopPrank();
    }

    function test_configureToolGating_canUpdate() public {
        MockSubscriptionNFT nft2 = new MockSubscriptionNFT();

        vm.startPrank(creator);
        predicate.configureToolGating(toolId, address(nft), 1);
        predicate.configureToolGating(toolId, address(nft2), 3);
        vm.stopPrank();

        SubscriptionPredicate.ToolGatingConfig memory config = predicate.getToolGatingConfig(toolId);
        assertEq(config.collection, address(nft2));
        assertEq(config.minTier, 3);
    }

    // --- hasAccess ---

    function test_hasAccess_trueWhenActiveSubscription() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 0);

        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 1);

        assertTrue(predicate.hasAccess(toolId, subscriber, ""));
    }

    function test_hasAccess_falseWhenNoNFT() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 0);

        assertFalse(predicate.hasAccess(toolId, nonSubscriber, ""));
    }

    function test_hasAccess_falseWhenExpired() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 0);

        // Set expiration in the past
        nft.setSubscription(subscriber, 1, uint64(block.timestamp - 1), 1);

        assertFalse(predicate.hasAccess(toolId, subscriber, ""));
    }

    function test_hasAccess_falseWhenExpirationEqualsNow() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 0);

        nft.setSubscription(subscriber, 1, uint64(block.timestamp), 1);

        assertFalse(predicate.hasAccess(toolId, subscriber, ""));
    }

    function test_hasAccess_falseWhenTierTooLow() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 2);

        // Tier 1 but needs tier 2
        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 1);

        assertFalse(predicate.hasAccess(toolId, subscriber, ""));
    }

    function test_hasAccess_trueWhenTierMeetsMinimum() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 2);

        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 2);

        assertTrue(predicate.hasAccess(toolId, subscriber, ""));
    }

    function test_hasAccess_trueWhenTierExceedsMinimum() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 2);

        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 3);

        assertTrue(predicate.hasAccess(toolId, subscriber, ""));
    }

    function test_hasAccess_falseWhenToolNotConfigured() public view {
        // toolId is registered in ToolRegistry but not configured in predicate
        assertFalse(predicate.hasAccess(toolId, subscriber, ""));
    }

    function test_hasAccess_minTierZeroIgnoresTier() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 0);

        // Tier 1 with minTier 0 — should pass
        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 1);
        assertTrue(predicate.hasAccess(toolId, subscriber, ""));
    }

    // --- Multi-tool with same collection, different tiers ---

    function test_multiTool_samecollection_differentTiers() public {
        vm.startPrank(creator);
        uint256 basicToolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        uint256 proToolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        predicate.configureToolGating(basicToolId, address(nft), 1);
        predicate.configureToolGating(proToolId, address(nft), 2);
        vm.stopPrank();

        // Subscriber has tier 1
        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 1);

        assertTrue(predicate.hasAccess(basicToolId, subscriber, ""));
        assertFalse(predicate.hasAccess(proToolId, subscriber, ""));
    }

    // --- Multi-tool with different collections ---

    function test_multiTool_differentCollections() public {
        MockSubscriptionNFT nft2 = new MockSubscriptionNFT();

        vm.startPrank(creator);
        uint256 tool1 = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        uint256 tool2 = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        predicate.configureToolGating(tool1, address(nft), 0);
        predicate.configureToolGating(tool2, address(nft2), 0);
        vm.stopPrank();

        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 1);
        // subscriber does NOT have nft2

        assertTrue(predicate.hasAccess(tool1, subscriber, ""));
        assertFalse(predicate.hasAccess(tool2, subscriber, ""));
    }

    // --- getSubscriptionStatus ---

    function test_getSubscriptionStatus_activeSubscription() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 2);

        uint64 exp = uint64(block.timestamp + 30 days);
        nft.setSubscription(subscriber, 1, exp, 3);

        (bool hasNft, uint8 tier, uint8 requiredTier, uint64 expiration, bool active) =
            predicate.getSubscriptionStatus(toolId, subscriber);

        assertTrue(hasNft);
        assertEq(tier, 3);
        assertEq(requiredTier, 2);
        assertEq(expiration, exp);
        assertTrue(active);
    }

    function test_getSubscriptionStatus_insufficientTier() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 3);

        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 1);

        (bool hasNft, uint8 tier, uint8 requiredTier, uint64 expiration, bool active) =
            predicate.getSubscriptionStatus(toolId, subscriber);

        assertTrue(hasNft);
        assertEq(tier, 1);
        assertEq(requiredTier, 3);
        assertTrue(expiration > block.timestamp);
        assertFalse(active);
    }

    function test_getSubscriptionStatus_noNFT() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 0);

        (bool hasNft, uint8 tier, uint8 requiredTier, uint64 expiration, bool active) =
            predicate.getSubscriptionStatus(toolId, nonSubscriber);

        assertFalse(hasNft);
        assertEq(tier, 0);
        assertEq(requiredTier, 0);
        assertEq(expiration, 0);
        assertFalse(active);
    }

    function test_getSubscriptionStatus_expired() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 0);

        nft.setSubscription(subscriber, 1, uint64(block.timestamp - 1), 2);

        (bool hasNft, uint8 tier,, uint64 expiration, bool active) = predicate.getSubscriptionStatus(toolId, subscriber);

        assertTrue(hasNft);
        assertEq(tier, 2);
        assertTrue(expiration < block.timestamp);
        assertFalse(active);
    }

    function test_getSubscriptionStatus_unconfiguredTool() public view {
        (bool hasNft, uint8 tier, uint8 requiredTier, uint64 expiration, bool active) =
            predicate.getSubscriptionStatus(toolId, subscriber);

        assertFalse(hasNft);
        assertEq(tier, 0);
        assertEq(requiredTier, 0);
        assertEq(expiration, 0);
        assertFalse(active);
    }

    // --- ERC-165 ---

    function test_supportsInterface_IAccessPredicate() public view {
        assertTrue(predicate.supportsInterface(type(IAccessPredicate).interfaceId));
    }

    function test_supportsInterface_IERC165() public view {
        assertTrue(predicate.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_falseForRandom() public view {
        assertFalse(predicate.supportsInterface(0xdeadbeef));
    }

    function test_name() public view {
        assertEq(predicate.name(), "SubscriptionPredicate");
    }

    function test_version() public view {
        assertEq(predicate.version(), "0.2");
    }

    // ── getRequirements ──────────────────────────────────────────────────

    function test_getRequirements_emptyWhenUnconfigured() public view {
        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 0);
        assertEq(uint256(logic), uint256(RequirementLogic.AND));
    }

    function test_getRequirements_returnsConfiguredRequirement() public {
        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 2);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 1);
        assertEq(reqs[0].kind, type(ISubscription).interfaceId);
        (address collection, uint8 minTier) = abi.decode(reqs[0].data, (address, uint8));
        assertEq(collection, address(nft));
        assertEq(minTier, 2);
        assertEq(uint256(logic), uint256(RequirementLogic.AND));
    }
}

contract SubscriptionPredicateIntegrationTest is Test {
    ToolRegistry public registry;
    SubscriptionPredicate public predicate;
    MockSubscriptionNFT public nft;

    address creator = makeAddr("creator");
    address subscriber = makeAddr("subscriber");
    string constant META_URI = "https://example.com/tool.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new SubscriptionPredicate(address(registry));
        nft = new MockSubscriptionNFT();
    }

    /// @dev End-to-end: register tool → configure gating → verify access via registry
    function test_registry_delegatesToSubscriptionPredicate() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        vm.prank(creator);
        predicate.configureToolGating(toolId, address(nft), 1);

        // No subscription yet
        assertFalse(registry.hasAccess(toolId, subscriber, ""));

        // Grant subscription
        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 1);
        assertTrue(registry.hasAccess(toolId, subscriber, ""));

        // Subscription expires
        vm.warp(block.timestamp + 31 days);
        assertFalse(registry.hasAccess(toolId, subscriber, ""));
    }

    /// @dev End-to-end: tiered access via registry
    function test_registry_tieredAccess() public {
        vm.startPrank(creator);
        uint256 basicId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        uint256 proId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        uint256 enterpriseId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        predicate.configureToolGating(basicId, address(nft), 1);
        predicate.configureToolGating(proId, address(nft), 2);
        predicate.configureToolGating(enterpriseId, address(nft), 3);
        vm.stopPrank();

        // Tier 2 subscriber
        nft.setSubscription(subscriber, 1, uint64(block.timestamp + 30 days), 2);

        assertTrue(registry.hasAccess(basicId, subscriber, ""));
        assertTrue(registry.hasAccess(proId, subscriber, ""));
        assertFalse(registry.hasAccess(enterpriseId, subscriber, ""));

        // tryHasAccess also works correctly
        (bool ok, bool granted) = registry.tryHasAccess(enterpriseId, subscriber, "");
        assertTrue(ok);
        assertFalse(granted);
    }
}
