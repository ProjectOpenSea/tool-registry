// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155OwnerPredicate} from "../examples/ERC1155OwnerPredicate.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {IERC1155Holding} from "../src/interfaces/IRequirementTypes.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";

/// @dev Minimal mock ERC-1155 with configurable per-(account, id) balances.
contract MockERC1155 {
    mapping(address => mapping(uint256 => uint256)) private _balances;

    function setBalance(address account, uint256 id, uint256 balance) external {
        _balances[account][id] = balance;
    }

    function balanceOf(address account, uint256 id) external view returns (uint256) {
        return _balances[account][id];
    }

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "length");
        uint256[] memory out = new uint256[](accounts.length);
        for (uint256 i; i < accounts.length; ++i) {
            out[i] = _balances[accounts[i]][ids[i]];
        }
        return out;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155).interfaceId;
    }
}

/// @dev Contract that does not implement balanceOfBatch.
contract NotAn1155 {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract ERC1155OwnerPredicateTest is Test {
    ToolRegistry public registry;
    ERC1155OwnerPredicate public predicate;
    MockERC1155 public nft;
    MockERC1155 public nft2;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");
    address nonHolder = makeAddr("nonHolder");
    address stranger = makeAddr("stranger");

    string constant META_URI = "https://api.opensea.io/.well-known/erc-draft/tools/1155-gate.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");
    uint256 toolId;

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new ERC1155OwnerPredicate(address(registry));
        nft = new MockERC1155();
        nft2 = new MockERC1155();

        vm.prank(creator);
        toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
    }

    function _entry(address collection, uint256[] memory tokenIds)
        internal
        pure
        returns (ERC1155OwnerPredicate.CollectionTokens memory)
    {
        return ERC1155OwnerPredicate.CollectionTokens({collection: collection, tokenIds: tokenIds});
    }

    function _ids(uint256 a) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = a;
    }

    function _ids(uint256 a, uint256 b) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](2);
        ids[0] = a;
        ids[1] = b;
    }

    // ── setCollectionTokens ─────────────────────────────────────────────

    function test_setCollectionTokens_singleEntry() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(1));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        ERC1155OwnerPredicate.CollectionTokens[] memory stored = predicate.getCollectionTokens(toolId);
        assertEq(stored.length, 1);
        assertEq(stored[0].collection, address(nft));
        assertEq(stored[0].tokenIds.length, 1);
        assertEq(stored[0].tokenIds[0], 1);
    }

    function test_setCollectionTokens_multipleEntries() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](2);
        entries[0] = _entry(address(nft), _ids(1, 2));
        entries[1] = _entry(address(nft2), _ids(7));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        ERC1155OwnerPredicate.CollectionTokens[] memory stored = predicate.getCollectionTokens(toolId);
        assertEq(stored.length, 2);
        assertEq(stored[0].collection, address(nft));
        assertEq(stored[0].tokenIds.length, 2);
        assertEq(stored[0].tokenIds[1], 2);
        assertEq(stored[1].collection, address(nft2));
        assertEq(stored[1].tokenIds[0], 7);
    }

    function test_setCollectionTokens_replacesExisting() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory first = new ERC1155OwnerPredicate.CollectionTokens[](1);
        first[0] = _entry(address(nft), _ids(1, 2));

        ERC1155OwnerPredicate.CollectionTokens[] memory second = new ERC1155OwnerPredicate.CollectionTokens[](1);
        second[0] = _entry(address(nft2), _ids(9));

        vm.startPrank(creator);
        predicate.setCollectionTokens(toolId, first);
        predicate.setCollectionTokens(toolId, second);
        vm.stopPrank();

        ERC1155OwnerPredicate.CollectionTokens[] memory stored = predicate.getCollectionTokens(toolId);
        assertEq(stored.length, 1);
        assertEq(stored[0].collection, address(nft2));
        assertEq(stored[0].tokenIds.length, 1);
        assertEq(stored[0].tokenIds[0], 9);
    }

    function test_setCollectionTokens_emptyArrayClearsGate() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory first = new ERC1155OwnerPredicate.CollectionTokens[](1);
        first[0] = _entry(address(nft), _ids(1));

        vm.startPrank(creator);
        predicate.setCollectionTokens(toolId, first);
        predicate.setCollectionTokens(toolId, new ERC1155OwnerPredicate.CollectionTokens[](0));
        vm.stopPrank();

        assertEq(predicate.getCollectionTokens(toolId).length, 0);
    }

    function test_setCollectionTokens_emitsEvent() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(42));

        vm.expectEmit(true, false, false, true);
        emit ERC1155OwnerPredicate.CollectionTokensSet(toolId, entries);

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);
    }

    function test_setCollectionTokens_revertsIfNotCreator() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(1));

        vm.expectRevert(abi.encodeWithSelector(ERC1155OwnerPredicate.CallerIsNotToolCreator.selector, toolId, stranger));
        vm.prank(stranger);
        predicate.setCollectionTokens(toolId, entries);
    }

    function test_setCollectionTokens_revertsIfTooManyCollections() public {
        uint256 max = predicate.MAX_COLLECTIONS_PER_TOOL();
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](max + 1);
        for (uint256 i; i < entries.length; ++i) {
            entries[i] = _entry(address(new MockERC1155()), _ids(i));
        }

        vm.expectRevert(abi.encodeWithSelector(ERC1155OwnerPredicate.TooManyCollections.selector, max + 1, max));
        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);
    }

    function test_setCollectionTokens_revertsIfTooManyTokenIds() public {
        uint256 max = predicate.MAX_TOKEN_IDS_PER_COLLECTION();
        uint256[] memory ids = new uint256[](max + 1);
        for (uint256 i; i < ids.length; ++i) {
            ids[i] = i;
        }

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), ids);

        vm.expectRevert(abi.encodeWithSelector(ERC1155OwnerPredicate.TooManyTokenIds.selector, 0, max + 1, max));
        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);
    }

    function test_setCollectionTokens_revertsIfEmptyTokenIds() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), new uint256[](0));

        vm.expectRevert(abi.encodeWithSelector(ERC1155OwnerPredicate.EmptyTokenIds.selector, 0));
        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);
    }

    function test_setCollectionTokens_revertsOnZeroAddress() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(0), _ids(1));

        vm.expectRevert(abi.encodeWithSelector(ERC1155OwnerPredicate.CollectionNoCode.selector, address(0)));
        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);
    }

    function test_setCollectionTokens_revertsOnEOA() public {
        address eoa = makeAddr("eoa");
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(eoa, _ids(1));

        vm.expectRevert(abi.encodeWithSelector(ERC1155OwnerPredicate.CollectionNoCode.selector, eoa));
        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);
    }

    function test_setCollectionTokens_maxConfigSucceeds() public {
        uint256 maxC = predicate.MAX_COLLECTIONS_PER_TOOL();
        uint256 maxIds = predicate.MAX_TOKEN_IDS_PER_COLLECTION();

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](maxC);
        for (uint256 i; i < maxC; ++i) {
            uint256[] memory ids = new uint256[](maxIds);
            for (uint256 j; j < maxIds; ++j) {
                ids[j] = j;
            }
            entries[i] = _entry(address(new MockERC1155()), ids);
        }

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        assertEq(predicate.getCollectionTokens(toolId).length, maxC);
    }

    // ── hasAccess ────────────────────────────────────────────────────────

    function test_hasAccess_trueWhenOwnsConfiguredId() public {
        nft.setBalance(holder, 1, 1);

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(1, 2));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_trueWhenOwnsAnyOfMultipleIds() public {
        nft.setBalance(holder, 2, 3);

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(1, 2));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_trueWhenOwnsInSecondEntry() public {
        nft2.setBalance(holder, 7, 1);

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](2);
        entries[0] = _entry(address(nft), _ids(1));
        entries[1] = _entry(address(nft2), _ids(7));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_falseWhenOwnsUnconfiguredId() public {
        nft.setBalance(holder, 99, 5);

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(1, 2));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_falseWhenOwnsNothing() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(1));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        assertFalse(predicate.hasAccess(toolId, nonHolder, ""));
    }

    function test_hasAccess_falseWhenNoEntries() public view {
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_falseWhenCleared() public {
        nft.setBalance(holder, 1, 1);

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(1));

        vm.startPrank(creator);
        predicate.setCollectionTokens(toolId, entries);
        predicate.setCollectionTokens(toolId, new ERC1155OwnerPredicate.CollectionTokens[](0));
        vm.stopPrank();

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_skipsContractWithoutBalanceOfBatch() public {
        NotAn1155 notNft = new NotAn1155();
        nft.setBalance(holder, 1, 1);

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](2);
        entries[0] = _entry(address(notNft), _ids(1));
        entries[1] = _entry(address(nft), _ids(1));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_isolatedPerTool() public {
        nft.setBalance(holder, 1, 1);

        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = _entry(address(nft), _ids(1));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        vm.prank(creator);
        uint256 toolId2 = registry.registerTool(
            "https://api.opensea.io/.well-known/erc-draft/tools/other-1155.json",
            keccak256("manifest-v2"),
            address(predicate)
        );

        assertTrue(predicate.hasAccess(toolId, holder, ""));
        assertFalse(predicate.hasAccess(toolId2, holder, ""));
    }

    // ── getCollectionTokens ─────────────────────────────────────────────

    function test_getCollectionTokens_returnsEmptyByDefault() public view {
        assertEq(predicate.getCollectionTokens(toolId).length, 0);
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
        assertEq(predicate.name(), "ERC1155OwnerPredicate");
    }

    function test_version() public view {
        assertEq(predicate.version(), "0.2");
    }

    // ── registry immutable ──────────────────────────────────────────────

    function test_registry_isImmutable() public view {
        assertEq(address(predicate.REGISTRY()), address(registry));
    }

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert("ERC1155OwnerPredicate: zero registry");
        new ERC1155OwnerPredicate(address(0));
    }

    // ── getRequirements ──────────────────────────────────────────────────

    function test_getRequirements_emptyWhenNoEntries() public view {
        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 0);
        assertEq(uint256(logic), uint256(RequirementLogic.OR));
    }

    function test_getRequirements_expandsTokenIds() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 10;
        ids[1] = 20;
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        entries[0] = ERC1155OwnerPredicate.CollectionTokens({collection: address(nft), tokenIds: ids});

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 2);
        assertEq(reqs[0].kind, type(IERC1155Holding).interfaceId);
        (address col0, uint256 id0) = abi.decode(reqs[0].data, (address, uint256));
        assertEq(col0, address(nft));
        assertEq(id0, 10);
        (address col1, uint256 id1) = abi.decode(reqs[1].data, (address, uint256));
        assertEq(col1, address(nft));
        assertEq(id1, 20);
        assertEq(uint256(logic), uint256(RequirementLogic.OR));
    }

    function test_getRequirements_multipleCollections() public {
        ERC1155OwnerPredicate.CollectionTokens[] memory entries = new ERC1155OwnerPredicate.CollectionTokens[](2);
        uint256[] memory ids1 = new uint256[](1);
        ids1[0] = 1;
        uint256[] memory ids2 = new uint256[](1);
        ids2[0] = 42;
        entries[0] = ERC1155OwnerPredicate.CollectionTokens({collection: address(nft), tokenIds: ids1});
        entries[1] = ERC1155OwnerPredicate.CollectionTokens({collection: address(nft2), tokenIds: ids2});

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, entries);

        (AccessRequirement[] memory reqs,) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 2);
        (address c0, uint256 t0) = abi.decode(reqs[0].data, (address, uint256));
        assertEq(c0, address(nft));
        assertEq(t0, 1);
        (address c1, uint256 t1) = abi.decode(reqs[1].data, (address, uint256));
        assertEq(c1, address(nft2));
        assertEq(t1, 42);
    }
}

