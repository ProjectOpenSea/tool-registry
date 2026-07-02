// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice A single machine-readable access requirement.
/// @param kind  ERC-165-style 4-byte identifier for the requirement type.
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
/// @dev Anyone can implement this to create custom access logic
///      (NFT gating, allowlists, staking requirements, subscriptions, etc.).
interface IAccessPredicate {
    /// @notice Check whether an account has access to a tool.
    /// @param toolId  The tool being accessed.
    /// @param account The account requesting access.
    /// @param data    Opaque context bytes (e.g., tokenId, proof, signature).
    /// @return Whether access is granted.
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
    ///      namespace open — anyone defining a new predicate publishes a new
    ///      marker interface and computes its 4-byte `interfaceId`. Known
    ///      kinds include `IERC721Holding`, `IERC1155Holding`, and
    ///      `ISubscription` interface IDs.
    /// @param toolId The tool to inspect.
    /// @return requirements Array of requirements the caller must satisfy.
    /// @return logic Whether requirements are combined with AND or OR.
    function getRequirements(uint256 toolId)
        external
        view
        returns (AccessRequirement[] memory requirements, RequirementLogic logic);
}
