// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseCreate2Script} from "create2-helpers/src/BaseCreate2Script.sol";
import {console2} from "forge-std/console2.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";
import {ERC721OwnerPredicate} from "../examples/ERC721OwnerPredicate.sol";
import {ERC1155OwnerPredicate} from "../examples/ERC1155OwnerPredicate.sol";

/// @title Deploy
/// @notice Deterministic CREATE2 deployment of `ToolRegistry` and the example
///         `ERC721OwnerPredicate` / `ERC1155OwnerPredicate` predicates via the
///         Arachnid keyless factory.
/// @dev Deploys are idempotent: re-running with the same salt is a no-op once
///      the address is occupied. Swap `_SALT` for a vanity salt later and
///      re-run — the script will deploy at the new address on chains that
///      have not yet seen it without disturbing existing deployments.
///
///      Pre-release policy: the script always deploys whatever bytecode the
///      current source produces. If the registry source (or any of its
///      imports) changes, the resulting CREATE2 address moves and a new
///      registry is deployed; existing tools at the old registry are left in
///      place but no longer canonical. Stabilise the registry address via a
///      pinned constant once we cut a 1.0 release.
contract Deploy is BaseCreate2Script {
    /// @dev Beta placeholder. Replace with a mined vanity salt before the
    ///      canonical multi-chain rollout — `_create2IfNotDeployed` will
    ///      deploy the new address wherever it doesn't exist yet.
    bytes32 private constant _SALT = bytes32(uint256(1));

    function run() public {
        runOnNetworks(deploy, vm.envString("NETWORKS", ","));
    }

    function deploy() public returns (address registryAddr) {
        registryAddr = _create2IfNotDeployed(deployer, _SALT, type(ToolRegistry).creationCode);
        console2.log("ToolRegistry:           ", registryAddr);

        bytes memory predicate721InitCode =
            abi.encodePacked(type(ERC721OwnerPredicate).creationCode, abi.encode(registryAddr));
        address predicate721 = _create2IfNotDeployed(deployer, _SALT, predicate721InitCode);
        console2.log("ERC721OwnerPredicate:   ", predicate721);

        bytes memory predicate1155InitCode =
            abi.encodePacked(type(ERC1155OwnerPredicate).creationCode, abi.encode(registryAddr));
        address predicate1155 = _create2IfNotDeployed(deployer, _SALT, predicate1155InitCode);
        console2.log("ERC1155OwnerPredicate:  ", predicate1155);
    }
}
