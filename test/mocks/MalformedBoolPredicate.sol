// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Predicate-shaped contract whose `hasAccess` returns a 32-byte word
///      that is neither 0 nor 1 (`uint256(2)`). Shares the selector of a
///      canonical `hasAccess(uint256,address,bytes)` so the registry invokes
///      it, but the returned word is not a canonical ABI-encoded bool and
///      MUST be treated by the registry as a malfunction.
contract MalformedBoolPredicate {
    function hasAccess(uint256, address, bytes calldata) external pure returns (uint256) {
        return 2;
    }
}
