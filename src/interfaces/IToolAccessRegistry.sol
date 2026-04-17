// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Token standard for collection bindings.
enum TokenStandard {
    ERC721,
    ERC1155
}

/// @notice Binding between a tool and an NFT collection that grants access.
/// @dev `tokenId` MUST be zero when `tokenStandard == ERC721`. ERC-721 bindings
///      use `balanceOf(account)`; a non-zero tokenId would be dead state and
///      is rejected by `addCollection`.
struct CollectionBinding {
    address collection;
    TokenStandard tokenStandard;
    uint256 tokenId;
}

/// @title IToolAccessRegistry
/// @notice NFT-based access gating for tools with payment-only passthrough.
/// @dev ERC-165 interface ID computed from type(IToolAccessRegistry).interfaceId
interface IToolAccessRegistry {
    /// @notice Maximum number of collection bindings per tool.
    /// @dev Implementations MUST return exactly `20`. Pinned by the standard so
    ///      interoperating contracts and indexers can assume a bounded iteration
    ///      cost for `hasAccess` (which performs an external call per binding)
    ///      and `getCollections`. Implementations MUST revert `addCollection`
    ///      with `MaxCollectionsReached` once 20 bindings exist for a tool.
    function MAX_COLLECTIONS() external view returns (uint256);

    event CollectionAdded(uint256 indexed toolId, address indexed collection, TokenStandard tokenStandard);
    event CollectionRemoved(uint256 indexed toolId, address indexed collection);

    error MaxCollectionsReached(uint256 toolId);
    error CollectionNotFound(uint256 toolId, uint256 index);
    /// @notice The binding at `index` did not match the caller's expected collection.
    /// @dev Raised by `removeCollection` when the caller's `expectedCollection`
    ///      does not match the binding at `index` at the time the call lands.
    ///      Protects against races where concurrent removals shift indices.
    error CollectionMismatch(uint256 toolId, uint256 index, address expected, address actual);
    error InvalidCollection(address collection);
    error NotToolCreator(uint256 toolId, address caller);
    error UnsupportedStandardForSubscription(uint256 toolId, TokenStandard standard);

    /// @dev If the tool is not `active`, MUST return `false`.
    ///      For OPEN tools, MUST return `true` when active. For NFT_GATED
    ///      tools, returns `true` if `account` holds a token from ANY bound
    ///      collection. For SUBSCRIPTION tools, MUST return `false`
    ///      unconditionally: `balanceOf` cannot disambiguate which `tokenId`
    ///      to check `expiresAt` on; callers MUST use `hasAccessWithProof`.
    ///      Prevents a silent security failure where expired subs would pass
    ///      a `balanceOf`-only check.
    ///      Argument order matches `IToolRegistry.hasAccess` so a single
    ///      contract MAY implement both interfaces with one function body.
    function hasAccess(uint256 toolId, address account) external view returns (bool);

    /// @notice Check access using a caller-supplied tokenId for SUBSCRIPTION expiry.
    /// @dev The only valid access check for SUBSCRIPTION tools. If the tool is
    ///      not `active`, MUST return `false`. For SUBSCRIPTION, MUST verify:
    ///      (a) `account` owns `tokenId` in a bound collection, AND
    ///      (b) `IERC5643(collection).expiresAt(tokenId) > block.timestamp`.
    ///      For NFT_GATED, `tokenId` is ignored and behavior matches `hasAccess`.
    function hasAccessWithProof(uint256 toolId, address account, uint256 tokenId) external view returns (bool);

    /// @notice Bind an NFT collection to a tool. Tool creator only.
    /// @dev MUST revert with `UnsupportedStandardForSubscription` if `standard`
    ///      is `ERC1155` and the tool's `accessMode` is `SUBSCRIPTION`; per-token
    ///      expiry semantics for ERC-1155 are not defined by ERC-5643.
    ///      MUST revert with `InvalidCollection` if `standard` is `ERC721` and
    ///      `tokenId != 0`, since ERC-721 bindings use `balanceOf(account)` and
    ///      a nonzero tokenId would be silently ignored state.
    function addCollection(uint256 toolId, address collection, TokenStandard standard, uint256 tokenId) external;

    /// @notice Remove a collection binding by index. Tool creator only.
    /// @dev Implementations MUST revert with `CollectionMismatch` if the
    ///      binding at `index` does not have `collection == expectedCollection`
    ///      at the time the call lands. This is a compare-and-swap guard
    ///      against index races where concurrent removals shift the array.
    ///      Callers SHOULD re-fetch `getCollections` and retry on mismatch.
    function removeCollection(uint256 toolId, uint256 index, address expectedCollection) external;

    function getCollections(uint256 toolId) external view returns (CollectionBinding[] memory);
}
