// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice A single machine-readable access requirement.
/// @param kind  ERC-165-style 4-byte identifier for the requirement type.
///              Anyone defining a new predicate publishes a new
///              `IRequirementType` interface and uses its `interfaceId`.
/// @param data  ABI-encoded payload whose layout is determined by `kind`.
/// @param label Human-readable hint (e.g. "Chonks on Base").
struct AccessRequirement {
    bytes4 kind;
    bytes data;
    string label;
}

/// @notice Boolean logic combining multiple requirements.
enum RequirementLogic {
    AND,
    OR
}

/// @title IAccessPredicate
/// @notice Three-function interface for tool access gating.
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

    /// @notice Returns machine-readable access requirements for a tool so
    ///         agents can programmatically discover what it takes to pass.
    /// @dev The `kind` field uses ERC-165-style 4-byte IDs to keep the
    ///      namespace open. Known kinds include IERC721Holding, IERC1155Holding,
    ///      and ISubscription interface IDs.
    function getRequirements(uint256 toolId)
        external
        view
        returns (AccessRequirement[] memory requirements, RequirementLogic logic);
}
