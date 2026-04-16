// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Token standard for collection bindings.
enum TokenStandard {
    ERC721,
    ERC1155
}

/// @notice Binding between a tool and an NFT collection that grants access.
struct CollectionBinding {
    address collection;
    TokenStandard tokenStandard;
    uint256 tokenId;
    bool active;
}

/// @title IToolAccessRegistry
/// @notice NFT-based access gating for tools with payment-only passthrough.
/// @dev ERC-165 interface ID computed from type(IToolAccessRegistry).interfaceId
interface IToolAccessRegistry {
    /// @notice Maximum number of collection bindings per tool.
    /// @dev Implementations MUST enforce this as a hard cap in `addCollection`.
    ///      The returned value MUST be >= 1 and SHOULD NOT exceed 100 to bound
    ///      `hasAccess` gas. Conforming implementations SHOULD return 20.
    function MAX_COLLECTIONS() external view returns (uint256);

    event CollectionAdded(uint256 indexed toolId, address indexed collection, TokenStandard tokenStandard);
    event CollectionRemoved(uint256 indexed toolId, address indexed collection);

    error MaxCollectionsReached(uint256 toolId);
    error CollectionNotFound(uint256 toolId, uint256 index);
    error InvalidCollection(address collection);
    error NotToolCreator(uint256 toolId, address caller);
    error UnsupportedStandardForSubscription(uint256 toolId, TokenStandard standard);

    /// @dev Argument order matches `IToolRegistry.hasAccess` so a single
    ///      contract MAY implement both interfaces with one function body.
    function hasAccess(uint256 toolId, address account) external view returns (bool);
    function hasAccessWithProof(uint256 toolId, address account, uint256 tokenId) external view returns (bool);

    /// @notice Bind an NFT collection to a tool. Tool creator only.
    /// @dev MUST revert with `UnsupportedStandardForSubscription` if `standard`
    ///      is `ERC1155` and the tool's `accessMode` is `SUBSCRIPTION`; per-token
    ///      expiry semantics for ERC-1155 are not defined by ERC-5643.
    function addCollection(uint256 toolId, address collection, TokenStandard standard, uint256 tokenId) external;
    function removeCollection(uint256 toolId, uint256 index) external;
    function getCollections(uint256 toolId) external view returns (CollectionBinding[] memory);
}
