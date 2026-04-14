// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGatewayKeyRegistry} from "./interfaces/IGatewayKeyRegistry.sol";

contract GatewayKeyRegistry is IGatewayKeyRegistry, ERC165, Ownable {
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

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IGatewayKeyRegistry).interfaceId || super.supportsInterface(interfaceId);
    }
}
