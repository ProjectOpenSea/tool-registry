// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Contract that claims ERC-165 support but reverts when queried for
///      any other interface ID. Non-conformant per ERC-165 (which requires
///      `supportsInterface` to answer without reverting for conformant
///      contracts); the registry MUST treat it as an invalid predicate.
contract RevertingERC165 {
    error NotImplemented();

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        if (interfaceId == 0x01ffc9a7) return true;
        revert NotImplemented();
    }
}
