// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IAccessPredicate} from "../../src/interfaces/IAccessPredicate.sol";

contract MockAccessPredicate is IAccessPredicate, ERC165 {
    mapping(address => bool) private _allowed;

    function setAllowed(address account, bool allowed) external {
        _allowed[account] = allowed;
    }

    function hasAccess(uint256, address account, bytes calldata) external view returns (bool) {
        return _allowed[account];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAccessPredicate).interfaceId || super.supportsInterface(interfaceId);
    }

    function name() external pure returns (string memory) {
        return "MockAccessPredicate";
    }
}
