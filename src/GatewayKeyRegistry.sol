// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IGatewayKeyRegistry} from "./interfaces/IGatewayKeyRegistry.sol";

/// @dev Uses `Ownable2Step` so admin transfers require the new admin to accept
///      before taking effect. A mistyped `transferOwnership` target cannot
///      silently brick the registry's trust anchor: the pending owner must
///      call `acceptOwnership` to complete the rotation.
contract GatewayKeyRegistry is IGatewayKeyRegistry, ERC165, Ownable2Step {
    /// @notice Signals an attempt to brick the registry by renouncing ownership.
    error OwnershipCannotBeRenounced();

    mapping(address => bool) private _validKeys;

    constructor(address admin) Ownable(admin) {}

    function addGatewayKey(address key) external onlyOwner {
        if (key == address(0)) revert InvalidKey();
        if (_validKeys[key]) revert KeyAlreadyRegistered(key);

        _validKeys[key] = true;
        emit GatewayKeyAdded(key);
    }

    function removeGatewayKey(address key) external onlyOwner {
        if (!_validKeys[key]) revert KeyNotRegistered(key);

        _validKeys[key] = false;
        emit GatewayKeyRemoved(key);
    }

    function isValidGatewayKey(address key) external view returns (bool) {
        return _validKeys[key];
    }

    /// @dev Overridden to revert. Renouncing ownership would strand the key
    ///      registry: no one could add or remove gateway keys, and every
    ///      cross-chain attestation would remain verifiable only until
    ///      `STALENESS_WINDOW` seconds after any compromised key's last
    ///      legitimate use. Transfer ownership instead.
    function renounceOwnership() public view override onlyOwner {
        revert OwnershipCannotBeRenounced();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IGatewayKeyRegistry).interfaceId || super.supportsInterface(interfaceId);
    }
}
