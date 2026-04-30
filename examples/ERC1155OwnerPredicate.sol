// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IAccessPredicate} from "../src/interfaces/IAccessPredicate.sol";
import {IToolRegistry} from "../src/interfaces/IToolRegistry.sol";

/// @title ERC1155OwnerPredicate
/// @notice IAccessPredicate that grants access to any account that owns ≥1
///         of any configured `(collection, tokenId)` pair across one or more
///         ERC-1155 collections. Entries are stored onchain so indexers can
///         discover which tokens gate which tools.
/// @dev Single-standard by design. Combine with `ERC721OwnerPredicate` (or
///      any other predicate) via a future `CompositePredicate` to express
///      AND/OR access policies across standards.
contract ERC1155OwnerPredicate is IAccessPredicate, ERC165 {
    /// @dev `hasAccess` issues one cross-contract `balanceOfBatch` call per
    ///      configured collection and is invoked under the registry's 200k
    ///      gas predicate budget. The per-tool / per-entry caps below are
    ///      sized so a maximally configured tool stays comfortably within
    ///      that budget.
    uint256 public constant MAX_COLLECTIONS_PER_TOOL = 10;
    uint256 public constant MAX_TOKEN_IDS_PER_COLLECTION = 16;

    /// @notice A collection address paired with the token IDs that gate access.
    struct CollectionTokens {
        address collection;
        uint256[] tokenIds;
    }

    IToolRegistry public immutable REGISTRY;

    mapping(uint256 toolId => CollectionTokens[]) private _entries;

    event CollectionTokensSet(uint256 indexed toolId, CollectionTokens[] entries);

    error CallerIsNotToolCreator(uint256 toolId, address caller);
    error TooManyCollections(uint256 count, uint256 max);
    error TooManyTokenIds(uint256 entryIndex, uint256 count, uint256 max);
    error EmptyTokenIds(uint256 entryIndex);
    error CollectionNoCode(address collection);

    constructor(address _registry) {
        require(_registry != address(0), "ERC1155OwnerPredicate: zero registry");
        REGISTRY = IToolRegistry(_registry);
    }

    /// @notice Set the (collection, tokenIds) entries that gate a tool.
    ///         Replaces any previous configuration.
    /// @dev Only the tool's creator (as recorded in the registry) may call this.
    function setCollectionTokens(uint256 toolId, CollectionTokens[] calldata entries) external {
        if (REGISTRY.getToolConfig(toolId).creator != msg.sender) {
            revert CallerIsNotToolCreator(toolId, msg.sender);
        }
        if (entries.length > MAX_COLLECTIONS_PER_TOOL) {
            revert TooManyCollections(entries.length, MAX_COLLECTIONS_PER_TOOL);
        }
        for (uint256 i; i < entries.length; ++i) {
            address collection = entries[i].collection;
            if (collection == address(0) || collection.code.length == 0) {
                revert CollectionNoCode(collection);
            }
            uint256 idsLen = entries[i].tokenIds.length;
            if (idsLen == 0) revert EmptyTokenIds(i);
            if (idsLen > MAX_TOKEN_IDS_PER_COLLECTION) {
                revert TooManyTokenIds(i, idsLen, MAX_TOKEN_IDS_PER_COLLECTION);
            }
        }

        // Solidity does not allow assigning a calldata struct array to a
        // storage struct array with a nested dynamic field, so rebuild the
        // storage array element-by-element.
        delete _entries[toolId];
        for (uint256 i; i < entries.length; ++i) {
            _entries[toolId].push(entries[i]);
        }

        emit CollectionTokensSet(toolId, entries);
    }

    /// @notice Returns the (collection, tokenIds) entries currently gating a tool.
    function getCollectionTokens(uint256 toolId) external view returns (CollectionTokens[] memory) {
        return _entries[toolId];
    }

    /// @notice Returns true if `account` owns ≥1 of any configured (collection, tokenId) pair.
    function hasAccess(uint256 toolId, address account, bytes calldata) external view override returns (bool) {
        CollectionTokens[] storage entries = _entries[toolId];
        uint256 entryCount = entries.length;
        if (entryCount == 0) return false;

        for (uint256 i; i < entryCount; ++i) {
            address collection = entries[i].collection;
            if (collection.code.length == 0) continue;

            uint256[] storage idsRef = entries[i].tokenIds;
            uint256 idsLen = idsRef.length;
            if (idsLen == 0) continue;

            address[] memory accounts = new address[](idsLen);
            uint256[] memory ids = new uint256[](idsLen);
            for (uint256 j; j < idsLen; ++j) {
                accounts[j] = account;
                ids[j] = idsRef[j];
            }

            try IERC1155(collection).balanceOfBatch(accounts, ids) returns (uint256[] memory balances) {
                for (uint256 j; j < balances.length; ++j) {
                    if (balances[j] > 0) return true;
                }
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
        return "ERC1155OwnerPredicate";
    }

    /// @notice Implementation version; same `MAJOR.MINOR` scheme as `ToolRegistry`.
    function version() external pure returns (string memory) {
        return "0.1";
    }
}
