// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../../src/interfaces/IAccessPredicate.sol";

/// @dev Predicate that returns a configurable set of requirements.
///      Used in CompositePredicate tests to exercise the requirement
///      concatenation / copy loop with non-empty child requirements.
contract MockRequirementsPredicate is IAccessPredicate, ERC165 {
    AccessRequirement[] private _reqs;

    function setRequirements(AccessRequirement[] calldata reqs) external {
        delete _reqs;
        for (uint256 i; i < reqs.length; ++i) {
            _reqs.push(reqs[i]);
        }
    }

    function hasAccess(uint256, address, bytes calldata) external pure returns (bool) {
        return true;
    }

    function getRequirements(uint256)
        external
        view
        returns (AccessRequirement[] memory requirements, RequirementLogic logic)
    {
        requirements = _reqs;
        logic = RequirementLogic.AND;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAccessPredicate).interfaceId || super.supportsInterface(interfaceId);
    }

    function name() external pure returns (string memory) {
        return "MockRequirementsPredicate";
    }
}
