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
    function MAX_COLLECTIONS() external pure returns (uint256);

    event CollectionAdded(uint256 indexed toolId, address indexed collection, TokenStandard tokenStandard);
    event CollectionRemoved(uint256 indexed toolId, address indexed collection);

    error MaxCollectionsReached(uint256 toolId);
    error CollectionNotFound(uint256 toolId, uint256 index);
    error InvalidCollection(address collection);
    error NotToolCreator(uint256 toolId, address caller);

    function hasAccess(address user, uint256 toolId) external view returns (bool);
    function hasAccessWithProof(address user, uint256 toolId, uint256 tokenId) external view returns (bool);

    function addCollection(uint256 toolId, address collection, TokenStandard standard, uint256 tokenId) external;
    function removeCollection(uint256 toolId, uint256 index) external;
    function getCollections(uint256 toolId) external view returns (CollectionBinding[] memory);
}
