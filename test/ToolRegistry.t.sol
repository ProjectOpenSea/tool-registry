// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";
import {IToolRegistry, ToolConfig} from "../src/interfaces/IToolRegistry.sol";
import {IAccessPredicate} from "../src/interfaces/IAccessPredicate.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ConfigurableReturnPredicate} from "./mocks/ConfigurableReturnPredicate.sol";
import {DataCheckPredicate} from "./mocks/DataCheckPredicate.sol";
import {DenyAllPredicate} from "./mocks/DenyAllPredicate.sol";
import {GasBurnerPredicate} from "./mocks/GasBurnerPredicate.sol";
import {MalformedBoolPredicate} from "./mocks/MalformedBoolPredicate.sol";
import {MockAccessPredicate} from "./mocks/MockAccessPredicate.sol";
import {NonPredicateERC165} from "./mocks/NonPredicateERC165.sol";
import {OversizeReturnPredicate} from "./mocks/OversizeReturnPredicate.sol";
import {RevertingERC165} from "./mocks/RevertingERC165.sol";
import {RevertingPredicate} from "./mocks/RevertingPredicate.sol";

contract ToolRegistryTest is Test {
    ToolRegistry public registry;
    MockAccessPredicate public predicate;

    address creator = makeAddr("creator");
    address other = makeAddr("other");
    string constant META_URI = "https://example.com/tool.json";
    string constant META_URI_2 = "ipfs://QmUpdated";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");
    bytes32 constant MANIFEST_HASH_2 = keccak256("manifest-v2");

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new MockAccessPredicate();
    }

    // --- registerTool ---

    function test_registerTool_open() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        assertEq(toolId, 1);

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(config.creator, creator);
        assertEq(config.metadataURI, META_URI);
        assertEq(config.manifestHash, MANIFEST_HASH);
        assertEq(config.accessPredicate, address(0));
    }

    function test_registerTool_withPredicate() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        assertEq(toolId, 1);

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(config.accessPredicate, address(predicate));
    }

    function test_registerTool_autoIncrementingIds() public {
        vm.startPrank(creator);
        uint256 id1 = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        uint256 id2 = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        uint256 id3 = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
    }

    function test_registerTool_emitsEvent() public {
        vm.prank(creator);
        vm.expectEmit(true, true, true, true);
        emit IToolRegistry.ToolRegistered(1, creator, address(0), META_URI, MANIFEST_HASH);
        registry.registerTool(META_URI, MANIFEST_HASH, address(0));
    }

    function test_registerTool_emitsEvent_withPredicate() public {
        vm.prank(creator);
        vm.expectEmit(true, true, true, true);
        emit IToolRegistry.ToolRegistered(1, creator, address(predicate), META_URI, MANIFEST_HASH);
        registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
    }

    function test_registerTool_revertsOnEmptyURI() public {
        vm.prank(creator);
        vm.expectRevert(IToolRegistry.InvalidMetadataURI.selector);
        registry.registerTool("", MANIFEST_HASH, address(0));
    }

    function test_registerTool_acceptsUriAtCap() public {
        string memory uri = _makeUri(2048);
        vm.prank(creator);
        uint256 toolId = registry.registerTool(uri, MANIFEST_HASH, address(0));
        assertEq(toolId, 1);
    }

    function test_registerTool_revertsOnUriAboveCap() public {
        string memory uri = _makeUri(2049);
        vm.prank(creator);
        vm.expectRevert(IToolRegistry.InvalidMetadataURI.selector);
        registry.registerTool(uri, MANIFEST_HASH, address(0));
    }

    function test_registerTool_revertsOnZeroManifestHash() public {
        vm.prank(creator);
        vm.expectRevert(IToolRegistry.InvalidManifestHash.selector);
        registry.registerTool(META_URI, bytes32(0), address(0));
    }

    // --- updateToolMetadata ---

    function test_updateToolMetadata() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.expectEmit(true, false, false, true);
        emit IToolRegistry.ToolMetadataUpdated(toolId, META_URI_2, MANIFEST_HASH_2);
        registry.updateToolMetadata(toolId, META_URI_2, MANIFEST_HASH_2);
        vm.stopPrank();

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(config.metadataURI, META_URI_2);
        assertEq(config.manifestHash, MANIFEST_HASH_2);
    }

    function test_updateToolMetadata_idempotent_noEventOnSameValues() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.recordLogs();
        registry.updateToolMetadata(toolId, META_URI, MANIFEST_HASH);
        vm.stopPrank();

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_updateToolMetadata_revertsIfNotCreator() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.NotToolCreator.selector, toolId, other));
        registry.updateToolMetadata(toolId, META_URI_2, MANIFEST_HASH_2);
    }

    function test_updateToolMetadata_revertsOnEmptyURI() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        vm.expectRevert(IToolRegistry.InvalidMetadataURI.selector);
        registry.updateToolMetadata(toolId, "", MANIFEST_HASH_2);
        vm.stopPrank();
    }

    function test_updateToolMetadata_revertsOnUriAboveCap() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        string memory uri = _makeUri(2049);
        vm.expectRevert(IToolRegistry.InvalidMetadataURI.selector);
        registry.updateToolMetadata(toolId, uri, MANIFEST_HASH_2);
        vm.stopPrank();
    }

    function test_updateToolMetadata_acceptsUriAtCap() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        string memory uri = _makeUri(2048);
        registry.updateToolMetadata(toolId, uri, MANIFEST_HASH_2);
        vm.stopPrank();

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(bytes(config.metadataURI).length, 2048);
        assertEq(config.manifestHash, MANIFEST_HASH_2);
    }

    function test_updateToolMetadata_revertsOnZeroManifestHash() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        vm.expectRevert(IToolRegistry.InvalidManifestHash.selector);
        registry.updateToolMetadata(toolId, META_URI_2, bytes32(0));
        vm.stopPrank();
    }

    function test_updateToolMetadata_revertsIfNotFound() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 999));
        registry.updateToolMetadata(999, META_URI_2, MANIFEST_HASH_2);
    }

    // --- setAccessPredicate ---

    function test_setAccessPredicate() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.expectEmit(true, true, false, true);
        emit IToolRegistry.AccessPredicateUpdated(toolId, address(predicate));
        registry.setAccessPredicate(toolId, address(predicate));
        vm.stopPrank();

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(config.accessPredicate, address(predicate));
    }

    function test_setAccessPredicate_toZero() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        registry.setAccessPredicate(toolId, address(0));
        vm.stopPrank();

        ToolConfig memory config = registry.getToolConfig(toolId);
        assertEq(config.accessPredicate, address(0));
    }

    function test_setAccessPredicate_idempotent_noEventOnSameValue() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        vm.recordLogs();
        registry.setAccessPredicate(toolId, address(predicate));
        vm.stopPrank();

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_setAccessPredicate_revertsIfNotCreator() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.NotToolCreator.selector, toolId, other));
        registry.setAccessPredicate(toolId, address(predicate));
    }

    function test_setAccessPredicate_revertsIfNotFound() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 999));
        registry.setAccessPredicate(999, address(predicate));
    }

    function test_setAccessPredicate_revertsForInvalidERC165Predicate() public {
        NonPredicateERC165 bad = new NonPredicateERC165();
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.InvalidAccessPredicate.selector, address(bad)));
        registry.setAccessPredicate(toolId, address(bad));
        vm.stopPrank();
    }

    function test_setAccessPredicate_revertsForERC165ThatRevertsOnPredicateQuery() public {
        RevertingERC165 bad = new RevertingERC165();
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.InvalidAccessPredicate.selector, address(bad)));
        registry.setAccessPredicate(toolId, address(bad));
        vm.stopPrank();
    }

    // --- registerTool predicate validation ---

    function test_registerTool_revertsForInvalidERC165Predicate() public {
        NonPredicateERC165 bad = new NonPredicateERC165();
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.InvalidAccessPredicate.selector, address(bad)));
        registry.registerTool(META_URI, MANIFEST_HASH, address(bad));
    }

    function test_registerTool_revertsForERC165ThatRevertsOnPredicateQuery() public {
        RevertingERC165 bad = new RevertingERC165();
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.InvalidAccessPredicate.selector, address(bad)));
        registry.registerTool(META_URI, MANIFEST_HASH, address(bad));
    }

    function test_registerTool_allowsNonERC165Predicate() public {
        RevertingPredicate noErc165 = new RevertingPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(noErc165));
        assertEq(registry.getToolConfig(toolId).accessPredicate, address(noErc165));
    }

    function test_registerTool_allowsEOAPredicate() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0xdead));
        assertEq(registry.getToolConfig(toolId).accessPredicate, address(0xdead));
    }

    // --- getToolConfig ---

    function test_getToolConfig_revertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 42));
        registry.getToolConfig(42);
    }

    // --- hasAccess ---

    function test_hasAccess_openToolReturnsTrue() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        assertTrue(registry.hasAccess(toolId, other, ""));
        assertTrue(registry.hasAccess(toolId, address(0), ""));
    }

    function test_hasAccess_predicateGated_allowed() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        predicate.setAllowed(other, true);
        assertTrue(registry.hasAccess(toolId, other, ""));
    }

    function test_hasAccess_predicateGated_denied() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        assertFalse(registry.hasAccess(toolId, other, ""));
    }

    function test_hasAccess_revertingPredicateReturnsFalse() public {
        RevertingPredicate bad = new RevertingPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        assertFalse(registry.hasAccess(toolId, other, ""));
    }

    function test_hasAccess_revertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 999));
        registry.hasAccess(999, other, "");
    }

    function test_hasAccess_forwardsData() public {
        DataCheckPredicate dataPredicate = new DataCheckPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(dataPredicate));

        bytes memory validData = abi.encode(uint256(42));
        assertTrue(registry.hasAccess(toolId, other, validData));
        assertFalse(registry.hasAccess(toolId, other, ""));
    }

    function test_hasAccess_rejectsNonCanonicalBool() public {
        MalformedBoolPredicate bad = new MalformedBoolPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        // Predicate returns uint256(2), which is not a canonical ABI-encoded bool.
        // Strict decoding must treat this as "access denied" rather than truthy.
        assertFalse(registry.hasAccess(toolId, other, ""));
    }

    function testFuzz_hasAccess_rejectsNonCanonicalBool(uint256 v) public {
        vm.assume(v != 0 && v != 1);
        ConfigurableReturnPredicate bad = new ConfigurableReturnPredicate(v);
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        // Any 32-byte word other than 0 or 1 is non-canonical per the ABI,
        // and strict decoding must treat every such value as "access denied."
        assertFalse(registry.hasAccess(toolId, other, ""));
    }

    function test_hasAccess_zeroCodePredicateDenies() public {
        // EOA-like predicate (no code) is accepted at registration time but
        // returns empty data from staticcall, which must fail-closed.
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0xdead));
        assertFalse(registry.hasAccess(toolId, other, ""));
    }

    function test_hasAccess_rejectsOversizeReturndata() public {
        // Predicate returns two 32-byte words (64 bytes). The registry caps
        // the returndata copy at one word but must still treat any size
        // other than 32 as a malfunction and fail closed, even if the first
        // word would otherwise decode as `true`.
        OversizeReturnPredicate bad = new OversizeReturnPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));
        assertFalse(registry.hasAccess(toolId, other, ""));
    }

    /// @dev Pins the `_PREDICATE_GAS_LIMIT` constant. A predicate whose
    ///      `hasAccess` runs an unbounded loop would, without the cap,
    ///      consume ~63/64 of the caller's remaining gas (EIP-150) and
    ///      leave only ~1/64 for the outer call. With the 200k cap in
    ///      force, the outer call completes cheaply, returns `false`, and
    ///      does not revert. Any future relaxation of the cap must pass
    ///      through this regression check.
    ///
    ///      Both an upper and a lower bound are asserted: the upper bound
    ///      catches "cap removed" regressions, and the lower bound catches
    ///      "cap silently lowered to near-zero" regressions where the
    ///      predicate would never actually get enough gas to do work.
    function test_hasAccess_boundsPredicateGas() public {
        GasBurnerPredicate bad = new GasBurnerPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        uint256 gasBefore = gasleft();
        bool granted = registry.hasAccess(toolId, other, "");
        uint256 gasUsed;
        unchecked {
            gasUsed = gasBefore - gasleft();
        }

        assertFalse(granted);
        // The 200k predicate cap plus registry overhead (existence check,
        // staticcall framing, bool decode) is well under 500k. Without the
        // cap the outer call would consume many millions of gas.
        assertLt(gasUsed, 500_000);
        // Lower bound: the predicate deliberately burns its full forwarded
        // budget, so the outer call must consume at least most of the
        // 200k cap. A silently-reduced cap would fail this bound.
        assertGt(gasUsed, 150_000);
    }

    function test_tryHasAccess_boundsPredicateGas() public {
        GasBurnerPredicate bad = new GasBurnerPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        uint256 gasBefore = gasleft();
        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        uint256 gasUsed;
        unchecked {
            gasUsed = gasBefore - gasleft();
        }

        assertFalse(ok);
        assertFalse(granted);
        assertLt(gasUsed, 500_000);
        assertGt(gasUsed, 150_000);
    }

    // --- pause/unpause via predicate swap ---

    /// @dev Exercises the pattern the spec rationale advocates as the
    ///      replacement for the removed `active` flag: a creator pauses
    ///      a tool by pointing `accessPredicate` at an always-deny
    ///      predicate, and un-pauses by restoring the original predicate.
    function test_pauseUnpauseViaDenyPredicate() public {
        DenyAllPredicate deny = new DenyAllPredicate();

        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        predicate.setAllowed(other, true);

        // Baseline: access is granted under the original predicate.
        assertTrue(registry.hasAccess(toolId, other, ""));

        // Pause: point accessPredicate at the always-deny predicate. The
        // tool is now effectively offline to every caller.
        vm.prank(creator);
        registry.setAccessPredicate(toolId, address(deny));
        assertFalse(registry.hasAccess(toolId, other, ""));
        assertFalse(registry.hasAccess(toolId, creator, ""));

        // Un-pause: restore the original predicate. Access resumes.
        vm.prank(creator);
        registry.setAccessPredicate(toolId, address(predicate));
        assertTrue(registry.hasAccess(toolId, other, ""));
    }

    // --- tryHasAccess ---

    function test_tryHasAccess_openToolReturnsOkGranted() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        assertTrue(ok);
        assertTrue(granted);
    }

    function test_tryHasAccess_predicateAllowsReturnsOkGranted() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        predicate.setAllowed(other, true);

        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        assertTrue(ok);
        assertTrue(granted);
    }

    function test_tryHasAccess_predicateDeniesReturnsOkNotGranted() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        // Predicate returns false cleanly: clean negative answer.
        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        assertTrue(ok);
        assertFalse(granted);
    }

    function test_tryHasAccess_revertingPredicateReturnsNotOk() public {
        RevertingPredicate bad = new RevertingPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        // Predicate reverted: malfunction, not a clean denial.
        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        assertFalse(ok);
        assertFalse(granted);
    }

    function test_tryHasAccess_nonCanonicalBoolReturnsNotOk() public {
        MalformedBoolPredicate bad = new MalformedBoolPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        // Predicate returned uint256(2), not a canonical ABI-encoded bool.
        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        assertFalse(ok);
        assertFalse(granted);
    }

    function testFuzz_tryHasAccess_rejectsNonCanonicalBool(uint256 v) public {
        vm.assume(v != 0 && v != 1);
        ConfigurableReturnPredicate bad = new ConfigurableReturnPredicate(v);
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        // Any 32-byte word other than 0 or 1 is non-canonical per the ABI,
        // and tryHasAccess must surface every such value as (ok=false, granted=false).
        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        assertFalse(ok);
        assertFalse(granted);
    }

    function test_tryHasAccess_forwardsData() public {
        DataCheckPredicate dataPredicate = new DataCheckPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(dataPredicate));

        bytes memory validData = abi.encode(uint256(42));
        (bool okValid, bool grantedValid) = registry.tryHasAccess(toolId, other, validData);
        assertTrue(okValid);
        assertTrue(grantedValid);

        (bool okEmpty, bool grantedEmpty) = registry.tryHasAccess(toolId, other, "");
        assertTrue(okEmpty);
        assertFalse(grantedEmpty);
    }

    function test_tryHasAccess_zeroCodePredicateReturnsNotOk() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0xdead));

        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        assertFalse(ok);
        assertFalse(granted);
    }

    function test_tryHasAccess_oversizeReturndataIsNotOk() public {
        OversizeReturnPredicate bad = new OversizeReturnPredicate();
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(bad));

        (bool ok, bool granted) = registry.tryHasAccess(toolId, other, "");
        assertFalse(ok);
        assertFalse(granted);
    }

    function test_tryHasAccess_revertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 999));
        registry.tryHasAccess(999, other, "");
    }

    // --- toolCount ---

    function test_toolCount() public {
        assertEq(registry.toolCount(), 0);

        vm.startPrank(creator);
        registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        assertEq(registry.toolCount(), 1);

        registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
        assertEq(registry.toolCount(), 2);
        vm.stopPrank();
    }

    // --- ERC-165 ---

    function test_supportsInterface_IToolRegistry() public view {
        assertTrue(registry.supportsInterface(type(IToolRegistry).interfaceId));
    }

    function test_supportsInterface_IToolRegistry_pinsId() public view {
        // Pins the IToolRegistry ERC-165 interface ID so the interface cannot
        // drift without the accompanying spec update. Derived from the XOR of
        // every selector in IToolRegistry.
        assertEq(type(IToolRegistry).interfaceId, bytes4(0xf1dc8075));
        assertTrue(registry.supportsInterface(0xf1dc8075));
    }

    function test_interfaceId_IAccessPredicate_pinned() public pure {
        // XOR of the `hasAccess`, `name`, and `getRequirements` selectors.
        assertEq(type(IAccessPredicate).interfaceId, bytes4(0xbdf9dc18));
    }

    // --- name + version ---

    function test_name() public view {
        assertEq(registry.name(), "ToolRegistry");
    }

    function test_version() public view {
        assertEq(registry.version(), "0.1");
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_invalid() public view {
        assertFalse(registry.supportsInterface(0xdeadbeef));
    }

    function test_supportsInterface_rejectsCanonicalInvalidId() public view {
        // ERC-165 requires `supportsInterface(0xffffffff)` to return false.
        // Pinning this explicitly catches a regression where a future
        // refactor or an OZ update breaks the standard-mandated case.
        assertFalse(registry.supportsInterface(0xffffffff));
    }

    // --- deregisterTool ---

    function test_deregisterTool() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit IToolRegistry.ToolDeregistered(toolId);
        registry.deregisterTool(toolId);

        // After deregistration, getToolConfig reverts with ToolIsDeregistered.
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolIsDeregistered.selector, toolId));
        registry.getToolConfig(toolId);
    }

    function test_deregisterTool_hasAccessRevertsAfterDeregistration() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.prank(creator);
        registry.deregisterTool(toolId);

        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolIsDeregistered.selector, toolId));
        registry.hasAccess(toolId, other, "");
    }

    function test_deregisterTool_tryHasAccessRevertsAfterDeregistration() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.prank(creator);
        registry.deregisterTool(toolId);

        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolIsDeregistered.selector, toolId));
        registry.tryHasAccess(toolId, other, "");
    }

    function test_deregisterTool_revertsIfNotCreator() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.NotToolCreator.selector, toolId, other));
        registry.deregisterTool(toolId);
    }

    function test_deregisterTool_revertsIfNotFound() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, 999));
        registry.deregisterTool(999);
    }

    function test_deregisterTool_revertsIfAlreadyDeregistered() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        registry.deregisterTool(toolId);

        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolIsDeregistered.selector, toolId));
        registry.deregisterTool(toolId);
        vm.stopPrank();
    }

    function test_deregisterTool_updateMetadataRevertsAfterDeregistration() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        registry.deregisterTool(toolId);

        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolIsDeregistered.selector, toolId));
        registry.updateToolMetadata(toolId, META_URI_2, MANIFEST_HASH_2);
        vm.stopPrank();
    }

    function test_deregisterTool_setPredicateRevertsAfterDeregistration() public {
        vm.startPrank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        registry.deregisterTool(toolId);

        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolIsDeregistered.selector, toolId));
        registry.setAccessPredicate(toolId, address(predicate));
        vm.stopPrank();
    }

    function test_deregisterTool_deregisteredToolRevertsBeforeAuthCheck() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        vm.prank(creator);
        registry.deregisterTool(toolId);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolIsDeregistered.selector, toolId));
        registry.deregisterTool(toolId);
    }

    function test_deregisterTool_doesNotAffectToolCount() public {
        vm.startPrank(creator);
        registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        uint256 toolId2 = registry.registerTool(META_URI, MANIFEST_HASH, address(0));
        assertEq(registry.toolCount(), 2);

        registry.deregisterTool(toolId2);
        // toolCount still returns the high-water mark (IDs are never reused).
        assertEq(registry.toolCount(), 2);
        vm.stopPrank();
    }

    // --- helpers ---

    function _makeUri(uint256 len) internal pure returns (string memory) {
        bytes memory buf = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            buf[i] = 0x61; // 'a'
        }
        return string(buf);
    }
}

