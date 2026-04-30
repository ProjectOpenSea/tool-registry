// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Contract that supports ERC-165 but NOT IAccessPredicate. The
///      registry's second supportsInterface probe returns `false`, so
///      registration / predicate update MUST revert `InvalidAccessPredicate`.
contract NonPredicateERC165 {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7; // ERC-165 only
    }
}
