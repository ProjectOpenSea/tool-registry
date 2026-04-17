// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TokenStandard} from "./IToolAccessRegistry.sol";

/// @notice Binding between a tool and an NFT collection on a remote chain.
/// @dev As in CollectionBinding, `tokenId` MUST be zero when
///      `tokenStandard == ERC721` and is rejected at bind time otherwise.
struct CrossChainBinding {
    uint256 chainId;
    address collection;
    TokenStandard tokenStandard;
    uint256 tokenId;
}

/// @notice Gateway-signed proof of NFT ownership on a remote chain.
/// @dev Scoped to NFT_GATED tools only. Cross-chain SUBSCRIPTION is out of
///      scope for this revision; SUBSCRIPTION tools MUST bind same-chain
///      ERC-5643 collections via IToolAccessRegistry.
struct CrossChainProof {
    uint256 toolId;
    address account;
    uint256 chainId;
    address collection;
    uint256 tokenId;
    uint256 checkedAt;
    bytes gatewaySignature;
}

/// @title IToolAccessRegistryCrossChain
/// @notice Cross-chain NFT gating extension to IToolAccessRegistry. Enables
///         NFT_GATED tools to accept holders of collections deployed on other
///         chains via gateway-signed EIP-712 attestations.
/// @dev Implementations MAY also implement IToolAccessRegistry on the same
///      contract. Deployments that offer only same-chain access MAY omit this
///      interface entirely.
///      Scope: NFT_GATED tools only. SUBSCRIPTION cross-chain bindings are
///      out of scope for this revision. The gateway would be attesting to
///      time-varying remote state (`expiresAt`), which adds a staleness race
///      on top of the existing one. A future revision MAY add SUBSCRIPTION
///      support as a pure extension.
interface IToolAccessRegistryCrossChain {
    // ──────────────────── Events ────────────────────

    event CrossChainBindingAdded(
        uint256 indexed toolId, uint256 chainId, address indexed collection, TokenStandard tokenStandard
    );
    event CrossChainBindingRemoved(uint256 indexed toolId, uint256 chainId, address indexed collection);

    // ──────────────────── Errors ────────────────────
    // Note: NotToolCreator and InvalidCollection are reused from
    // IToolAccessRegistry and are not redeclared here. Cross-chain removal
    // uses its own `CrossChainBindingMismatch` (not the same-chain
    // `CollectionMismatch`) because a collection address alone is not a
    // unique binding key across chains.

    error MaxCrossChainCollectionsReached(uint256 toolId);
    error CrossChainBindingNotFound(uint256 toolId, uint256 index);
    error InvalidChainId(uint256 chainId);
    error SubscriptionCrossChainUnsupported(uint256 toolId);
    /// @notice The binding at `index` did not match the caller's expected
    ///         `(chainId, collection)` pair.
    /// @dev Raised by `removeCrossChainCollection` when either `expectedChainId`
    ///      or `expectedCollection` does not match the binding at `index` at the
    ///      time the call lands. Same-chain collection addresses can be
    ///      duplicated across remote chains (e.g. deterministic CREATE2), so
    ///      matching on collection alone is insufficient; both fields are
    ///      compared under CAS to prevent races from removing the wrong chain's
    ///      binding.
    error CrossChainBindingMismatch(
        uint256 toolId,
        uint256 index,
        uint256 expectedChainId,
        address expectedCollection,
        uint256 actualChainId,
        address actualCollection
    );

    // ──────────────────── Constants ────────────────────

    /// @notice Maximum number of cross-chain bindings per tool.
    /// @dev Implementations MUST return exactly 20.
    function MAX_CROSS_CHAIN_COLLECTIONS() external view returns (uint256);

    /// @notice Staleness window for cross-chain proofs, in seconds.
    /// @dev Implementations MUST return 300 (5 minutes). Gateways SHOULD
    ///      refresh attestations proactively before expiry.
    function STALENESS_WINDOW() external view returns (uint256);

    // ──────────────────── Access Check ────────────────────

    /// @notice Check access using a gateway-signed cross-chain ownership proof.
    /// @dev Returns false if any step fails. Verification order (cheap O(1)
    ///      comparisons first, binding loop and ECDSA recovery last):
    ///   1. Tool must be active. OPEN tools return true without any proof
    ///      verification (the OPEN mode does not require gating).
    ///   2. `proof.toolId == toolId` and `proof.account == account`.
    ///   3. `proof.checkedAt <= block.timestamp` and
    ///      `block.timestamp - proof.checkedAt <= STALENESS_WINDOW()`.
    ///   4. `(proof.chainId, proof.collection)` matches a CrossChainBinding
    ///      for the tool; for ERC-1155 bindings `proof.tokenId` must also
    ///      match the bound tokenId.
    ///   5. EIP-712 signature recovers to an address registered in
    ///      IGatewayKeyRegistry.
    ///      SUBSCRIPTION tools cannot have cross-chain bindings (see
    ///      addCrossChainCollection), so this function returns false for
    ///      SUBSCRIPTION tools without inspecting the proof.
    function hasAccessWithRemoteProof(uint256 toolId, address account, CrossChainProof calldata proof)
        external
        view
        returns (bool);

    // ──────────────────── Collection Management ────────────────────

    /// @notice Bind a remote-chain NFT collection to a tool. Creator only.
    /// @dev MUST revert with `MaxCrossChainCollectionsReached` once the cap
    ///      is reached. MUST revert with `SubscriptionCrossChainUnsupported`
    ///      if the tool's accessMode is `SUBSCRIPTION`. MUST revert with
    ///      `InvalidCollection` if `standard` is `ERC721` and `tokenId != 0`.
    function addCrossChainCollection(
        uint256 toolId,
        uint256 chainId,
        address collection,
        TokenStandard standard,
        uint256 tokenId
    ) external;

    /// @notice Remove a cross-chain collection binding by index. Creator only.
    /// @dev Implementations MUST revert with `CrossChainBindingMismatch` if the
    ///      binding at `index` does not have
    ///      `(chainId, collection) == (expectedChainId, expectedCollection)` at
    ///      the time the call lands. The compare-and-swap matches on both
    ///      fields because a single collection address can legitimately be
    ///      bound on multiple remote chains (e.g. deterministic CREATE2
    ///      deployments). Same CAS intent as
    ///      `IToolAccessRegistry.removeCollection`.
    function removeCrossChainCollection(
        uint256 toolId,
        uint256 index,
        uint256 expectedChainId,
        address expectedCollection
    ) external;

    /// @notice Get all cross-chain collection bindings for a tool.
    function getCrossChainCollections(uint256 toolId) external view returns (CrossChainBinding[] memory);
}
