// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice An "ERC1155" whose balanceOf always reverts. Used to verify that
///         ToolAccessRegistry does not let a misbehaving bound collection DoS
///         the access check for other bindings.
contract RevertingERC1155 {
    error AlwaysReverts();

    function balanceOf(address, uint256) external pure returns (uint256) {
        revert AlwaysReverts();
    }
}
