// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../../src/interfaces/IAccessPredicate.sol";

/// @dev Predicate that unconditionally denies access. Used in tests to
///      exercise the spec's "pause a tool by pointing accessPredicate at an
///      always-deny predicate" pattern, which replaces the removed `active`
///      flag.
contract DenyAllPredicate is IAccessPredicate, ERC165 {
    function hasAccess(uint256, address, bytes calldata) external pure returns (bool) {
        return false;
    }

    function getRequirements(uint256)
        external
        pure
        returns (AccessRequirement[] memory requirements, RequirementLogic logic)
    {
        requirements = new AccessRequirement[](0);
        logic = RequirementLogic.AND;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAccessPredicate).interfaceId || super.supportsInterface(interfaceId);
    }

    function name() external pure returns (string memory) {
        return "DenyAllPredicate";
    }
}
