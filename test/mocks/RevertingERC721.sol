// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice An "ERC721" whose balanceOf and ownerOf always revert. Used to
///         verify that ToolAccessRegistry does not let a misbehaving bound
///         collection DoS the access check for other bindings.
contract RevertingERC721 {
    error AlwaysReverts();

    function balanceOf(address) external pure returns (uint256) {
        revert AlwaysReverts();
    }

    function ownerOf(uint256) external pure returns (address) {
        revert AlwaysReverts();
    }
}
