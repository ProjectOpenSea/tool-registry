// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseCreate2Script} from "create2-helpers/src/BaseCreate2Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20BalancePredicate} from "../examples/ERC20BalancePredicate.sol";

/// @title DeployERC20BalancePredicate
/// @notice Standalone deterministic CREATE2 deployment of `ERC20BalancePredicate`
///         against an existing `ToolRegistry`. Use this to deploy the predicate
///         without redeploying the registry or other predicates.
/// @dev Requires REGISTRY env var pointing to the deployed ToolRegistry address.
///      Idempotent: re-running with the same salt is a no-op once the address
///      is occupied.
contract DeployERC20BalancePredicate is BaseCreate2Script {
    bytes32 private constant _SALT = bytes32(uint256(1));

    function run() public {
        runOnNetworks(deploy, vm.envString("NETWORKS", ","));
    }

    function deploy() public returns (address predicateAddr) {
        address registry = vm.envAddress("REGISTRY");
        console2.log("Using ToolRegistry:       ", registry);

        bytes memory initCode = abi.encodePacked(type(ERC20BalancePredicate).creationCode, abi.encode(registry));
        predicateAddr = _create2IfNotDeployed(deployer, _SALT, initCode);
        console2.log("ERC20BalancePredicate:    ", predicateAddr);
    }
}
