// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Predicate that only grants access when `data` decodes to uint256(42).
///      Intentionally omits ERC-165 support so the registry's best-effort
///      validation accepts it as a non-ERC-165 predicate.
contract DataCheckPredicate {
    function hasAccess(uint256, address, bytes calldata data) external pure returns (bool) {
        if (data.length != 32) return false;
        return abi.decode(data, (uint256)) == 42;
    }
}
