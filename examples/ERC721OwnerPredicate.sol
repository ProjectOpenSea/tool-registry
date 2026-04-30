// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAccessPredicate} from "../src/interfaces/IAccessPredicate.sol";
import {IToolRegistry} from "../src/interfaces/IToolRegistry.sol";

/// @title ERC721OwnerPredicate
/// @notice IAccessPredicate that grants access to any account that owns ≥1
///         token (`balanceOf > 0`) in any of the ERC-721 collections
///         configured for a given tool. Collections are stored onchain so
///         indexers can discover which NFTs gate which tools.
/// @dev Single-standard by design. Combine with `ERC1155OwnerPredicate` (or
///      any other predicate) via a future `CompositePredicate` to express
///      AND/OR access policies across standards.
contract ERC721OwnerPredicate is IAccessPredicate, ERC165 {
    uint256 public constant MAX_COLLECTIONS_PER_TOOL = 10;

    IToolRegistry public immutable REGISTRY;

    mapping(uint256 => address[]) private _collections;

    event CollectionsSet(uint256 indexed toolId, address[] collections);

    error CallerIsNotToolCreator(uint256 toolId, address caller);
    error TooManyCollections(uint256 count, uint256 max);
    error CollectionNoCode(address collection);

    constructor(address _registry) {
        require(_registry != address(0), "ERC721OwnerPredicate: zero registry");
        REGISTRY = IToolRegistry(_registry);
    }

    /// @notice Set the collections that gate a tool. Replaces any previous list.
    /// @dev Only the tool's creator (as recorded in the registry) may call this.
    function setCollections(uint256 toolId, address[] calldata collections) external {
        if (REGISTRY.getToolConfig(toolId).creator != msg.sender) {
            revert CallerIsNotToolCreator(toolId, msg.sender);
        }
        if (collections.length > MAX_COLLECTIONS_PER_TOOL) {
            revert TooManyCollections(collections.length, MAX_COLLECTIONS_PER_TOOL);
        }
        for (uint256 i; i < collections.length; ++i) {
            if (collections[i] == address(0) || collections[i].code.length == 0) {
                revert CollectionNoCode(collections[i]);
            }
        }
        _collections[toolId] = collections;
        emit CollectionsSet(toolId, collections);
    }

    /// @notice Returns the collections currently gating a tool.
    function getCollections(uint256 toolId) external view returns (address[] memory) {
        return _collections[toolId];
    }

    /// @notice Returns true if `account` holds ≥1 NFT in any configured collection.
    function hasAccess(uint256 toolId, address account, bytes calldata) external view override returns (bool) {
        address[] storage collections = _collections[toolId];
        uint256 len = collections.length;
        if (len == 0) return false;

        for (uint256 i; i < len; ++i) {
            address collection = collections[i];
            if (collection.code.length == 0) continue;
            try IERC721(collection).balanceOf(account) returns (uint256 balance) {
                if (balance > 0) return true;
            } catch {
                continue;
            }
        }
        return false;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAccessPredicate).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IAccessPredicate
    function name() external pure returns (string memory) {
        return "ERC721OwnerPredicate";
    }

    /// @notice Implementation version; same `MAJOR.MINOR` scheme as `ToolRegistry`.
    function version() external pure returns (string memory) {
        return "0.1";
    }
}
