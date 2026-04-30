// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IAccessPredicate} from "../src/interfaces/IAccessPredicate.sol";
import {IToolRegistry} from "../src/interfaces/IToolRegistry.sol";

/// @title CompositePredicate
/// @notice IAccessPredicate that combines up to `MAX_TERMS_PER_COMPOSITION`
///         leaf `IAccessPredicate` contracts under a single boolean operator
///         (AND-all or OR-any) with optional per-term negation, so a tool can
///         express access rules like "owns 721 X **OR** holds active
///         subscription Y" or "owns 721 X **AND NOT** owns 1155 Z" without
///         writing a bespoke predicate.
/// @dev Each tool's composition is `(op, terms[])`. Setting an empty `terms`
///      array clears the gate (`hasAccess` returns `false`). Term evaluation
///      `staticcall`s each leaf with a 50k gas budget; failures, reverts, and
///      non-canonical bool returns are treated as `false` (fail-closed) before
///      `negate` is applied.
///
///      The registry forwards exactly 200k gas to a predicate's `hasAccess`,
///      so per-term budget and term count are coupled. `MAX_TERMS_PER_COMPOSITION`
///      is capped at 3 so that 3 sub-staticcalls under `_PER_TERM_GAS_LIMIT`
///      (50k each = 150k) plus iteration, returndata decoding, and short-circuit
///      bookkeeping fit comfortably within the registry's 200k forwarded budget,
///      with enough headroom for leaf predicates that themselves make
///      cross-contract calls (e.g. `ERC721OwnerPredicate` looping
///      `balanceOf` over multiple cold collections). Compositions of more than
///      three terms are deliberately out of scope for this example — express
///      them by nesting another `CompositePredicate` as a leaf, or by writing
///      a bespoke predicate.
///
///      The same `data` is forwarded to every term — per-term `data` routing
///      is out of scope for this example. Self-reference is rejected at
///      configuration time to keep evaluation bounded; cycles via other
///      composite predicates are still possible but require deliberate setup.
contract CompositePredicate is IAccessPredicate, ERC165 {
    /// @notice Boolean operator that combines the per-term results.
    enum Op {
        ALL, // AND-all: every term (after `negate`) must be `true`
        ANY // OR-any:  at least one term (after `negate`) must be `true`
    }

    /// @notice A single leaf predicate plus an optional negation flag.
    /// @param predicate The leaf `IAccessPredicate` contract to call.
    /// @param negate    When `true`, the term's result is inverted before being
    ///                  combined under `op`.
    struct Term {
        address predicate;
        bool negate;
    }

    /// @notice Maximum number of terms per composition.
    /// @dev Sized so that `MAX_TERMS_PER_COMPOSITION` sub-staticcalls under
    ///      `_PER_TERM_GAS_LIMIT` fit within the registry's 200k forwarded gas
    ///      budget for `hasAccess`, with enough per-term headroom for leaf
    ///      predicates that themselves make cross-contract calls.
    uint256 public constant MAX_TERMS_PER_COMPOSITION = 3;

    /// @dev Gas forwarded to each term's `hasAccess` staticcall. Sized to
    ///      cover leaf predicates that loop `balanceOf` / `balanceOfBatch`
    ///      over a handful of cold collections (e.g. `ERC721OwnerPredicate`
    ///      with several configured collections, or `ERC1155OwnerPredicate`
    ///      with multiple token IDs). With at most three terms, 50k each
    ///      keeps total forwarded sub-call gas at 150k, leaving 50k of
    ///      headroom for term iteration, returndata decoding, and bookkeeping
    ///      under the registry's forwarded budget.
    uint256 private constant _PER_TERM_GAS_LIMIT = 50_000;

    /// @dev Gas forwarded to each `supportsInterface` probe during
    ///      configuration-time ERC-165 validation. Matches the ERC-165
    ///      ceiling and the registry's own validation cap.
    uint256 private constant _ERC165_VALIDATION_GAS_LIMIT = 30_000;

    /// @notice The ToolRegistry used to verify tool creator identity.
    IToolRegistry public immutable REGISTRY;

    mapping(uint256 toolId => Op) private _ops;
    mapping(uint256 toolId => Term[]) private _terms;

    event CompositionSet(uint256 indexed toolId, Op op, Term[] terms);

    error CallerIsNotToolCreator(uint256 toolId, address caller);
    error TooManyTerms(uint256 count, uint256 max);
    /// @notice The term at `index` failed structural validation (zero address,
    ///         self-reference, or no deployed code).
    error InvalidTerm(uint256 index, address predicate);
    /// @notice The term's contract claims ERC-165 support but does not report
    ///         `IAccessPredicate.interfaceId`, mirroring `IToolRegistry`'s
    ///         `InvalidAccessPredicate` semantics.
    error InvalidAccessPredicate(address predicate);

    constructor(address _registry) {
        require(_registry != address(0), "CompositePredicate: zero registry");
        REGISTRY = IToolRegistry(_registry);
    }

    /// @notice Set the boolean operator and term list for a tool. Replaces
    ///         any previous configuration atomically.
    /// @dev Only the tool's creator (as recorded in the registry) may call
    ///      this. Passing an empty `terms` array clears the gate (treated as
    ///      deny-all by `hasAccess`).
    /// @param toolId The tool to configure.
    /// @param op     `Op.ALL` for AND-all, `Op.ANY` for OR-any.
    /// @param terms  The leaf predicates to combine. Length capped at
    ///               `MAX_TERMS_PER_COMPOSITION`.
    function setComposition(uint256 toolId, Op op, Term[] calldata terms) external {
        if (REGISTRY.getToolConfig(toolId).creator != msg.sender) {
            revert CallerIsNotToolCreator(toolId, msg.sender);
        }
        if (terms.length > MAX_TERMS_PER_COMPOSITION) {
            revert TooManyTerms(terms.length, MAX_TERMS_PER_COMPOSITION);
        }

        for (uint256 i; i < terms.length; ++i) {
            address predicate = terms[i].predicate;
            if (predicate == address(0) || predicate == address(this) || predicate.code.length == 0) {
                revert InvalidTerm(i, predicate);
            }
            _validateTermErc165(predicate);
        }

        _ops[toolId] = op;
        delete _terms[toolId];
        for (uint256 i; i < terms.length; ++i) {
            _terms[toolId].push(terms[i]);
        }

        emit CompositionSet(toolId, op, terms);
    }

    /// @notice Read the operator currently configured for a tool.
    /// @dev Defaults to `Op.ALL` for tools that have no composition set; the
    ///      empty term list is what `hasAccess` interprets as deny-all, so the
    ///      operator default is informational only.
    function getOp(uint256 toolId) external view returns (Op) {
        return _ops[toolId];
    }

    /// @notice Read the term list currently configured for a tool.
    function getTerms(uint256 toolId) external view returns (Term[] memory) {
        return _terms[toolId];
    }

    /// @notice Returns `true` when the configured `(op, terms)` combination
    ///         evaluates to true for `account`. An empty term list returns
    ///         `false`. The same `data` is forwarded to every term.
    /// @dev Each term is `staticcall`ed with `_PER_TERM_GAS_LIMIT` gas and a
    ///      strict ABI-bool decode (32-byte word, value 0 or 1). On any
    ///      failure — call revert, out-of-gas, oversize / undersize
    ///      returndata, or non-canonical bool — the term result is treated
    ///      as `false` before `negate` is applied. Short-circuits on the
    ///      first decisive result.
    function hasAccess(uint256 toolId, address account, bytes calldata data) external view override returns (bool) {
        Term[] storage terms = _terms[toolId];
        uint256 len = terms.length;
        if (len == 0) return false;

        Op op = _ops[toolId];
        bytes memory payload = abi.encodeCall(IAccessPredicate.hasAccess, (toolId, account, data));

        for (uint256 i; i < len; ++i) {
            Term storage term = terms[i];
            bool termResult = _evaluateTerm(term.predicate, payload);
            if (term.negate) termResult = !termResult;

            if (op == Op.ANY) {
                if (termResult) return true;
            } else {
                if (!termResult) return false;
            }
        }

        // ALL: every term passed without early exit -> true.
        // ANY: no term passed -> false.
        return op == Op.ALL;
    }

    /// @dev Performs one bounded staticcall to `predicate` with `payload` and
    ///      decodes the strict ABI-bool result. Mirrors the registry's own
    ///      decode: any non-canonical shape (call failure, returndata not
    ///      exactly 32 bytes, or a word that is neither 0 nor 1) yields
    ///      `false`.
    function _evaluateTerm(address predicate, bytes memory payload) internal view returns (bool) {
        if (predicate.code.length == 0) return false;

        uint256 gasBudget = _PER_TERM_GAS_LIMIT;
        bool callOk;
        uint256 retSize;
        bytes32 word;
        assembly ("memory-safe") {
            callOk := staticcall(gasBudget, predicate, add(payload, 0x20), mload(payload), 0x00, 0x20)
            retSize := returndatasize()
            word := mload(0x00)
        }
        if (!callOk || retSize != 32) return false;
        if (word == bytes32(uint256(1))) return true;
        return false;
    }

    /// @dev Best-effort ERC-165 check mirroring `ToolRegistry._validatePredicate`:
    ///      reverts only when the term's contract claims ERC-165 support but
    ///      reports `false` (or reverts) for `IAccessPredicate.interfaceId`.
    ///      Contracts that do not declare ERC-165 are accepted, matching the
    ///      registry's permissiveness.
    function _validateTermErc165(address predicate) internal view {
        try IERC165(predicate).supportsInterface{gas: _ERC165_VALIDATION_GAS_LIMIT}(type(IERC165).interfaceId) returns (
            bool erc165Supported
        ) {
            if (!erc165Supported) return;
        } catch {
            return;
        }

        try IERC165(predicate).supportsInterface{gas: _ERC165_VALIDATION_GAS_LIMIT}(
            type(IAccessPredicate).interfaceId
        ) returns (bool supported) {
            if (!supported) revert InvalidAccessPredicate(predicate);
        } catch {
            revert InvalidAccessPredicate(predicate);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAccessPredicate).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IAccessPredicate
    function name() external pure returns (string memory) {
        return "CompositePredicate";
    }

    /// @notice Implementation version; same `MAJOR.MINOR` scheme as `ToolRegistry`.
    function version() external pure returns (string memory) {
        return "0.1";
    }
}
