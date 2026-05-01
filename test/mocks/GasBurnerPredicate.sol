// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../../src/interfaces/IAccessPredicate.sol";

/// @dev Predicate whose `hasAccess` deliberately burns every unit of gas it
///      is forwarded. Used to pin the registry's `_PREDICATE_GAS_LIMIT`:
///      without the cap, the staticcall would forward ~63/64 of the
///      registry caller's remaining gas (per EIP-150) and consume all of
///      it, leaving the outer `hasAccess` call with only ~1/64 of gas.
///      With the cap in force the outer call stays cheap and fails closed.
contract GasBurnerPredicate is IAccessPredicate, ERC165 {
    function hasAccess(uint256, address, bytes calldata) external view returns (bool) {
        // Unbounded loop: consume all forwarded gas. The `gasleft()` read
        // suppresses the optimizer-removable pure-view analysis on the
        // counter. The loop never exits on its own; it exits when the EVM
        // halts execution with out-of-gas.
        uint256 i;
        while (true) {
            unchecked {
                i += gasleft();
            }
        }
        return i == 0;
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
        return "GasBurnerPredicate";
    }
}
