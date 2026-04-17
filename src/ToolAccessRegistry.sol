// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IToolAccessRegistry, CollectionBinding, TokenStandard} from "./interfaces/IToolAccessRegistry.sol";
import {
    IToolAccessRegistryCrossChain,
    CrossChainBinding,
    CrossChainProof
} from "./interfaces/IToolAccessRegistryCrossChain.sol";
import {IGatewayKeyRegistry} from "./interfaces/IGatewayKeyRegistry.sol";
import {IToolRegistry, ToolConfig, AccessMode} from "./interfaces/IToolRegistry.sol";

/// @notice Minimal ERC-5643 interface for subscription expiration checks.
interface IERC5643 {
    function expiresAt(uint256 tokenId) external view returns (uint64);
}

contract ToolAccessRegistry is IToolAccessRegistry, IToolAccessRegistryCrossChain, EIP712, ERC165 {
    uint256 public constant MAX_COLLECTIONS_VALUE = 20;
    uint256 public constant MAX_CROSS_CHAIN_COLLECTIONS_VALUE = 20;
    uint256 public constant STALENESS_WINDOW_VALUE = 300;

    bytes32 private constant CROSS_CHAIN_PROOF_TYPEHASH = keccak256(
        "CrossChainProof(uint256 toolId,address account,uint256 chainId,address collection,uint256 tokenId,uint256 checkedAt)"
    );

    IToolRegistry public immutable toolRegistry;
    IGatewayKeyRegistry public immutable gatewayKeyRegistry;

    mapping(uint256 => CollectionBinding[]) private _bindings;
    mapping(uint256 => CrossChainBinding[]) private _crossChainBindings;

    /// @param _toolRegistry        Address of the Tool Registry (§1).
    /// @param _gatewayKeyRegistry  Address of the Gateway Key Registry (§4).
    ///                             May be the zero address on deployments that
    ///                             do not offer cross-chain bindings; in that
    ///                             case hasAccessWithRemoteProof will always
    ///                             return false.
    /// @dev Both addresses are immutable. Rotating to a new Gateway Key Registry
    ///      or Tool Registry requires deploying a fresh ToolAccessRegistry and
    ///      re-registering bindings; this keeps the reference implementation
    ///      simple but production deployments that anticipate key-registry
    ///      migration should consider wrapping the registry address in a proxy.
    constructor(address _toolRegistry, address _gatewayKeyRegistry) EIP712("ToolRegistryCrossChain", "1") {
        toolRegistry = IToolRegistry(_toolRegistry);
        gatewayKeyRegistry = IGatewayKeyRegistry(_gatewayKeyRegistry);
    }

    function MAX_COLLECTIONS() external pure returns (uint256) {
        return MAX_COLLECTIONS_VALUE;
    }

    function MAX_CROSS_CHAIN_COLLECTIONS() external pure returns (uint256) {
        return MAX_CROSS_CHAIN_COLLECTIONS_VALUE;
    }

    function STALENESS_WINDOW() external pure returns (uint256) {
        return STALENESS_WINDOW_VALUE;
    }

    /// @dev MUST return false for SUBSCRIPTION tools; `balanceOf` cannot
    ///      disambiguate which tokenId to check expiresAt on. Consumers MUST
    ///      use hasAccessWithProof for SUBSCRIPTION tools.
    function hasAccess(uint256 toolId, address account) external view returns (bool) {
        ToolConfig memory config = toolRegistry.getToolConfig(toolId);
        if (!config.active) return false;
        if (config.accessMode == AccessMode.SUBSCRIPTION) return false;
        // proofTokenId is unused for OPEN/NFT_GATED paths; pass 0 as a placeholder.
        return _checkAccess(account, config.accessMode, _bindings[toolId], 0);
    }

    /// @notice Check access using a caller-supplied tokenId for SUBSCRIPTION expiry.
    /// @dev The only valid access check for SUBSCRIPTION tools. For NFT_GATED,
    ///      the proof tokenId is ignored and behavior matches hasAccess.
    function hasAccessWithProof(uint256 toolId, address account, uint256 tokenId) external view returns (bool) {
        ToolConfig memory config = toolRegistry.getToolConfig(toolId);
        if (!config.active) return false;
        return _checkAccess(account, config.accessMode, _bindings[toolId], tokenId);
    }

    /// @dev Iterates up to MAX_COLLECTIONS_VALUE bindings, each doing an
    ///      external call (balanceOf/ownerOf/expiresAt). All external calls
    ///      are wrapped in try/catch so that a misbehaving bound collection
    ///      (revert, self-destructed code, wrong ABI) cannot DoS the access
    ///      check for other bindings: a failing call is treated as "no
    ///      balance" and iteration continues to the next binding.
    ///      Consumers should set an appropriate gas limit when calling from
    ///      other contracts.
    /// @dev Invariant: SUBSCRIPTION tools only reach this function via
    ///      hasAccessWithProof, since hasAccess short-circuits them upstream.
    ///      `proofTokenId` is therefore the caller-supplied value whenever the
    ///      SUBSCRIPTION/ERC-721 branch runs.
    function _checkAccess(
        address account,
        AccessMode accessMode,
        CollectionBinding[] storage bindings,
        uint256 proofTokenId
    ) internal view returns (bool) {
        if (accessMode == AccessMode.OPEN) return true;

        uint256 len = bindings.length;

        for (uint256 i; i < len;) {
            CollectionBinding storage binding = bindings[i];

            if (binding.tokenStandard == TokenStandard.ERC721) {
                if (accessMode == AccessMode.NFT_GATED) {
                    try IERC721(binding.collection).balanceOf(account) returns (uint256 bal) {
                        if (bal > 0) return true;
                    } catch {}
                } else {
                    // SUBSCRIPTION: verify ownership of the caller-supplied proof token.
                    try IERC721(binding.collection).ownerOf(proofTokenId) returns (address owner) {
                        if (owner == account) {
                            try IERC5643(binding.collection).expiresAt(proofTokenId) returns (uint64 expiry) {
                                if (expiry > block.timestamp) return true;
                            } catch {}
                        }
                    } catch {}
                }
            } else {
                // ERC-1155 bindings are only permitted for NFT_GATED tools; see
                // addCollection's UnsupportedStandardForSubscription guard.
                try IERC1155(binding.collection).balanceOf(account, binding.tokenId) returns (uint256 bal) {
                    if (bal > 0) return true;
                } catch {}
            }

            unchecked {
                ++i;
            }
        }

        return false;
    }

    function addCollection(uint256 toolId, address collection, TokenStandard standard, uint256 tokenId) external {
        // Inline creator check (rather than _requireToolCreator) so the config
        // fetched here is reused for the access-mode validation below.
        ToolConfig memory config = toolRegistry.getToolConfig(toolId);
        if (config.creator != msg.sender) revert NotToolCreator(toolId, msg.sender);
        if (collection == address(0)) revert InvalidCollection(collection);
        if (standard == TokenStandard.ERC1155 && config.accessMode == AccessMode.SUBSCRIPTION) {
            revert UnsupportedStandardForSubscription(toolId, standard);
        }
        if (standard == TokenStandard.ERC721 && tokenId != 0) revert InvalidCollection(collection);
        if (_bindings[toolId].length >= MAX_COLLECTIONS_VALUE) revert MaxCollectionsReached(toolId);

        _bindings[toolId].push(CollectionBinding({collection: collection, tokenStandard: standard, tokenId: tokenId}));

        emit CollectionAdded(toolId, collection, standard);
    }

    /// @dev Compare-and-swap removal using swap-and-pop. Reverts with
    ///      `CollectionMismatch` if the binding at `index` does not match
    ///      `expectedCollection` at the time the call lands, so racing
    ///      callers who read a stale layout fail loudly rather than
    ///      dropping the wrong binding.
    function removeCollection(uint256 toolId, uint256 index, address expectedCollection) external {
        _requireToolCreator(toolId);

        CollectionBinding[] storage bindings = _bindings[toolId];
        uint256 len = bindings.length;
        if (index >= len) revert CollectionNotFound(toolId, index);

        address actual = bindings[index].collection;
        if (actual != expectedCollection) {
            revert CollectionMismatch(toolId, index, expectedCollection, actual);
        }

        uint256 last = len - 1;
        if (index != last) {
            bindings[index] = bindings[last];
        }
        bindings.pop();

        emit CollectionRemoved(toolId, actual);
    }

    function getCollections(uint256 toolId) external view returns (CollectionBinding[] memory) {
        return _bindings[toolId];
    }

    // ──────────────────── Cross-Chain ────────────────────

    function addCrossChainCollection(
        uint256 toolId,
        uint256 chainId,
        address collection,
        TokenStandard standard,
        uint256 tokenId
    ) external {
        ToolConfig memory config = toolRegistry.getToolConfig(toolId);
        if (config.creator != msg.sender) revert NotToolCreator(toolId, msg.sender);
        if (collection == address(0)) revert InvalidCollection(collection);
        if (chainId == 0) revert InvalidChainId(chainId);
        if (config.accessMode == AccessMode.SUBSCRIPTION) {
            revert SubscriptionCrossChainUnsupported(toolId);
        }
        if (standard == TokenStandard.ERC721 && tokenId != 0) revert InvalidCollection(collection);
        if (_crossChainBindings[toolId].length >= MAX_CROSS_CHAIN_COLLECTIONS_VALUE) {
            revert MaxCrossChainCollectionsReached(toolId);
        }

        _crossChainBindings[toolId].push(
            CrossChainBinding({chainId: chainId, collection: collection, tokenStandard: standard, tokenId: tokenId})
        );

        emit CrossChainBindingAdded(toolId, chainId, collection, standard);
    }

    /// @dev Compare-and-swap removal using swap-and-pop. Reverts with
    ///      `CrossChainBindingMismatch` if the binding at `index` does not
    ///      match `(expectedChainId, expectedCollection)` at call time. Both
    ///      fields are compared because the same collection address can be
    ///      bound on multiple remote chains (e.g. deterministic CREATE2).
    function removeCrossChainCollection(
        uint256 toolId,
        uint256 index,
        uint256 expectedChainId,
        address expectedCollection
    ) external {
        _requireToolCreator(toolId);

        CrossChainBinding[] storage bindings = _crossChainBindings[toolId];
        uint256 len = bindings.length;
        if (index >= len) revert CrossChainBindingNotFound(toolId, index);

        CrossChainBinding memory binding = bindings[index];
        if (binding.chainId != expectedChainId || binding.collection != expectedCollection) {
            revert CrossChainBindingMismatch(
                toolId, index, expectedChainId, expectedCollection, binding.chainId, binding.collection
            );
        }

        uint256 last = len - 1;
        if (index != last) {
            bindings[index] = bindings[last];
        }
        bindings.pop();

        emit CrossChainBindingRemoved(toolId, binding.chainId, binding.collection);
    }

    function getCrossChainCollections(uint256 toolId) external view returns (CrossChainBinding[] memory) {
        return _crossChainBindings[toolId];
    }

    /// @notice Check access using a gateway-signed cross-chain ownership proof.
    /// @dev See IToolAccessRegistryCrossChain.hasAccessWithRemoteProof for the
    ///      verification ordering. Returns false on any failed check; the
    ///      function does not revert, so callers can use it for gating logic
    ///      without try/catch. Gateways debugging a rejected proof should
    ///      reconstruct and re-verify offchain.
    function hasAccessWithRemoteProof(uint256 toolId, address account, CrossChainProof calldata proof)
        external
        view
        returns (bool)
    {
        ToolConfig memory config = toolRegistry.getToolConfig(toolId);
        if (!config.active) return false;
        if (config.accessMode == AccessMode.OPEN) return true;
        // SUBSCRIPTION tools cannot have cross-chain bindings (addCrossChainCollection
        // rejects them), so there is nothing to verify. Fail closed.
        if (config.accessMode == AccessMode.SUBSCRIPTION) return false;

        // Proof must name the same tool and account the caller is asking about.
        if (proof.toolId != toolId) return false;
        if (proof.account != account) return false;

        // Staleness: proof must have been attested within STALENESS_WINDOW of now,
        // and MUST NOT be dated in the future.
        if (proof.checkedAt > block.timestamp) return false;
        unchecked {
            // Safe: checkedAt <= block.timestamp by the check above.
            if (block.timestamp - proof.checkedAt > STALENESS_WINDOW_VALUE) return false;
        }

        // Binding: (chainId, collection) must match an active cross-chain
        // binding on this tool. For ERC-1155 bindings, the tokenId must also
        // match the bound tokenId.
        if (!_matchesCrossChainBinding(toolId, proof)) return false;

        // Signature: recover signer from EIP-712 typed data and check against
        // the Gateway Key Registry.
        if (address(gatewayKeyRegistry) == address(0)) return false;
        address signer = _recoverCrossChainSigner(proof);
        if (!gatewayKeyRegistry.isValidGatewayKey(signer)) return false;

        return true;
    }

    function _matchesCrossChainBinding(uint256 toolId, CrossChainProof calldata proof) internal view returns (bool) {
        CrossChainBinding[] storage bindings = _crossChainBindings[toolId];
        uint256 len = bindings.length;
        for (uint256 i; i < len;) {
            CrossChainBinding storage b = bindings[i];
            if (
                b.chainId == proof.chainId && b.collection == proof.collection
                    && (b.tokenStandard != TokenStandard.ERC1155 || b.tokenId == proof.tokenId)
            ) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function _recoverCrossChainSigner(CrossChainProof calldata proof) internal view returns (address) {
        bytes32 structHash = keccak256(
            abi.encode(
                CROSS_CHAIN_PROOF_TYPEHASH,
                proof.toolId,
                proof.account,
                proof.chainId,
                proof.collection,
                proof.tokenId,
                proof.checkedAt
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, proof.gatewaySignature);
        if (err != ECDSA.RecoverError.NoError) return address(0);
        return recovered;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IToolAccessRegistry).interfaceId
            || interfaceId == type(IToolAccessRegistryCrossChain).interfaceId || super.supportsInterface(interfaceId);
    }

    function _requireToolCreator(uint256 toolId) internal view {
        ToolConfig memory config = toolRegistry.getToolConfig(toolId);
        if (config.creator != msg.sender) revert NotToolCreator(toolId, msg.sender);
    }
}
