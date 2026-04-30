// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Predicate-shaped contract whose `hasAccess` returns two 32-byte
///      words (64 bytes) with the first word encoding canonical `true`.
///      Exercises the registry's strict `returndatasize == 32` check, which
///      MUST reject oversize returns even when the first word would
///      otherwise decode as `true`.
contract OversizeReturnPredicate {
    function hasAccess(uint256, address, bytes calldata) external pure returns (uint256, uint256) {
        return (1, 0);
    }
}
