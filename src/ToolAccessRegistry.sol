// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IToolAccessRegistry, CollectionBinding, TokenStandard} from "./interfaces/IToolAccessRegistry.sol";
import {IToolRegistry, ToolConfig, AccessMode} from "./interfaces/IToolRegistry.sol";

/// @notice Minimal ERC-5643 interface for subscription expiration checks.
interface IERC5643 {
    function expiresAt(uint256 tokenId) external view returns (uint64);
}

contract ToolAccessRegistry is IToolAccessRegistry, ERC165 {
    uint256 public constant MAX_COLLECTIONS_VALUE = 20;
    IToolRegistry public immutable toolRegistry;

    mapping(uint256 => CollectionBinding[]) private _bindings;
    mapping(uint256 => uint256) private _activeCount;

    constructor(address _toolRegistry) {
        toolRegistry = IToolRegistry(_toolRegistry);
    }

    function MAX_COLLECTIONS() external pure returns (uint256) {
        return MAX_COLLECTIONS_VALUE;
    }

    function hasAccess(address user, uint256 toolId) external view returns (bool) {
        return _checkAccess(user, toolId, 0, false);
    }

    /// @notice Check access using a caller-supplied tokenId for SUBSCRIPTION expiry.
    /// @dev This is the primary interface for SUBSCRIPTION mode. The no-proof
    ///      hasAccess() falls back to binding.tokenId which only works when
    ///      the user holds that exact tokenId.
    function hasAccessWithProof(address user, uint256 toolId, uint256 tokenId) external view returns (bool) {
        return _checkAccess(user, toolId, tokenId, true);
    }

    /// @dev Iterates up to MAX_COLLECTIONS*2 bindings, each doing an external
    ///      call (balanceOf/ownerOf/expiresAt). Consumers should set an appropriate
    ///      gas limit when calling hasAccess from other contracts.
    function _checkAccess(address user, uint256 toolId, uint256 proofTokenId, bool useProof)
        internal
        view
        returns (bool)
    {
        ToolConfig memory config = toolRegistry.getToolConfig(toolId);

        if (!config.active) return false;
        if (config.accessMode == AccessMode.OPEN) return true;

        CollectionBinding[] storage bindings = _bindings[toolId];
        uint256 len = bindings.length;

        for (uint256 i; i < len;) {
            CollectionBinding storage binding = bindings[i];
            if (!binding.active) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (binding.tokenStandard == TokenStandard.ERC721) {
                if (config.accessMode == AccessMode.NFT_GATED) {
                    if (IERC721(binding.collection).balanceOf(user) > 0) return true;
                } else {
                    // SUBSCRIPTION: verify ownership of the specific proof token
                    uint256 subTokenId = useProof ? proofTokenId : binding.tokenId;
                    try IERC721(binding.collection).ownerOf(subTokenId) returns (address owner) {
                        if (owner == user) {
                            try IERC5643(binding.collection).expiresAt(subTokenId) returns (uint64 expiry) {
                                if (expiry > block.timestamp) return true;
                            } catch {}
                        }
                    } catch {}
                }
            } else {
                if (config.accessMode == AccessMode.NFT_GATED) {
                    if (IERC1155(binding.collection).balanceOf(user, binding.tokenId) > 0) return true;
                } else {
                    uint256 subTokenId = useProof ? proofTokenId : binding.tokenId;
                    if (IERC1155(binding.collection).balanceOf(user, subTokenId) > 0) {
                        try IERC5643(binding.collection).expiresAt(subTokenId) returns (uint64 expiry) {
                            if (expiry > block.timestamp) return true;
                        } catch {}
                    }
                }
            }

            unchecked {
                ++i;
            }
        }

        return false;
    }

    function addCollection(uint256 toolId, address collection, TokenStandard standard, uint256 tokenId) external {
        _requireToolCreator(toolId);
        if (collection == address(0)) revert InvalidCollection(collection);
        if (_activeCount[toolId] >= MAX_COLLECTIONS_VALUE) revert MaxCollectionsReached(toolId);
        if (_bindings[toolId].length >= MAX_COLLECTIONS_VALUE * 2) revert MaxCollectionsReached(toolId);

        _bindings[toolId].push(
            CollectionBinding({collection: collection, tokenStandard: standard, tokenId: tokenId, active: true})
        );
        ++_activeCount[toolId];

        emit CollectionAdded(toolId, collection, standard);
    }

    /// @dev Index-based removal — callers should read getCollections() immediately
    ///      before calling to avoid targeting a stale index.
    function removeCollection(uint256 toolId, uint256 index) external {
        _requireToolCreator(toolId);

        CollectionBinding[] storage bindings = _bindings[toolId];
        if (index >= bindings.length) revert CollectionNotFound(toolId, index);

        CollectionBinding storage binding = bindings[index];
        if (!binding.active) revert CollectionNotFound(toolId, index);

        binding.active = false;
        --_activeCount[toolId];

        emit CollectionRemoved(toolId, binding.collection);
    }

    function getCollections(uint256 toolId) external view returns (CollectionBinding[] memory) {
        return _bindings[toolId];
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IToolAccessRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _requireToolCreator(uint256 toolId) internal view {
        ToolConfig memory config = toolRegistry.getToolConfig(toolId);
        if (config.creator != msg.sender) revert NotToolCreator(toolId, msg.sender);
    }
}
