// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {CompositePredicate} from "../examples/CompositePredicate.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";
import {MockAccessPredicate} from "./mocks/MockAccessPredicate.sol";
import {RevertingPredicate} from "./mocks/RevertingPredicate.sol";
import {GasBurnerPredicate} from "./mocks/GasBurnerPredicate.sol";
import {MalformedBoolPredicate} from "./mocks/MalformedBoolPredicate.sol";
import {MockRequirementsPredicate} from "./mocks/MockRequirementsPredicate.sol";
import {NonPredicateERC165} from "./mocks/NonPredicateERC165.sol";

contract CompositePredicateTest is Test {
    ToolRegistry public registry;
    CompositePredicate public predicate;
    MockAccessPredicate public leafA;
    MockAccessPredicate public leafB;
    MockAccessPredicate public leafC;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");
    address otherUser = makeAddr("otherUser");
    address stranger = makeAddr("stranger");

    string constant META_URI = "https://api.opensea.io/.well-known/erc-draft/tools/composite.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");
    uint256 toolId;

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new CompositePredicate(address(registry));
        leafA = new MockAccessPredicate();
        leafB = new MockAccessPredicate();
        leafC = new MockAccessPredicate();

        vm.prank(creator);
        toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
    }

    // ── helpers ─────────────────────────────────────────────────────────

    function _term(address p, bool negate) internal pure returns (CompositePredicate.Term memory) {
        return CompositePredicate.Term({predicate: p, negate: negate});
    }

    function _setOp(uint256 _toolId, CompositePredicate.Op op, CompositePredicate.Term[] memory terms) internal {
        vm.prank(creator);
        predicate.setComposition(_toolId, op, terms);
    }

    // ── setComposition ──────────────────────────────────────────────────

    function test_setComposition_singleTermStored() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertEq(uint256(predicate.getOp(toolId)), uint256(CompositePredicate.Op.ALL));
        CompositePredicate.Term[] memory stored = predicate.getTerms(toolId);
        assertEq(stored.length, 1);
        assertEq(stored[0].predicate, address(leafA));
        assertEq(stored[0].negate, false);
    }

    function test_setComposition_replacesExisting() public {
        CompositePredicate.Term[] memory first = new CompositePredicate.Term[](2);
        first[0] = _term(address(leafA), false);
        first[1] = _term(address(leafB), true);
        _setOp(toolId, CompositePredicate.Op.ALL, first);

        CompositePredicate.Term[] memory second = new CompositePredicate.Term[](1);
        second[0] = _term(address(leafC), false);
        _setOp(toolId, CompositePredicate.Op.ANY, second);

        assertEq(uint256(predicate.getOp(toolId)), uint256(CompositePredicate.Op.ANY));
        CompositePredicate.Term[] memory stored = predicate.getTerms(toolId);
        assertEq(stored.length, 1);
        assertEq(stored[0].predicate, address(leafC));
    }

    function test_setComposition_emptyArrayClearsGate() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        _setOp(toolId, CompositePredicate.Op.ALL, new CompositePredicate.Term[](0));
        assertEq(predicate.getTerms(toolId).length, 0);
        // hasAccess MUST be false on empty terms regardless of operator.
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_setComposition_emitsEvent() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), true);

        vm.expectEmit(true, false, false, true);
        emit CompositePredicate.CompositionSet(toolId, CompositePredicate.Op.ANY, terms);

        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ANY, terms);
    }

    function test_setComposition_revertsIfNotCreator() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);

        vm.expectRevert(abi.encodeWithSelector(CompositePredicate.CallerIsNotToolCreator.selector, toolId, stranger));
        vm.prank(stranger);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);
    }

    function test_setComposition_revertsIfTooManyTerms() public {
        uint256 max = predicate.MAX_TERMS_PER_COMPOSITION();
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](max + 1);
        for (uint256 i; i < terms.length; ++i) {
            terms[i] = _term(address(new MockAccessPredicate()), false);
        }

        vm.expectRevert(abi.encodeWithSelector(CompositePredicate.TooManyTerms.selector, max + 1, max));
        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);
    }

    function test_setComposition_maxTermsSucceeds() public {
        uint256 max = predicate.MAX_TERMS_PER_COMPOSITION();
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](max);
        for (uint256 i; i < max; ++i) {
            terms[i] = _term(address(new MockAccessPredicate()), false);
        }

        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);

        assertEq(predicate.getTerms(toolId).length, max);
    }

    function test_hasAccess_allOpEvaluatesAllMaxTerms() public {
        // Concrete proof that a fully-populated MAX_TERMS_PER_COMPOSITION
        // composition fits inside the registry's 200k-gas predicate budget:
        // every term is reached, each sub-staticcall succeeds, and the
        // ALL combiner returns true only when every leaf returns true.
        uint256 max = predicate.MAX_TERMS_PER_COMPOSITION();
        MockAccessPredicate[] memory leaves = new MockAccessPredicate[](max);
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](max);
        for (uint256 i; i < max; ++i) {
            leaves[i] = new MockAccessPredicate();
            leaves[i].setAllowed(holder, true);
            terms[i] = _term(address(leaves[i]), false);
        }

        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));

        // Flipping the last leaf to deny must flip the ALL result, proving
        // every term is consulted (not short-circuited prematurely).
        leaves[max - 1].setAllowed(holder, false);
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_setComposition_revertsOnZeroAddressTerm() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(0), false);

        vm.expectRevert(abi.encodeWithSelector(CompositePredicate.InvalidTerm.selector, 1, address(0)));
        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);
    }

    function test_setComposition_revertsOnSelfReference() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(predicate), false);

        vm.expectRevert(abi.encodeWithSelector(CompositePredicate.InvalidTerm.selector, 0, address(predicate)));
        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);
    }

    function test_setComposition_revertsOnEOATerm() public {
        address eoa = makeAddr("eoa");
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(eoa, false);

        vm.expectRevert(abi.encodeWithSelector(CompositePredicate.InvalidTerm.selector, 0, eoa));
        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);
    }

    function test_setComposition_revertsOnNonPredicateERC165() public {
        NonPredicateERC165 bad = new NonPredicateERC165();
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(bad), false);

        vm.expectRevert(abi.encodeWithSelector(CompositePredicate.InvalidAccessPredicate.selector, address(bad)));
        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);
    }

    function test_setComposition_acceptsNonERC165Predicate() public {
        // RevertingPredicate has no ERC-165 support; the registry-style probe
        // returns/reverts and the term is accepted at config time. The
        // term will fail closed at evaluation time.
        RevertingPredicate rp = new RevertingPredicate();
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(rp), false);

        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);

        assertEq(predicate.getTerms(toolId).length, 1);
    }

    // ── hasAccess: ALL operator ─────────────────────────────────────────

    function test_hasAccess_ALL_allTrue() public {
        leafA.setAllowed(holder, true);
        leafB.setAllowed(holder, true);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_ALL_oneFalseShortCircuits() public {
        leafA.setAllowed(holder, true);
        // leafB returns false for holder

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_ALL_singleTermTrue() public {
        leafA.setAllowed(holder, true);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_ALL_singleTermFalse() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    // ── hasAccess: ANY operator ─────────────────────────────────────────

    function test_hasAccess_ANY_oneTrueShortCircuits() public {
        // leafA denies; leafB allows.
        leafB.setAllowed(holder, true);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), false);
        _setOp(toolId, CompositePredicate.Op.ANY, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_ANY_allFalse() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), false);
        _setOp(toolId, CompositePredicate.Op.ANY, terms);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_ANY_singleTermTrue() public {
        leafA.setAllowed(holder, true);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ANY, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    // ── hasAccess: empty ────────────────────────────────────────────────

    function test_hasAccess_emptyTermsReturnsFalse_ALL() public view {
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_emptyTermsReturnsFalse_ANY() public {
        // Op defaults to ALL (zero), but we explicitly switch to ANY+empty too.
        _setOp(toolId, CompositePredicate.Op.ANY, new CompositePredicate.Term[](0));
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    // ── hasAccess: negate ───────────────────────────────────────────────

    function test_hasAccess_negate_invertsTermResult() public {
        // leafA denies holder; with negate=true the term reads as true.
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), true);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_negate_invertsAllowedToDenied() public {
        leafA.setAllowed(holder, true);
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), true);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_negate_appliedAfterFailClose() public {
        // RevertingPredicate fails closed (false) -> negate flips to true.
        RevertingPredicate rp = new RevertingPredicate();
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(rp), true);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_ANDNOT_pattern() public {
        // "owns A AND NOT owns B"
        leafA.setAllowed(holder, true);
        leafB.setAllowed(holder, false);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), true);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));

        // Now grant leafB too — the "NOT B" term flips false, so the AND fails.
        leafB.setAllowed(holder, true);
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    // ── hasAccess: failure modes ────────────────────────────────────────

    function test_hasAccess_revertingTermTreatedAsFalse_ALL() public {
        RevertingPredicate rp = new RevertingPredicate();
        leafA.setAllowed(holder, true);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(rp), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_revertingTermTreatedAsFalse_ANY() public {
        RevertingPredicate rp = new RevertingPredicate();
        leafA.setAllowed(holder, true);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(rp), false);
        terms[1] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ANY, terms);

        // The reverting term is false, but ANY short-circuits on the second
        // (allowing) term.
        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_gasBurnerTermTreatedAsFalse() public {
        GasBurnerPredicate gb = new GasBurnerPredicate();

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(gb), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_gasBurnerDoesNotExhaustOuterCall() public {
        GasBurnerPredicate gb = new GasBurnerPredicate();
        leafA.setAllowed(holder, true);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(gb), false);
        terms[1] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ANY, terms);

        // The 50k per-term cap means the outer call still has gas left to
        // evaluate the second term and short-circuit on it.
        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_malformedBoolTreatedAsFalse() public {
        MalformedBoolPredicate mb = new MalformedBoolPredicate();
        // No ERC-165 -> accepted at config time.
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(mb), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_perAccountIsolation() public {
        leafA.setAllowed(holder, true);
        // otherUser is not allowed.

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
        assertFalse(predicate.hasAccess(toolId, otherUser, ""));
    }

    function test_hasAccess_perToolIsolation() public {
        leafA.setAllowed(holder, true);
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        // Register a second tool with no composition set — it defaults to deny.
        vm.prank(creator);
        uint256 toolId2 = registry.registerTool(
            "https://api.opensea.io/.well-known/erc-draft/tools/composite-2.json",
            keccak256("manifest-v2"),
            address(predicate)
        );

        assertTrue(predicate.hasAccess(toolId, holder, ""));
        assertFalse(predicate.hasAccess(toolId2, holder, ""));
    }

    // ── name + version + supportsInterface ──────────────────────────────

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
        assertEq(predicate.name(), "CompositePredicate");
    }

    function test_version() public view {
        assertEq(predicate.version(), "0.2");
    }

    // ── registry immutable ──────────────────────────────────────────────

    function test_registry_isImmutable() public view {
        assertEq(address(predicate.REGISTRY()), address(registry));
    }

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert("CompositePredicate: zero registry");
        new CompositePredicate(address(0));
    }

    // ── getRequirements ──────────────────────────────────────────────────

    function test_getRequirements_emptyWhenNoTerms() public view {
        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 0);
        assertEq(uint256(logic), uint256(RequirementLogic.AND));
    }

    function test_getRequirements_flattensAllChildren() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        // MockAccessPredicate returns 0 requirements each
        assertEq(reqs.length, 0);
        assertEq(uint256(logic), uint256(RequirementLogic.AND));
    }

    function test_getRequirements_sentinelForRevertingChild() public {
        RevertingPredicate reverter = new RevertingPredicate();
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(reverter), false);
        terms[1] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ANY, terms);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        // Reverting child produces a sentinel; leafA returns 0 reqs.
        assertEq(reqs.length, 1);
        assertEq(reqs[0].kind, bytes4(0));
        assertEq(reqs[0].data, "");
        assertEq(keccak256(bytes(reqs[0].label)), keccak256(bytes("unknown")));
        assertEq(uint256(logic), uint256(RequirementLogic.OR));
    }

    function test_getRequirements_opAnyReturnsOR() public {
        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);
        _setOp(toolId, CompositePredicate.Op.ANY, terms);

        (, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(uint256(logic), uint256(RequirementLogic.OR));
    }

    function test_getRequirements_flattensNonEmptyChildren() public {
        MockRequirementsPredicate childA = new MockRequirementsPredicate();
        MockRequirementsPredicate childB = new MockRequirementsPredicate();

        // Configure childA with 1 requirement.
        AccessRequirement[] memory reqsA = new AccessRequirement[](1);
        reqsA[0] = AccessRequirement({kind: bytes4(0x11111111), data: hex"aa", label: "req-a"});
        childA.setRequirements(reqsA);

        // Configure childB with 2 requirements.
        AccessRequirement[] memory reqsB = new AccessRequirement[](2);
        reqsB[0] = AccessRequirement({kind: bytes4(0x22222222), data: hex"bb", label: "req-b1"});
        reqsB[1] = AccessRequirement({kind: bytes4(0x33333333), data: hex"cc", label: "req-b2"});
        childB.setRequirements(reqsB);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(childA), false);
        terms[1] = _term(address(childB), false);
        _setOp(toolId, CompositePredicate.Op.ALL, terms);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 3);
        assertEq(reqs[0].kind, bytes4(0x11111111));
        assertEq(keccak256(bytes(reqs[0].label)), keccak256(bytes("req-a")));
        assertEq(reqs[1].kind, bytes4(0x22222222));
        assertEq(keccak256(bytes(reqs[1].label)), keccak256(bytes("req-b1")));
        assertEq(reqs[2].kind, bytes4(0x33333333));
        assertEq(keccak256(bytes(reqs[2].label)), keccak256(bytes("req-b2")));
        assertEq(uint256(logic), uint256(RequirementLogic.AND));
    }

    function test_getRequirements_sentinelMixedWithRealRequirements() public {
        RevertingPredicate reverter = new RevertingPredicate();
        MockRequirementsPredicate childB = new MockRequirementsPredicate();

        // Configure childB with 1 requirement.
        AccessRequirement[] memory reqsB = new AccessRequirement[](1);
        reqsB[0] = AccessRequirement({kind: bytes4(0x44444444), data: hex"dd", label: "real-req"});
        childB.setRequirements(reqsB);

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(reverter), false);
        terms[1] = _term(address(childB), false);
        _setOp(toolId, CompositePredicate.Op.ANY, terms);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        // Sentinel from reverter + real requirement from childB.
        assertEq(reqs.length, 2);
        assertEq(reqs[0].kind, bytes4(0));
        assertEq(keccak256(bytes(reqs[0].label)), keccak256(bytes("unknown")));
        assertEq(reqs[1].kind, bytes4(0x44444444));
        assertEq(keccak256(bytes(reqs[1].label)), keccak256(bytes("real-req")));
        assertEq(uint256(logic), uint256(RequirementLogic.OR));
    }
}

