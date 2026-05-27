// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {TraitGatedPredicate} from "../examples/TraitGatedPredicate.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {IERC7496Trait} from "../src/interfaces/IRequirementTypes.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";

/// @dev Minimal mock ERC-721 with configurable ownerOf.
contract MockERC721 {
    mapping(uint256 => address) private _owners;

    function setOwner(uint256 tokenId, address owner) external {
        _owners[tokenId] = owner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }
}

/// @dev Mock ERC-7496 traits contract. Returns bytes32(0) for unset traits
///      (matching DynamicTraits behavior); predicate rejects bytes32(0) in allowedValues.
contract MockTraits {
    mapping(uint256 => mapping(bytes32 => bytes32)) private _traits;

    function setTrait(uint256 tokenId, bytes32 traitKey, bytes32 value) external {
        _traits[tokenId][traitKey] = value;
    }

    function getTraitValue(uint256 tokenId, bytes32 traitKey) external view returns (bytes32) {
        return _traits[tokenId][traitKey];
    }
}

/// @dev Contract that does not implement getTraitValue.
contract NotATraitsContract {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract TraitGatedPredicateTest is Test {
    ToolRegistry public registry;
    TraitGatedPredicate public predicate;
    MockERC721 public nft;
    MockTraits public traits;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");
    address nonHolder = makeAddr("nonHolder");
    address stranger = makeAddr("stranger");

    string constant META_URI = "https://api.opensea.io/.well-known/ai-tool/trait-tool.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    bytes32 constant TIER_KEY = bytes32("tier");
    bytes32 constant TIER_RARE = bytes32("Rare");
    bytes32 constant TIER_STANDARD = bytes32("Standard");
    bytes32 constant TIER_LEGENDARY = bytes32("Legendary");

    uint256 toolId;
    uint256 constant TOKEN_ID = 42;

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new TraitGatedPredicate(address(registry));
        nft = new MockERC721();
        traits = new MockTraits();

        nft.setOwner(TOKEN_ID, holder);
        traits.setTrait(TOKEN_ID, TIER_KEY, TIER_RARE);

        vm.prank(creator);
        toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
    }

    // ── constructor ─────────────────────────────────────────────────────

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert("TraitGatedPredicate: zero registry");
        new TraitGatedPredicate(address(0));
    }

    function test_constructor_setsRegistry() public view {
        assertEq(address(predicate.REGISTRY()), address(registry));
    }

    // ── configureToolTrait ──────────────────────────────────────────────

    function test_configureToolTrait_success() public {
        bytes32[] memory allowed = new bytes32[](2);
        allowed[0] = TIER_RARE;
        allowed[1] = TIER_LEGENDARY;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        TraitGatedPredicate.ToolTraitConfig memory config = predicate.getToolTraitConfig(toolId);
        assertEq(config.collection, address(nft));
        assertEq(config.traitsContract, address(traits));
        assertEq(config.traitKey, TIER_KEY);
        assertEq(config.allowedValues.length, 2);
        assertEq(config.allowedValues[0], TIER_RARE);
        assertEq(config.allowedValues[1], TIER_LEGENDARY);
    }

    function test_configureToolTrait_sameCollectionAndTraitsContract() public {
        // When the NFT itself implements ERC-7496
        MockTraitsNFT combined = new MockTraitsNFT();
        combined.setOwner(TOKEN_ID, holder);
        combined.setTrait(TOKEN_ID, TIER_KEY, TIER_RARE);

        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(combined), address(combined), TIER_KEY, allowed);

        TraitGatedPredicate.ToolTraitConfig memory config = predicate.getToolTraitConfig(toolId);
        assertEq(config.collection, address(combined));
        assertEq(config.traitsContract, address(combined));
    }

    function test_configureToolTrait_emitsEvent() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.expectEmit(true, true, false, true);
        emit TraitGatedPredicate.ToolTraitConfigured(toolId, address(nft), address(traits), TIER_KEY, allowed);

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);
    }

    function test_configureToolTrait_replacesExisting() public {
        bytes32[] memory allowed1 = new bytes32[](1);
        allowed1[0] = TIER_RARE;

        bytes32[] memory allowed2 = new bytes32[](1);
        allowed2[0] = TIER_LEGENDARY;

        vm.startPrank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed1);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed2);
        vm.stopPrank();

        TraitGatedPredicate.ToolTraitConfig memory config = predicate.getToolTraitConfig(toolId);
        assertEq(config.allowedValues.length, 1);
        assertEq(config.allowedValues[0], TIER_LEGENDARY);
    }

    function test_configureToolTrait_revertsIfNotCreator() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.expectRevert(abi.encodeWithSelector(TraitGatedPredicate.CallerIsNotToolCreator.selector, toolId, stranger));
        vm.prank(stranger);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);
    }

    function test_configureToolTrait_revertsOnZeroCollection() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.expectRevert(TraitGatedPredicate.ZeroCollection.selector);
        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(0), address(traits), TIER_KEY, allowed);
    }

    function test_configureToolTrait_revertsOnEOACollection() public {
        address eoa = makeAddr("eoa");
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.expectRevert(abi.encodeWithSelector(TraitGatedPredicate.CollectionNoCode.selector, eoa));
        vm.prank(creator);
        predicate.configureToolTrait(toolId, eoa, address(traits), TIER_KEY, allowed);
    }

    function test_configureToolTrait_revertsOnZeroTraitsContract() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.expectRevert(TraitGatedPredicate.ZeroTraitsContract.selector);
        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(0), TIER_KEY, allowed);
    }

    function test_configureToolTrait_revertsOnEOATraitsContract() public {
        address eoa = makeAddr("eoa");
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.expectRevert(abi.encodeWithSelector(TraitGatedPredicate.TraitsContractNoCode.selector, eoa));
        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), eoa, TIER_KEY, allowed);
    }

    function test_configureToolTrait_revertsOnEmptyAllowedValues() public {
        bytes32[] memory allowed = new bytes32[](0);

        vm.expectRevert(TraitGatedPredicate.EmptyAllowedValues.selector);
        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);
    }

    function test_configureToolTrait_revertsOnTooManyAllowedValues() public {
        uint256 max = predicate.MAX_ALLOWED_VALUES();
        bytes32[] memory allowed = new bytes32[](max + 1);
        for (uint256 i; i < allowed.length; ++i) {
            allowed[i] = bytes32(i + 1);
        }

        vm.expectRevert(abi.encodeWithSelector(TraitGatedPredicate.TooManyAllowedValues.selector, max + 1, max));
        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);
    }

    function test_configureToolTrait_revertsOnZeroValueInAllowedValues() public {
        bytes32[] memory allowed = new bytes32[](2);
        allowed[0] = TIER_RARE;
        allowed[1] = bytes32(0);

        vm.expectRevert(abi.encodeWithSelector(TraitGatedPredicate.ZeroValueInAllowedValues.selector, 1));
        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);
    }

    // ── hasAccess ────────────────────────────────────────────────────────

    function test_hasAccess_grantsWhenTraitMatches() public {
        bytes32[] memory allowed = new bytes32[](2);
        allowed[0] = TIER_RARE;
        allowed[1] = TIER_LEGENDARY;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        bytes memory data = abi.encode(TOKEN_ID);
        assertTrue(predicate.hasAccess(toolId, holder, data));
    }

    function test_hasAccess_deniesWhenTraitDoesNotMatch() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_LEGENDARY;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        bytes memory data = abi.encode(TOKEN_ID);
        assertFalse(predicate.hasAccess(toolId, holder, data));
    }

    function test_hasAccess_deniesNonOwner() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        bytes memory data = abi.encode(TOKEN_ID);
        assertFalse(predicate.hasAccess(toolId, nonHolder, data));
    }

    function test_hasAccess_deniesWhenNoConfig() public view {
        bytes memory data = abi.encode(TOKEN_ID);
        assertFalse(predicate.hasAccess(toolId, holder, data));
    }

    function test_hasAccess_returnsFalseOnEmptyData() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_returnsFalseOnMalformedData() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        assertFalse(predicate.hasAccess(toolId, holder, hex"deadbeef"));
    }

    function test_hasAccess_deniesWhenTokenDoesNotExist() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        bytes memory data = abi.encode(uint256(999));
        assertFalse(predicate.hasAccess(toolId, holder, data));
    }

    function test_hasAccess_worksWithSeparateTraitsContract() public {
        MockTraits separateTraits = new MockTraits();
        separateTraits.setTrait(TOKEN_ID, TIER_KEY, TIER_LEGENDARY);

        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_LEGENDARY;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(separateTraits), TIER_KEY, allowed);

        bytes memory data = abi.encode(TOKEN_ID);
        assertTrue(predicate.hasAccess(toolId, holder, data));
    }

    function test_hasAccess_deniesWhenTraitsContractReverts() public {
        NotATraitsContract bogus = new NotATraitsContract();
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(bogus), TIER_KEY, allowed);

        bytes memory data = abi.encode(TOKEN_ID);
        assertFalse(predicate.hasAccess(toolId, holder, data));
    }

    function test_hasAccess_worksWithCombinedNFTAndTraits() public {
        MockTraitsNFT combined = new MockTraitsNFT();
        combined.setOwner(TOKEN_ID, holder);
        combined.setTrait(TOKEN_ID, TIER_KEY, TIER_RARE);

        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(combined), address(combined), TIER_KEY, allowed);

        bytes memory data = abi.encode(TOKEN_ID);
        assertTrue(predicate.hasAccess(toolId, holder, data));
    }

    function test_hasAccess_multipleAllowedValues_matchesLast() public {
        bytes32[] memory allowed = new bytes32[](3);
        allowed[0] = TIER_STANDARD;
        allowed[1] = TIER_LEGENDARY;
        allowed[2] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        bytes memory data = abi.encode(TOKEN_ID);
        assertTrue(predicate.hasAccess(toolId, holder, data));
    }

    // ── getRequirements ─────────────────────────────────────────────────

    function test_getRequirements_emptyWhenNotConfigured() public view {
        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 0);
        assertEq(uint8(logic), uint8(RequirementLogic.AND));
    }

    function test_getRequirements_returnsConfiguredRequirement() public {
        bytes32[] memory allowed = new bytes32[](2);
        allowed[0] = TIER_RARE;
        allowed[1] = TIER_LEGENDARY;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(traits), TIER_KEY, allowed);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 1);
        assertEq(reqs[0].kind, type(IERC7496Trait).interfaceId);
        assertEq(uint8(logic), uint8(RequirementLogic.AND));

        (address decodedCollection, address decodedTraits, bytes32 decodedKey, bytes32[] memory decodedValues) =
            abi.decode(reqs[0].data, (address, address, bytes32, bytes32[]));
        assertEq(decodedCollection, address(nft));
        assertEq(decodedTraits, address(traits));
        assertEq(decodedKey, TIER_KEY);
        assertEq(decodedValues.length, 2);
        assertEq(decodedValues[0], TIER_RARE);
        assertEq(decodedValues[1], TIER_LEGENDARY);
    }

    // ── interface ID pin ─────────────────────────────────────────────────

    function test_interfaceId_IERC7496Trait_pinned() public pure {
        assertEq(type(IERC7496Trait).interfaceId, bytes4(0x37d8dc22));
    }

    // ── ERC-165 ─────────────────────────────────────────────────────────

    function test_supportsInterface_IAccessPredicate() public view {
        assertTrue(predicate.supportsInterface(type(IAccessPredicate).interfaceId));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(predicate.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_random_returns_false() public view {
        assertFalse(predicate.supportsInterface(0xdeadbeef));
    }

    // ── name / version ──────────────────────────────────────────────────

    function test_name() public view {
        assertEq(predicate.name(), "TraitGatedPredicate");
    }

    function test_version() public view {
        assertEq(predicate.version(), "0.1");
    }
}

/// @dev Combined mock that implements both ERC-721 ownerOf and ERC-7496 getTraitValue.
contract MockTraitsNFT {
    mapping(uint256 => address) private _owners;
    mapping(uint256 => mapping(bytes32 => bytes32)) private _traits;

    function setOwner(uint256 tokenId, address owner) external {
        _owners[tokenId] = owner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    function setTrait(uint256 tokenId, bytes32 traitKey, bytes32 value) external {
        _traits[tokenId][traitKey] = value;
    }

    function getTraitValue(uint256 tokenId, bytes32 traitKey) external view returns (bytes32) {
        return _traits[tokenId][traitKey];
    }
}

// ── Tests against shipyard-core DynamicTraits reference impl ────────

import {DynamicTraits} from "shipyard-core/dynamic-traits/DynamicTraits.sol";

/// @dev ERC-721 + real DynamicTraits. Exposes internal helpers for test setup.
contract RealTraitsNFT is DynamicTraits {
    mapping(uint256 => address) private _owners;

    function mint(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    function registerTraitKey(bytes32 traitKey) external {
        _registerTraitKey(traitKey);
    }
}

contract TraitGatedPredicateRealDynamicTraitsTest is Test {
    ToolRegistry public registry;
    TraitGatedPredicate public predicate;
    RealTraitsNFT public nft;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");

    bytes32 constant TIER_KEY = bytes32("tier");
    bytes32 constant TIER_RARE = bytes32("Rare");
    bytes32 constant TIER_LEGENDARY = bytes32("Legendary");
    bytes32 constant UNREGISTERED_KEY = bytes32("nonexistent");

    uint256 toolId;
    uint256 constant TOKEN_ID = 42;
    uint256 constant TOKEN_ID_UNSET = 99;

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new TraitGatedPredicate(address(registry));
        nft = new RealTraitsNFT();

        // Register the "tier" trait key and set a value for TOKEN_ID.
        nft.registerTraitKey(TIER_KEY);
        nft.mint(holder, TOKEN_ID);
        nft.mint(holder, TOKEN_ID_UNSET);
        nft.setTrait(TOKEN_ID, TIER_KEY, TIER_RARE);
        // TOKEN_ID_UNSET has the key registered but no value set → bytes32(0).

        vm.prank(creator);
        toolId = registry.registerTool(
            "https://api.opensea.io/.well-known/ai-tool/real-trait-tool.json",
            keccak256("manifest-v2"),
            address(predicate)
        );
    }

    function test_realDynamicTraits_grantsOnMatchingTrait() public {
        bytes32[] memory allowed = new bytes32[](2);
        allowed[0] = TIER_RARE;
        allowed[1] = TIER_LEGENDARY;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(nft), TIER_KEY, allowed);

        assertTrue(predicate.hasAccess(toolId, holder, abi.encode(TOKEN_ID)));
    }

    function test_realDynamicTraits_deniesOnNonMatchingTrait() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_LEGENDARY;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(nft), TIER_KEY, allowed);

        assertFalse(predicate.hasAccess(toolId, holder, abi.encode(TOKEN_ID)));
    }

    function test_realDynamicTraits_unsetTraitReturnsZero_deniedBecauseZeroNotAllowed() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(nft), TIER_KEY, allowed);

        // TOKEN_ID_UNSET has a registered key but no value → bytes32(0), which won't match.
        assertFalse(predicate.hasAccess(toolId, holder, abi.encode(TOKEN_ID_UNSET)));
    }

    function test_realDynamicTraits_unregisteredKey_reverts_predicateReturnsFalse() public {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(nft), address(nft), UNREGISTERED_KEY, allowed);

        // DynamicTraits reverts with TraitDoesNotExist for unregistered keys.
        // The predicate's try/catch wraps this and returns false.
        assertFalse(predicate.hasAccess(toolId, holder, abi.encode(TOKEN_ID)));
    }

    function test_realDynamicTraits_separateTraitsContract() public {
        // Use the NFT for ownership, deploy a separate DynamicTraits for traits.
        MockERC721 ownershipNft = new MockERC721();
        ownershipNft.setOwner(TOKEN_ID, holder);

        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = TIER_RARE;

        vm.prank(creator);
        predicate.configureToolTrait(toolId, address(ownershipNft), address(nft), TIER_KEY, allowed);

        assertTrue(predicate.hasAccess(toolId, holder, abi.encode(TOKEN_ID)));
    }
}
