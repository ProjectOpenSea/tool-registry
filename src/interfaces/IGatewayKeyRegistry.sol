// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IGatewayKeyRegistry
/// @notice Registry of gateway signing keys for EIP-712 cross-chain attestations.
/// @dev ERC-165 interface ID computed from type(IGatewayKeyRegistry).interfaceId
interface IGatewayKeyRegistry {
    event GatewayKeyAdded(address indexed key);
    event GatewayKeyRemoved(address indexed key);

    error KeyAlreadyRegistered(address key);
    error KeyNotRegistered(address key);
    /// @notice The supplied key is invalid.
    /// @dev Implementations MUST revert with this error when the supplied key
    ///      is `address(0)`. Implementations MAY additionally reject keys that
    ///      fail implementation-specific validation.
    error InvalidKey();
    error Unauthorized();

    /// @notice Register a new gateway signing key. Admin only.
    /// @dev MUST revert with `InvalidKey` if `key` is `address(0)`. MUST revert
    ///      with `KeyAlreadyRegistered` if the key is already registered.
    function addGatewayKey(address key) external;
    function removeGatewayKey(address key) external;
    function isValidGatewayKey(address key) external view returns (bool);
}
