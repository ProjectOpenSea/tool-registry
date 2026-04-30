// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IAccessPredicate
/// @notice Two-function interface for tool access gating.
/// @dev Predicates MAY implement ERC-165. Those that do MUST return true for
///      the IAccessPredicate interface ID. The registry uses ERC-165 as a
///      best-effort misconfiguration check but does not require predicates
///      to support it.
interface IAccessPredicate {
    function hasAccess(uint256 toolId, address account, bytes calldata data) external view returns (bool);

    /// @notice Returns a human-readable identifier for the predicate
    ///         implementation (e.g. `"ERC721OwnerPredicate"`).
    /// @dev MUST return a non-empty string. Format is implementation-defined;
    ///      consumers SHOULD treat the value as opaque except for equality
    ///      comparison. Useful for indexer / explorer display so consumers
    ///      can distinguish between predicate implementations without ABI
    ///      introspection.
    function name() external view returns (string memory);
}
