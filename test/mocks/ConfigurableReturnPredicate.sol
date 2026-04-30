// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Predicate-shaped contract that returns a caller-configured 32-byte
///      word. Used by fuzz tests to exercise the full range of values the
///      registry's strict bool decode must reject.
contract ConfigurableReturnPredicate {
    uint256 private immutable _VALUE;

    constructor(uint256 value) {
        _VALUE = value;
    }

    function hasAccess(uint256, address, bytes calldata) external view returns (uint256) {
        return _VALUE;
    }
}
