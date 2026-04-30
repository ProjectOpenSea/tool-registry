// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

contract RevertingPredicate {
    error AlwaysReverts();

    function hasAccess(uint256, address, bytes calldata) external pure returns (bool) {
        revert AlwaysReverts();
    }
}