contract CompositePredicateIntegrationTest is Test {
    ToolRegistry public registry;
    CompositePredicate public predicate;
    MockAccessPredicate public leafA;
    MockAccessPredicate public leafB;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");
    address nonHolder = makeAddr("nonHolder");

    string constant META_URI = "https://api.opensea.io/.well-known/erc-draft/tools/composite-int.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new CompositePredicate(address(registry));
        leafA = new MockAccessPredicate();
        leafB = new MockAccessPredicate();
    }

    function _term(address p, bool negate) internal pure returns (CompositePredicate.Term memory) {
        return CompositePredicate.Term({predicate: p, negate: negate});
    }

    function test_registry_hasAccess_grantedThroughComposite() public {
        leafA.setAllowed(holder, true);
        leafB.setAllowed(holder, true);

        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), false);

        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);

        assertTrue(registry.hasAccess(toolId, holder, ""));
    }

    function test_registry_hasAccess_deniedThroughComposite() public {
        // ALL with one denying leaf -> false.
        leafA.setAllowed(holder, true);

        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](2);
        terms[0] = _term(address(leafA), false);
        terms[1] = _term(address(leafB), false);

        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ALL, terms);

        assertFalse(registry.hasAccess(toolId, holder, ""));
        assertFalse(registry.hasAccess(toolId, nonHolder, ""));
    }

    function test_registry_tryHasAccess_returnsCorrectTuple() public {
        leafA.setAllowed(holder, true);

        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        CompositePredicate.Term[] memory terms = new CompositePredicate.Term[](1);
        terms[0] = _term(address(leafA), false);

        vm.prank(creator);
        predicate.setComposition(toolId, CompositePredicate.Op.ANY, terms);

        (bool ok, bool granted) = registry.tryHasAccess(toolId, holder, "");
        assertTrue(ok);
        assertTrue(granted);

        (bool ok2, bool granted2) = registry.tryHasAccess(toolId, nonHolder, "");
        assertTrue(ok2);
        assertFalse(granted2);
    }

    function test_registry_emptyCompositionDenies() public {
        vm.prank(creator);
        uint256 toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        // No setComposition call -> empty terms -> deny.
        (bool ok, bool granted) = registry.tryHasAccess(toolId, holder, "");
        assertTrue(ok);
        assertFalse(granted);
    }

    function test_crossCompositeCycle_failsClosed() public {
        // Two composites configured for the same `toolId`, each pointing at
        // the other. Because the composite forwards `toolId` unchanged on
        // every sub-staticcall, calling `predicate.hasAccess(toolId, ...)`
        // recurses: predicate -> other -> predicate -> other -> ...
        // The 50k per-term gas cap (further reduced by EIP-150's 63/64 rule
        // at each frame) starves the deepest call of gas; its staticcall
        // returns nothing, the caller treats the term as denied, and the
        // result bubbles back up. The whole pair must fail-closed — never
        // revert, never grant.
        CompositePredicate other = new CompositePredicate(address(registry));

        vm.prank(creator);
        uint256 cycleToolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));

        CompositePredicate.Term[] memory pointToOther = new CompositePredicate.Term[](1);
        pointToOther[0] = _term(address(other), false);

        CompositePredicate.Term[] memory pointToSelf = new CompositePredicate.Term[](1);
        pointToSelf[0] = _term(address(predicate), false);

        // setComposition only checks the registry's tool creator, so both
        // composites can be configured for the same `cycleToolId` even
        // though only `predicate` is the registry's recorded `accessPredicate`.
        vm.startPrank(creator);
        predicate.setComposition(cycleToolId, CompositePredicate.Op.ALL, pointToOther);
        other.setComposition(cycleToolId, CompositePredicate.Op.ALL, pointToSelf);
        vm.stopPrank();

        // Either composite's hasAccess returns false; neither reverts.
        assertFalse(predicate.hasAccess(cycleToolId, holder, ""));
        assertFalse(other.hasAccess(cycleToolId, holder, ""));

        // Through the registry, the call layer succeeds (`ok = true`) and
        // reports not-granted (`granted = false`).
        (bool ok, bool granted) = registry.tryHasAccess(cycleToolId, holder, "");
        assertTrue(ok);
        assertFalse(granted);
    }
}
