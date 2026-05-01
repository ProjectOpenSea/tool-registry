// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IRequirementTypes
/// @notice Marker interfaces whose `interfaceId` values serve as the `kind`
///         field in `AccessRequirement`. Each defines the ABI-encoded layout
///         of the `data` payload.

/// @dev kind for ERC-721 holding requirements.
///      data = abi.encode(address collection)
interface IERC721Holding {
    function erc721Holding() external;
}

/// @dev kind for ERC-1155 holding requirements.
///      data = abi.encode(address collection, uint256 tokenId)
interface IERC1155Holding {
    function erc1155Holding() external;
}

/// @dev kind for subscription requirements.
///      data = abi.encode(address collection, uint8 minTier)
interface ISubscription {
    function subscription() external;
}