contract ERC1155OwnerPredicateIntegrationTest is Test {
    ToolRegistry public registry;
    ERC1155OwnerPredicate public predicate;
    MockERC1155 public nft;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");
    address nonHolder = makeAddr("nonHolder");
    string constant META_URI = "https://api.opensea.io/.well-known/erc-draft/tools/1155-gate.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new ERC1155OwnerPredicate(address(registry));
        nft = new MockERC1155();
    }

    function _entries(address collection, uint256 tokenId)
        internal
        pure
        returns (ERC1155OwnerPredicate.CollectionTokens[] memory entries)
    {
        entries = new ERC1155OwnerPredicate.CollectionTokens[](1);
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        entries[0] = ERC1155OwnerPredicate.CollectionTokens({collection: collection, tokenIds: ids});
    }

    function test_registry_delegatesToPredicate_granted() public {
        nft.setBalance(holder, 1, 1);

        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, _entries(address(nft), 1));

        assertTrue(registry.hasAccess(toolId, holder, ""));
    }

    function test_registry_delegatesToPredicate_denied() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, _entries(address(nft), 1));

        assertFalse(registry.hasAccess(toolId, nonHolder, ""));
    }

    function test_registry_tryHasAccess_returnsCorrectTuple() public {
        nft.setBalance(holder, 1, 1);

        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        vm.prank(creator);
        predicate.setCollectionTokens(toolId, _entries(address(nft), 1));

        (bool ok, bool granted) = registry.tryHasAccess(toolId, holder, "");
        assertTrue(ok);
        assertTrue(granted);

        (bool ok2, bool granted2) = registry.tryHasAccess(toolId, nonHolder, "");
        assertTrue(ok2);
        assertFalse(granted2);
    }
}
