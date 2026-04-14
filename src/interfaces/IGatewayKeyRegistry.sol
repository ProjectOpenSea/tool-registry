// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IGatewayKeyRegistry
/// @notice Registry of gateway signing keys for EIP-712 invocation token verification.
/// @dev ERC-165 interface ID computed from type(IGatewayKeyRegistry).interfaceId
interface IGatewayKeyRegistry {
    event GatewayKeyAdded(address indexed key);
    event GatewayKeyRemoved(address indexed key);

    error KeyAlreadyRegistered(address key);
    error KeyNotRegistered(address key);
    error InvalidKey();
    error Unauthorized();

    function addGatewayKey(address key) external;
    function removeGatewayKey(address key) external;
    function isValidGatewayKey(address key) external view returns (bool);
}
