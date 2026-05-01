// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721OwnerPredicate} from "../examples/ERC721OwnerPredicate.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {IERC721Holding} from "../src/interfaces/IRequirementTypes.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";

/// @dev Minimal mock ERC-721 with configurable balanceOf.
contract MockERC721 {
    mapping(address => uint256) private _balances;

    function setBalance(address account, uint256 balance) external {
        _balances[account] = balance;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId;
    }
}

/// @dev Contract that does not implement balanceOf.
contract NotAnNFT {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract ERC721OwnerPredicateTest is Test {
    ToolRegistry public registry;
    ERC721OwnerPredicate public predicate;
    MockERC721 public nft;
    MockERC721 public nft2;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");
    address nonHolder = makeAddr("nonHolder");
    address stranger = makeAddr("stranger");

    string constant META_URI = "https://api.opensea.io/.well-known/erc-xxxx/tools/holder-swaps.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");
    uint256 toolId;

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new ERC721OwnerPredicate(address(registry));
        nft = new MockERC721();
        nft2 = new MockERC721();

        vm.prank(creator);
        toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
    }

    // ── setCollections ──────────────────────────────────────────────────

    function test_setCollections_singleCollection() public {
        address[] memory cols = new address[](1);
        cols[0] = address(nft);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        address[] memory stored = predicate.getCollections(toolId);
        assertEq(stored.length, 1);
        assertEq(stored[0], address(nft));
    }

    function test_setCollections_multipleCollections() public {
        address[] memory cols = new address[](2);
        cols[0] = address(nft);
        cols[1] = address(nft2);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        address[] memory stored = predicate.getCollections(toolId);
        assertEq(stored.length, 2);
        assertEq(stored[0], address(nft));
        assertEq(stored[1], address(nft2));
    }

    function test_setCollections_replacesExisting() public {
        address[] memory cols1 = new address[](1);
        cols1[0] = address(nft);

        address[] memory cols2 = new address[](1);
        cols2[0] = address(nft2);

        vm.startPrank(creator);
        predicate.setCollections(toolId, cols1);
        predicate.setCollections(toolId, cols2);
        vm.stopPrank();

        address[] memory stored = predicate.getCollections(toolId);
        assertEq(stored.length, 1);
        assertEq(stored[0], address(nft2));
    }

    function test_setCollections_emptyArrayClearsGate() public {
        address[] memory cols = new address[](1);
        cols[0] = address(nft);

        vm.startPrank(creator);
        predicate.setCollections(toolId, cols);
        predicate.setCollections(toolId, new address[](0));
        vm.stopPrank();

        assertEq(predicate.getCollections(toolId).length, 0);
    }

    function test_setCollections_emitsEvent() public {
        address[] memory cols = new address[](2);
        cols[0] = address(nft);
        cols[1] = address(nft2);

        vm.expectEmit(true, false, false, true);
        emit ERC721OwnerPredicate.CollectionsSet(toolId, cols);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);
    }

    function test_setCollections_revertsIfNotCreator() public {
        address[] memory cols = new address[](1);
        cols[0] = address(nft);

        vm.expectRevert(abi.encodeWithSelector(ERC721OwnerPredicate.CallerIsNotToolCreator.selector, toolId, stranger));
        vm.prank(stranger);
        predicate.setCollections(toolId, cols);
    }

    function test_setCollections_revertsIfTooMany() public {
        uint256 max = predicate.MAX_COLLECTIONS_PER_TOOL();
        address[] memory cols = new address[](max + 1);
        for (uint256 i; i < cols.length; ++i) {
            cols[i] = address(new MockERC721());
        }

        vm.expectRevert(abi.encodeWithSelector(ERC721OwnerPredicate.TooManyCollections.selector, max + 1, max));
        vm.prank(creator);
        predicate.setCollections(toolId, cols);
    }

    function test_setCollections_revertsOnZeroAddress() public {
        address[] memory cols = new address[](1);
        cols[0] = address(0);

        vm.expectRevert(abi.encodeWithSelector(ERC721OwnerPredicate.CollectionNoCode.selector, address(0)));
        vm.prank(creator);
        predicate.setCollections(toolId, cols);
    }

    function test_setCollections_revertsOnEOA() public {
        address eoa = makeAddr("eoa");
        address[] memory cols = new address[](1);
        cols[0] = eoa;

        vm.expectRevert(abi.encodeWithSelector(ERC721OwnerPredicate.CollectionNoCode.selector, eoa));
        vm.prank(creator);
        predicate.setCollections(toolId, cols);
    }

    function test_setCollections_maxCollectionsSucceeds() public {
        uint256 max = predicate.MAX_COLLECTIONS_PER_TOOL();
        address[] memory cols = new address[](max);
        for (uint256 i; i < max; ++i) {
            cols[i] = address(new MockERC721());
        }

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        assertEq(predicate.getCollections(toolId).length, max);
    }

    // ── hasAccess ────────────────────────────────────────────────────────

    function test_hasAccess_trueWhenHoldsInFirstCollection() public {
        nft.setBalance(holder, 1);

        address[] memory cols = new address[](2);
        cols[0] = address(nft);
        cols[1] = address(nft2);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_trueWhenHoldsInSecondCollection() public {
        nft2.setBalance(holder, 1);

        address[] memory cols = new address[](2);
        cols[0] = address(nft);
        cols[1] = address(nft2);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_trueWhenHoldsInAllCollections() public {
        nft.setBalance(holder, 5);
        nft2.setBalance(holder, 3);

        address[] memory cols = new address[](2);
        cols[0] = address(nft);
        cols[1] = address(nft2);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_falseWhenHoldsNone() public {
        address[] memory cols = new address[](2);
        cols[0] = address(nft);
        cols[1] = address(nft2);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        assertFalse(predicate.hasAccess(toolId, nonHolder, ""));
    }

    function test_hasAccess_falseWhenNoCollectionsSet() public view {
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_falseWhenCollectionsCleared() public {
        nft.setBalance(holder, 1);

        address[] memory cols = new address[](1);
        cols[0] = address(nft);

        vm.startPrank(creator);
        predicate.setCollections(toolId, cols);
        predicate.setCollections(toolId, new address[](0));
        vm.stopPrank();

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_skipsContractWithoutBalanceOf() public {
        NotAnNFT notNft = new NotAnNFT();
        nft.setBalance(holder, 1);

        address[] memory cols = new address[](2);
        cols[0] = address(notNft);
        cols[1] = address(nft);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_ignoresToolIdForDifferentTools() public {
        nft.setBalance(holder, 1);

        address[] memory cols = new address[](1);
        cols[0] = address(nft);

        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        // A different toolId with no collections configured should return false.
        vm.prank(creator);
        uint256 toolId2 = registry.registerTool(
            "https://api.opensea.io/.well-known/erc-xxxx/tools/other.json", keccak256("manifest-v2"), address(predicate)
        );

        assertTrue(predicate.hasAccess(toolId, holder, ""));
        assertFalse(predicate.hasAccess(toolId2, holder, ""));
    }

    // ── getCollections ──────────────────────────────────────────────────

    function test_getCollections_returnsEmptyByDefault() public view {
        assertEq(predicate.getCollections(toolId).length, 0);
    }

    // ── supportsInterface ───────────────────────────────────────────────

    function test_supportsInterface_IAccessPredicate() public view {
        assertTrue(predicate.supportsInterface(type(IAccessPredicate).interfaceId));
    }

    function test_supportsInterface_IERC165() public view {
        assertTrue(predicate.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_falseForRandom() public view {
        assertFalse(predicate.supportsInterface(0xdeadbeef));
    }

    // ── name + version ──────────────────────────────────────────────────

    function test_name() public view {
        assertEq(predicate.name(), "ERC721OwnerPredicate");
    }

    function test_version() public view {
        assertEq(predicate.version(), "0.1");
    }

    // ── registry immutable ──────────────────────────────────────────────

    function test_registry_isImmutable() public view {
        assertEq(address(predicate.REGISTRY()), address(registry));
    }

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert("ERC721OwnerPredicate: zero registry");
        new ERC721OwnerPredicate(address(0));
    }

    // ── getRequirements ──────────────────────────────────────────────────

    function test_getRequirements_emptyWhenNoCollections() public view {
        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 0);
        assertEq(uint256(logic), uint256(RequirementLogic.OR));
    }

    function test_getRequirements_singleCollection() public {
        address[] memory cols = new address[](1);
        cols[0] = address(nft);
        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 1);
        assertEq(reqs[0].kind, type(IERC721Holding).interfaceId);
        assertEq(abi.decode(reqs[0].data, (address)), address(nft));
        assertEq(bytes(reqs[0].label).length, 0);
        assertEq(uint256(logic), uint256(RequirementLogic.OR));
    }

    function test_getRequirements_multipleCollections() public {
        address[] memory cols = new address[](2);
        cols[0] = address(nft);
        cols[1] = address(nft2);
        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 2);
        assertEq(abi.decode(reqs[0].data, (address)), address(nft));
        assertEq(abi.decode(reqs[1].data, (address)), address(nft2));
        assertEq(uint256(logic), uint256(RequirementLogic.OR));
    }
}

contract ERC721OwnerPredicateIntegrationTest is Test {
    ToolRegistry public registry;
    ERC721OwnerPredicate public predicate;
    MockERC721 public nft;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");
    address nonHolder = makeAddr("nonHolder");
    string constant META_URI = "https://api.opensea.io/.well-known/erc-xxxx/tools/holder-swaps.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new ERC721OwnerPredicate(address(registry));
        nft = new MockERC721();
    }

    function test_registry_delegatesToPredicate_granted() public {
        nft.setBalance(holder, 1);

        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        address[] memory cols = new address[](1);
        cols[0] = address(nft);
        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        assertTrue(registry.hasAccess(toolId, holder, ""));
    }

    function test_registry_delegatesToPredicate_denied() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        address[] memory cols = new address[](1);
        cols[0] = address(nft);
        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        assertFalse(registry.hasAccess(toolId, nonHolder, ""));
    }

    function test_registry_tryHasAccess_returnsCorrectTuple() public {
        nft.setBalance(holder, 1);

        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        address[] memory cols = new address[](1);
        cols[0] = address(nft);
        vm.prank(creator);
        predicate.setCollections(toolId, cols);

        (bool ok, bool granted) = registry.tryHasAccess(toolId, holder, "");
        assertTrue(ok);
        assertTrue(granted);

        (bool ok2, bool granted2) = registry.tryHasAccess(toolId, nonHolder, "");
        assertTrue(ok2);
        assertFalse(granted2);
    }

    function test_registry_samePredicateMultipleTools() public {
        MockERC721 nft2 = new MockERC721();
        nft.setBalance(holder, 1);

        vm.startPrank(creator);
        uint256 tool1 = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        uint256 tool2 = registry.registerTool(
            "https://api.opensea.io/.well-known/erc-xxxx/tools/holder-tokens.json",
            keccak256("manifest-v2"),
            address(predicate)
        );
        vm.stopPrank();

        address[] memory cols1 = new address[](1);
        cols1[0] = address(nft);
        address[] memory cols2 = new address[](1);
        cols2[0] = address(nft2);

        vm.startPrank(creator);
        predicate.setCollections(tool1, cols1);
        predicate.setCollections(tool2, cols2);
        vm.stopPrank();

        assertTrue(registry.hasAccess(tool1, holder, ""));
        assertFalse(registry.hasAccess(tool2, holder, ""));
    }
}
