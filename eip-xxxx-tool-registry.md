---
eip: XXXX
title: Agent Tool Registry
description: Minimal onchain registry for AI agent tools with extensible predicate-based access control
author: Cody Sears (@CodySearsOS), Ryan Ghods (@ryanio)
discussions-to: https://ethereum-magicians.org/t/eip-xxxx-agent-tool-registry/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2026-04-17
requires: 165
---

## Abstract

This ERC specifies a permissionless onchain registry for AI agent tools. Each registration commits a metadata URI and a content hash; invocation access is gated by an optional external predicate contract. Registrations are anchored to a canonical off-chain manifest through origin-binding (the manifest MUST be served at a well-known path on the endpoint's origin) and creator self-attestation (the manifest declares which onchain address is entitled to register it). Pricing and access-model details are deferred: the manifest carries protocol-agnostic pricing hints, and access logic lives in the predicate layer.

## Motivation

**Discovery is fragmented.** AI agent tools are scattered across proprietary catalogs with no uniform onchain source of truth. Agents need a permissionless, chain-native directory to find and verify tools.

**Access control needs to be extensible.** A single predicate pointer delegates gating to an external contract, following the same "pluggable external contract" pattern used by Seaport zones, Uniswap v4 hooks, and ERC-4337 paymasters. Any access model (NFT gating, subscriptions, allowlists, DAO votes, reputation scores) is expressible as a predicate contract without modifying the registry.

**Onchain commitment matters.** By storing a `keccak256` hash of the manifest onchain, consumers can verify that the manifest they fetched has not been tampered with. Combined with origin-binding, this provides a lightweight trust anchor without requiring onchain access checks or gateway infrastructure.

**Pricing is part of discovery.** An agent choosing between two tools that do the same thing needs to know cost. Declaring pricing in the manifest (and committing it by hash onchain) lets consumers compare tools before invocation. The manifest declares what the tool costs; the endpoint enforces payment. The registry itself never handles funds. The pricing schema is deliberately protocol-agnostic: it identifies the payment protocol by an opaque string so the standard does not depend on any specific payment system.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This ERC targets EVM chains. The registry interface uses EVM-native types (`address`, `bytes32`, `uint256`), and tool IDs are scoped to the `(chainId, registryAddress)` tuple of an EVM deployment (see §1). Pricing entries carry their own chain identifiers via [CAIP-19](https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-19.md) `asset` and [CAIP-10](https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-10.md) `recipient`, so a tool registered on an EVM chain MAY price itself in assets on any CAIP-10/CAIP-19 namespace; concrete guidance in §3 focuses on `eip155:*` because that is the namespace the reference implementation has been exercised against.

### 1. Tool Registry

#### ToolConfig Struct

```solidity
/// @notice Onchain configuration for a registered tool.
struct ToolConfig {
    address creator;          // Address that registered the tool (immutable after registration)
    string metadataURI;       // Resolves to Tool Manifest JSON
    bytes32 manifestHash;     // keccak256 of the canonical manifest bytes at metadataURI
    address accessPredicate;  // address(0) = open access; otherwise, gating contract
}
```

#### IToolRegistry Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IToolRegistry
/// @notice Minimal onchain registry for AI agent tools.
/// @dev ERC-165 interface ID: 0x609466bf
interface IToolRegistry /* is IERC165 */ {

    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a new tool is registered.
    /// @dev The event carries `metadataURI` (non-indexed) alongside
    ///      `manifestHash` so indexers can resolve a new tool without a
    ///      follow-up `getToolConfig` call. `string` cannot participate
    ///      in the topic set, so filter by `toolId`, `creator`, or
    ///      `accessPredicate` at the topic layer and parse `metadataURI`
    ///      from the log data.
    event ToolRegistered(
        uint256 indexed toolId,
        address indexed creator,
        address indexed accessPredicate,
        string metadataURI,
        bytes32 manifestHash
    );

    /// @notice Emitted when a tool's metadata URI and/or manifest hash is updated.
    event ToolMetadataUpdated(
        uint256 indexed toolId,
        string newURI,
        bytes32 newHash
    );

    /// @notice Emitted when a tool's access predicate is updated.
    event AccessPredicateUpdated(
        uint256 indexed toolId,
        address indexed newPredicate
    );

    // ──────────────────── Errors ────────────────────

    /// @notice The specified tool ID does not exist.
    error ToolNotFound(uint256 toolId);

    /// @notice Caller is not the tool's creator.
    error NotToolCreator(uint256 toolId, address caller);

    /// @notice The provided metadata URI is invalid.
    /// @dev Implementations MUST revert with this error when `metadataURI` is
    ///      the empty string. Implementations MAY additionally reject URIs that
    ///      fail implementation-specific validation (e.g., length caps).
    error InvalidMetadataURI();

    /// @notice The provided manifest hash is `bytes32(0)`.
    /// @dev `keccak256` of any real content cannot produce `bytes32(0)`, so
    ///      a zero hash is semantically meaningless as a commitment.
    error InvalidManifestHash();

    /// @notice The provided access predicate claims ERC-165 support but does
    ///         not advertise `IAccessPredicate`.
    /// @dev OPTIONAL. Implementations that perform registration-time ERC-165
    ///      validation (see Zero-Code Access Predicates in Security
    ///      Considerations) MUST revert with this error when the candidate
    ///      predicate returns `true` for `type(IERC165).interfaceId` but then
    ///      returns `false` (or reverts) when queried for
    ///      `type(IAccessPredicate).interfaceId`. Implementations that do not
    ///      perform ERC-165 validation omit this error. The error is not
    ///      required to reach the ERC-165 interface ID check (it does not
    ///      participate in any function selector); implementations MAY
    ///      substitute an equivalent error provided the validation behavior
    ///      matches.
    error InvalidAccessPredicate(address predicate);

    // ──────────────────── Registration ────────────────────

    /// @notice Register a new tool. The caller becomes the tool's creator.
    /// @dev The tool's `creator` is set to `msg.sender` and cannot be changed.
    ///      `manifestHash` is `keccak256` over the canonical manifest bytes
    ///      served at `metadataURI`. Consumers SHOULD reject manifests whose
    ///      `keccak256` does not match the onchain hash.
    ///      Implementations MUST revert with `InvalidManifestHash` if
    ///      `manifestHash` is `bytes32(0)`.
    ///      Implementations MUST revert with `InvalidMetadataURI` if
    ///      `metadataURI` is the empty string.
    ///      If `accessPredicate` is `address(0)`, the tool is open to all callers.
    /// @param metadataURI     URI resolving to the Tool Manifest JSON.
    /// @param manifestHash    keccak256 of the canonical manifest bytes at metadataURI.
    /// @param accessPredicate Address of the access-gating contract, or address(0) for open access.
    /// @return toolId The sequential ID assigned to the tool.
    function registerTool(
        string calldata metadataURI,
        bytes32 manifestHash,
        address accessPredicate
    ) external returns (uint256 toolId);

    // ──────────────────── Metadata ────────────────────

    /// @notice Update a tool's metadata URI and manifest hash atomically. Creator only.
    /// @dev Implementations MUST revert with `InvalidManifestHash` if `newHash`
    ///      is `bytes32(0)`, and with `InvalidMetadataURI` if `newURI` is the
    ///      empty string.
    ///      MUST emit `ToolMetadataUpdated` when either `newURI` or `newHash`
    ///      differs from the stored values. Implementations MAY skip emission
    ///      when the call is idempotent (both values match what is already
    ///      stored), to avoid polluting event streams.
    /// @param toolId  The tool to update.
    /// @param newURI  The new metadata URI.
    /// @param newHash keccak256 of the canonical manifest bytes served at `newURI`.
    function updateToolMetadata(
        uint256 toolId,
        string calldata newURI,
        bytes32 newHash
    ) external;

    // ──────────────────── Access Predicate ────────────────────

    /// @notice Update a tool's access predicate. Creator only.
    /// @dev Setting `newPredicate` to `address(0)` makes the tool open-access.
    ///      Creators who want to temporarily disable a tool SHOULD point
    ///      `newPredicate` at an always-deny predicate rather than delete the
    ///      registration; this re-uses the predicate mechanism already
    ///      required for any gated tool.
    ///      MUST emit `AccessPredicateUpdated` when the stored predicate
    ///      changes. Implementations MAY skip emission when the call is
    ///      idempotent (`newPredicate` equals the currently stored
    ///      predicate), to avoid polluting event streams.
    /// @param toolId       The tool to update.
    /// @param newPredicate The new access predicate address, or address(0) for open access.
    function setAccessPredicate(uint256 toolId, address newPredicate) external;

    // ──────────────────── Views ────────────────────

    /// @notice Get the full configuration for a tool.
    /// @dev MUST revert with `ToolNotFound` if `toolId` has not been registered.
    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory);

    /// @notice Check whether an account has access to a tool.
    /// @dev Convenience wrapper over `tryHasAccess`: returns `true` if and
    ///      only if the predicate call succeeds AND returns a canonical
    ///      "granted" answer. Any malfunction (revert, out-of-gas,
    ///      non-canonical return word, zero-code predicate) returns `false`,
    ///      identical to a clean denial. Callers that need to distinguish
    ///      "denied" from "predicate malfunctioned" MUST use `tryHasAccess`
    ///      instead.
    ///      If `accessPredicate` is `address(0)`, MUST return true (open),
    ///      ignoring `data`. Callers for open-access or data-less predicates
    ///      SHOULD pass empty bytes (`""`) for `data`.
    /// @param toolId  The tool to check.
    /// @param account The account requesting access.
    /// @param data    Opaque context bytes forwarded to the predicate
    ///                (e.g., a tokenId, a Merkle proof, a signature).
    function hasAccess(
        uint256 toolId,
        address account,
        bytes calldata data
    ) external view returns (bool);

    /// @notice Check whether an account has access to a tool and report
    ///         whether the predicate call itself succeeded.
    /// @dev Returns `(ok, granted)`:
    ///      - `(true, true)`: open-access, or the predicate returned a
    ///        canonical ABI-encoded `true`.
    ///      - `(true, false)`: the predicate returned a canonical ABI-encoded
    ///        `false`; this is a clean denial.
    ///      - `(false, false)`: the predicate call failed in a way that the
    ///        registry cannot interpret. This covers revert, out-of-gas,
    ///        wrong return length, non-canonical return word (any 32-byte
    ///        value that is neither `0` nor `1`), and zero-code predicates.
    ///        Consumers SHOULD surface this case separately from a clean
    ///        denial (e.g., "predicate is misconfigured" vs "you do not
    ///        qualify"). Implementations MUST NOT return `(false, true)`.
    ///      Same delegation contract as `hasAccess`: MUST invoke the
    ///      predicate via `staticcall`. If `accessPredicate` is `address(0)`,
    ///      MUST return `(true, true)` without calling anything.
    /// @return ok       Whether the predicate answered canonically.
    /// @return granted  Whether access is granted. Only meaningful when `ok`.
    function tryHasAccess(
        uint256 toolId,
        address account,
        bytes calldata data
    ) external view returns (bool ok, bool granted);

    /// @notice Total number of registered tools.
    /// @dev Tool IDs are assigned sequentially starting from 1 and are never
    ///      reused, so `toolCount()` equals the highest assigned tool ID.
    ///      Callers MAY treat `toolId == 0` as "never registered" since no
    ///      registration can produce that ID; implementations rely on this
    ///      to use `toolId == 0` as an existence sentinel in internal state.
    function toolCount() external view returns (uint256);

    /// @notice Returns a human-readable identifier for the registry implementation.
    /// @dev MUST return a non-empty string. Format is implementation-defined;
    ///      the reference implementation returns `"ToolRegistry"`. Consumers
    ///      SHOULD treat the value as opaque except for equality comparison.
    function name() external view returns (string memory);

    /// @notice Returns the implementation's version string.
    /// @dev MUST return a non-empty string. Format is implementation-defined;
    ///      the reference implementation uses `MAJOR.MINOR` (e.g. `"0.1"`,
    ///      `"1.0"`, `"1.1"`, `"2.0"`). Consumers SHOULD treat the value as
    ///      opaque except for equality comparison; ordering semantics are
    ///      implementation-defined.
    function version() external view returns (string memory);
}
```

`name()` and `version()` exist as diagnostic primitives so consumers can identify a registry deployment without ABI introspection or an external lookup table. The reference implementation uses a `MAJOR.MINOR` scheme — `"0.1"` for the current pre-release, `"1.0"` for the first stable release, `"1.1"` / `"2.0"` for subsequent revisions. The scheme intentionally omits the patch component used in strict semver: `version()` is a coarse-grained identity for the deployment, not a fine-grained changelog.

#### IAccessPredicate Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IAccessPredicate
/// @notice Two-function interface for tool access gating.
/// @dev Anyone can implement this to create custom access logic
///      (NFT gating, allowlists, staking requirements, subscriptions, etc.).
interface IAccessPredicate {
    /// @notice Check whether an account has access to a tool.
    /// @param toolId  The tool being accessed.
    /// @param account The account requesting access.
    /// @param data    Opaque context bytes (e.g., tokenId, proof, signature).
    /// @return Whether access is granted.
    function hasAccess(
        uint256 toolId,
        address account,
        bytes calldata data
    ) external view returns (bool);

    /// @notice Returns a human-readable identifier for the predicate
    ///         implementation (e.g. `"ERC721OwnerPredicate"`).
    /// @dev MUST return a non-empty string. Format is implementation-defined;
    ///      consumers SHOULD treat the value as opaque except for equality
    ///      comparison. Useful for indexer / explorer display so consumers
    ///      can distinguish between predicate implementations without ABI
    ///      introspection.
    function name() external view returns (string memory);
}
```

Predicate introspection beyond `name()` (advertising the shape of `data` the predicate expects, or the policy it enforces) is out of scope for this ERC. A companion ERC MAY specify such a mechanism later. `name()` is intentionally minimal — it gives indexers and consumers a non-opaque identifier without committing the standard to a richer introspection schema. Consumers today rely on out-of-band documentation from the predicate author, mirroring how Seaport zones and Uniswap v4 hooks are documented.

#### Tool ID Scope

Tool IDs are scoped to the `(chainId, registryAddress)` tuple. Two independent deployments of this registry (on the same or different chains) MAY assign the same tool ID to unrelated tools. Offchain consumers (indexers, wallets, agent frameworks) MUST qualify tool references with the deploying chain ID and registry address. The RECOMMENDED canonical identifier format follows CAIP-19: `eip155:<chainId>/erc-xxxx:<registryAddress>/<toolId>`.

### 2. Tool Manifest

The `metadataURI` in `ToolConfig` MUST resolve to a JSON document conforming to the schema below. Consumers SHOULD validate that the `type` field matches a known schema version identifier and SHOULD reject manifests with an unknown or missing `type`.

#### Canonical Manifest Bytes

The `manifestHash` in `ToolConfig` is `keccak256` over the **JSON Canonicalization Scheme (JCS)** form of the manifest, as defined by [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785). JCS normalizes object key order, whitespace, number formatting, and string escaping so that semantically identical manifests produce identical byte sequences. Implementations MUST canonicalize with JCS before hashing, and consumers MUST canonicalize before verifying. Servers MAY serve the manifest in any JSON form; the hash commits to the JCS form regardless of transport representation.

JCS does not normalize Unicode string content or reject byte-order marks, so two extra rules apply to every manifest before JCS is run:

- **Unicode normalization:** all JSON string values MUST be in Unicode [Normalization Form C (NFC)](https://www.unicode.org/reports/tr15/) per Unicode 16.0 or later. Producers MUST NFC-normalize before JCS serialization; consumers MUST reject a fetched manifest whose strings are not already NFC-normalized (no silent re-normalization, since that would change the bytes that were hashed). This prevents hash divergence between producers that canonicalize with NFC and consumers that do not.
- **Byte-order mark:** the manifest MUST be served as UTF-8 without a byte-order mark. Consumers MUST reject a fetched response whose bytes begin with `EF BB BF` rather than silently stripping the BOM, because silent stripping would change the bytes fed to `keccak256` and cause a hash mismatch that is difficult to diagnose.

Both rules are treated as verification failures (see [§5 Handling Verification Failure](#handling-verification-failure)). Concrete hash-divergence vectors for NFC-vs-NFD and with-vs-without-BOM appear in the test-vectors appendix alongside canonical reference manifests.

Reference implementations of JCS suitable for use with this ERC:

- JavaScript / TypeScript: [`canonicalize`](https://www.npmjs.com/package/canonicalize) (npm).
- Python: [`jcs`](https://pypi.org/project/jcs/) (PyPI).
- Go: [`jcs`](https://pkg.go.dev/github.com/cyberphone/json-canonicalization/go/src/webpki.org/jsoncanonicalizer) from the reference implementation linked by RFC 8785.

Any RFC 8785 conformant implementation MUST produce the same byte output for the same semantic input; consumers and producers SHOULD use maintained libraries rather than hand-rolled canonicalizers to avoid hash divergence.

#### Required Fields

| Field | Type | Description |
| --- | --- | --- |
| `type` | string | Schema version identifier (e.g., `"https://eips.ethereum.org/EIPS/eip-XXXX#tool-manifest-v1"`) |
| `name` | string | Tool name. 1-128 Unicode code points in NFC form. MUST NOT contain Unicode control characters (general category `Cc`). |
| `description` | string | Human-readable description. 1-500 Unicode code points in NFC form. MAY contain LF (`U+000A`), CR (`U+000D`), and TAB (`U+0009`) for Markdown formatting; all other Unicode control characters (general category `Cc`) MUST NOT appear. |
| `endpoint` | string | URL where the tool is hosted. MUST begin with `https://` after URL normalization. Other schemes (`http://`, `data:`, `javascript:`, `file:`, etc.) MUST NOT be used; consumers MUST reject a manifest whose `endpoint` is not `https://`. |
| `inputs` | object | JSON Schema defining input parameters. `{}` is valid and means "no schema"; the empty object counts as 1 node against the `inputs` + `outputs` 1,024-node cap (see [Manifest Parser Hardening](#manifest-parser-hardening)). |
| `outputs` | object | JSON Schema defining output parameters. `{}` is valid and means "no schema"; counted the same way as `inputs`. |
| `creatorAddress` | string | The onchain address permitted to register this tool. MUST be a 42-character `0x`-prefixed lowercase hex string (20 bytes). The manifest's `creatorAddress` field MUST equal the `creator` address recorded onchain (i.e., `msg.sender` of `registerTool`). This allows offchain consumers to verify manifest authenticity by comparing the served manifest's `creatorAddress` with `getToolConfig(toolId).creator`. See [§5 Creator Binding](#5-creator-binding-anti-impersonation) for the grammar rationale and consumer comparison rules. |

#### Optional Fields

| Field | Type | Description |
| --- | --- | --- |
| `version` | string | Semantic version (e.g., `"1.0.0"`). Consumers MAY interpret an absent `version` as `"1.0.0"` for display purposes, but MUST NOT insert a default into the manifest before JCS canonicalization; the manifest is hashed as served. |
| `image` | string | Tool icon URL. MUST be at most 2,048 characters after URL normalization. Consumers are responsible for rendering this field safely; see [Rendering Manifest Content](#rendering-manifest-content). |
| `tags` | array | Discovery tags. Each tag MUST match `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$` and be 1-32 Unicode code points; the array MUST contain at most 16 entries and MUST NOT contain duplicates (consumers MUST reject manifests with repeated tags). |
| `pricing` | array | Payment options for tool invocation (see [Pricing](#3-pricing)) |

#### Unknown Fields and Extensions

Consumers MUST ignore unknown top-level fields so that future extensions land without breaking older parsers. Unknown fields MUST NOT override or shadow any field defined in this ERC; consumers MUST derive the meaning of specified fields only from the specified fields.

Extension authors MUST namespace their keys. The RECOMMENDED form is a reverse-DNS prefix (`"io.opensea.paymentHint"`), following [RFC 6648](https://www.rfc-editor.org/rfc/rfc6648)'s guidance against the legacy `X-` convention. Existing `x-`-prefixed keys (`"x-opensea-paymentHint"`) remain tolerated for backwards-compatibility with ecosystems that adopted them, but new extensions SHOULD prefer reverse-DNS. Extensions SHOULD NOT occupy bare top-level names, to avoid colliding with future normative additions to this ERC.

#### Example Manifest (Free Tool)

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#tool-manifest-v1",
  "name": "nft-price-oracle",
  "description": "Returns estimated floor price for any NFT collection.",
  "endpoint": "https://tools.example.com/nft-price-oracle",
  "inputs": {
    "type": "object",
    "properties": {
      "collection": { "type": "string", "description": "Contract address" },
      "chainId": { "type": "integer" }
    },
    "required": ["collection", "chainId"]
  },
  "outputs": {
    "type": "object",
    "properties": {
      "floorPriceEth": { "type": "string" },
      "updatedAt": { "type": "string", "format": "date-time" }
    }
  },
  "version": "1.0.0",
  "tags": ["nft", "pricing", "oracle"],
  "creatorAddress": "0xabcdefabcdef1234567890abcdefabcdef123456"
}
```

#### Example Manifest (Paid Tool)

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#tool-manifest-v1",
  "name": "premium-analytics",
  "description": "Advanced portfolio analytics for NFT holders.",
  "endpoint": "https://tools.example.com/premium-analytics",
  "inputs": {
    "type": "object",
    "properties": {
      "wallet": { "type": "string", "description": "Wallet address to analyze" }
    },
    "required": ["wallet"]
  },
  "outputs": {
    "type": "object",
    "properties": {
      "totalValue": { "type": "string" },
      "breakdown": { "type": "array" }
    }
  },
  "version": "1.0.0",
  "tags": ["analytics", "portfolio"],
  "pricing": [
    {
      "amount": "20000",
      "asset": "eip155:8453/erc20:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      "recipient": "eip155:8453:0xabcdef0123456789abcdef0123456789abcdef01",
      "protocol": "x402"
    },
    {
      "amount": "20000",
      "asset": "eip155:1/erc20:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      "recipient": "eip155:1:0xabcdef0123456789abcdef0123456789abcdef01",
      "protocol": "x402"
    }
  ],
  "creatorAddress": "0xabcdef0123456789abcdef0123456789abcdef01"
}
```

### 3. Pricing

The manifest MAY include a `pricing` array that declares the tool's accepted payment options. This is a discovery mechanism: it tells agents what a tool costs before they invoke it. The endpoint enforces payment; the registry never handles funds.

The pricing schema is deliberately protocol-agnostic. Each entry identifies a payment protocol by an opaque string (`protocol`). The ERC defines no protocol-specific semantics; it provides a uniform structure so that manifests from different ecosystems are comparable without prior knowledge of any particular payment system.

#### Pricing Entry Fields

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `amount` | string | Yes | Cost per invocation in the asset's smallest unit (e.g., `"20000"` for 0.02 USDC). MUST match the regular expression `^(0|[1-9][0-9]*)$` (decimal, no leading zeros, no sign, no decimal point) and MUST be at most 78 characters long (the decimal length of `type(uint256).max`). The value it represents MUST be in the range `[0, 2^256 − 1]`; a 78-digit string whose numeric value exceeds `type(uint256).max` MUST be rejected. Consumers MUST reject any value that fails the grammar or the range check. |
| `asset` | string | Yes | [CAIP-19](https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-19.md) asset identifier. Encodes both the chain and the asset in one field (e.g., `"eip155:8453/erc20:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"` for USDC on Base, `"eip155:1/slip44:60"` for native ETH on Ethereum). |
| `recipient` | string | Yes | [CAIP-10](https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-10.md) account identifier that receives payment (e.g., `"eip155:8453:0xabcdef…"`). MUST reference the same chain as `asset`. The account reference MUST NOT be the zero address. |
| `protocol` | string | Yes | Payment protocol identifier (e.g., `"x402"`, `"erc20-transfer"`). Opaque to this specification; the ERC does not define protocol-specific behavior. |

**CAIP encoding on `eip155:*` networks:** hex digits inside `asset` and `recipient` MUST be lowercase (non-checksummed) so that JCS-canonicalized manifests produce deterministic bytes for the same address. Consumers comparing addresses retrieved from the manifest to values from other sources SHOULD normalize to lowercase before comparing.

**Non-EVM namespaces:** any CAIP-2 namespace supported by CAIP-10 and CAIP-19 is permitted. Encoding, however, is only well-understood on `eip155:*` at the time this ERC is published; tools targeting other namespaces SHOULD validate against the relevant CAIP namespace specification before relying on cross-ecosystem agents to interpret their pricing.

**Constraints:**

- All four fields are REQUIRED when a pricing entry is present.
- `pricing`, when present, MUST be a non-empty array. A JSON `null` value for `pricing` MUST be rejected; the field is either absent or a non-empty array.
- The chain references embedded in `asset` (the CAIP-19 `chain_id` prefix) and `recipient` (the CAIP-10 `chain_id` prefix) MUST be identical; a pricing entry whose asset and recipient live on different chains MUST be rejected. CAIP-19 separates the chain reference from the asset reference with `/`, while CAIP-10 separates the chain reference from the account reference with `:`; the following pseudocode extracts and compares the two:

    ```
    // CAIP-19 asset format:    <namespace>:<reference>/<asset_namespace>:<asset_reference>
    // CAIP-10 recipient format: <namespace>:<reference>:<account_reference>
    assetChain     = substring_before(asset,     "/")   // e.g. "eip155:8453"
    recipientChain = rsubstring_before(recipient, ":")  // e.g. "eip155:8453"
    require assetChain == recipientChain
    ```
- The array is ordered by creator preference: the first entry is the creator's preferred payment method.
- Agents that do not support any listed `protocol` value SHOULD treat the tool as "pricing unknown" rather than "free."
- Agents SHOULD iterate the array and select the first entry whose `protocol` they support.

**Display guidance (non-normative):** `amount` is always in the asset's smallest unit. Discovery UIs and agent frameworks SHOULD read the token's `decimals()` (for ERC-20 tokens) or use known native-currency decimals to display human-readable amounts.

#### Example: Multi-Option Pricing (USDC on Base or Ethereum)

```json
{
  "pricing": [
    {
      "amount": "20000",
      "asset": "eip155:8453/erc20:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      "recipient": "eip155:8453:0xabcdef0123456789abcdef0123456789abcdef01",
      "protocol": "x402"
    },
    {
      "amount": "20000",
      "asset": "eip155:1/erc20:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      "recipient": "eip155:1:0xabcdef0123456789abcdef0123456789abcdef01",
      "protocol": "x402"
    }
  ]
}
```

#### Example: Native ETH Payment

```json
{
  "pricing": [
    {
      "amount": "1000000000000000",
      "asset": "eip155:1/slip44:60",
      "recipient": "eip155:1:0xabcdef0123456789abcdef0123456789abcdef01",
      "protocol": "native-transfer"
    }
  ]
}
```

### 4. Origin-Binding (Anti-Impersonation)

The manifest MUST be fetchable at a slugged well-known path on the same origin as `endpoint`:

```
<origin>/.well-known/ai-tool/<slug>.json
```

The `<slug>` is chosen by the origin operator and MUST match the pattern `[a-z0-9]([a-z0-9-]*[a-z0-9])?` with length 1-64 characters. Slugs are scoped to the origin: two different origins MAY use the same slug for unrelated tools. Origin operators MUST ensure slugs are unique within a single origin. An origin hosting exactly one tool MAY pick any compliant slug (e.g., `default`, or the tool's name).

The `metadataURI` declared onchain MUST exactly equal this URL once both sides have been normalized per the rules below; consumers MUST NOT accept a manifest served from any other location.

Origin comparison follows [RFC 6454](https://www.rfc-editor.org/rfc/rfc6454): same scheme, host, and port. `endpoint` MAY include a path or query string; only its scheme, host, and port participate in the origin check.

#### URL Normalization

Because URLs have multiple equivalent representations, both registrants and consumers MUST reduce a `metadataURI` to the following canonical form before writing, reading, or comparing it:

1. Lowercase the scheme and host.
2. Omit port 443 (the default for `https`).
3. Preserve the path exactly as specified by §4 (`/.well-known/ai-tool/<slug>.json`). Do not append a trailing slash.
4. Apply no query string and no fragment. Consumers MUST reject a `metadataURI` containing `?` or `#`.
5. Leave percent-encoding as-is in the slug path segment. The slug grammar (`[a-z0-9]([a-z0-9-]*[a-z0-9])?`) does not use characters that require percent-encoding, so a compliant slug has exactly one encoded form.
6. Normalize the host as an A-label (ASCII Compatible Encoding, per [RFC 5891](https://www.rfc-editor.org/rfc/rfc5891)) before lowercasing. Consumers MUST reject a `metadataURI` whose host is given as a U-label (internationalized) without ACE encoding.

Only the `https` scheme is permitted. Consumers MUST reject any `metadataURI` that does not begin with `https://` after normalization. After normalizing both sides, string equality (byte-for-byte) is the comparison rule for check 1 of §5 Consumer Verification.

This origin-binding rule ensures that only the operator of the endpoint's origin can serve a manifest for it. Registering a tool at a domain you do not control is impossible because you cannot place the manifest at the required well-known path.

This is the same trust model used by Let's Encrypt, Apple's `apple-app-site-association`, OAuth discovery (`.well-known/openid-configuration`), and WebFinger. It is not perfect (DNS hijacking, compromised TLS), but it is simple, widely understood, and sufficient for the majority of use cases.

#### Example: Single-Tool Origin

```
endpoint     = https://weather-oracle.example.com
metadataURI  = https://weather-oracle.example.com/.well-known/ai-tool/weather.json
```

#### Example: Multi-Tool Origin

An origin hosting multiple tools registers each under its own slug:

```
endpoint     = https://opensea.io/api/search
metadataURI  = https://opensea.io/.well-known/ai-tool/search.json

endpoint     = https://opensea.io/api/trade
metadataURI  = https://opensea.io/.well-known/ai-tool/trade.json

endpoint     = https://opensea.io/api/mint
metadataURI  = https://opensea.io/.well-known/ai-tool/mint.json
```

All three share the `https://opensea.io` origin, so each slug MUST be unique under that origin.

### 5. Creator Binding (Anti-Impersonation)

Origin-binding (§4) proves a manifest was served by the endpoint's operator. It does not prove which onchain account is entitled to register that manifest. Because `registerTool` is permissionless, any account can call it with any `metadataURI` and any `accessPredicate`. Without an additional check, an attacker can read a legitimate creator's well-known URL and register it under the attacker's own address with a malicious predicate: the manifest bytes and `manifestHash` would still verify, but the onchain entry would gate access through the attacker's contract.

Creator binding closes this gap by having the manifest itself declare which onchain address is permitted to appear as `creator`.

#### `creatorAddress` Field

```json
{
  "creatorAddress": "0xabcdefabcdef1234567890abcdefabcdef123456"
}
```

The `creatorAddress` field MUST be a 0x-prefixed 20-byte hex string. Manifest producers MUST write the hex digits in lowercase (non-checksummed) so that JCS-canonicalized manifests produce deterministic bytes for the same address; consumers MUST compare `creatorAddress` against the onchain `creator` case-insensitively so that a manifest produced by a non-conformant tool that emitted checksummed hex can still be matched. A manifest served with checksummed or mixed-case hex is non-conformant: it will produce a different `manifestHash` than the all-lowercase canonical form, so the hash check in §5 Consumer Verification will fail even when the creator comparison would succeed.

Richer creator metadata (ENS names, contact info, reputation signals) is out of scope for this ERC and MAY be placed under a namespaced extension key (see [Unknown Fields and Extensions](#unknown-fields-and-extensions)). Consumers that resolve ENS names MAY use such extensions for display but MUST NOT rely on them for the creator-binding check.

#### Registration-Time Enforcement

SDKs implementing this specification SHOULD validate at registration time that the signing account matches `manifest.creatorAddress` and refuse to submit the transaction on mismatch. Offchain consumers can verify by comparing the manifest's `creatorAddress` with `getToolConfig(toolId).creator` returned from the registry contract.

#### Consumer Verification

When resolving a tool, consumers MUST perform the following checks in order, and MUST reject the tool if any check fails:

1. Fetch the manifest from the onchain `metadataURI`.
2. Confirm that `metadataURI` lies on the endpoint's origin at the well-known path defined in §4. This includes URL normalization (§4), slug grammar (§4), and origin equality (§4); any failure of these sub-checks is a check-2 failure.
3. Confirm the fetched bytes are valid UTF-8 without a byte-order mark and that every JSON string value is in Unicode NFC form (see [Canonical Manifest Bytes](#canonical-manifest-bytes)). Canonicalize the manifest with JCS (RFC 8785) and verify that its `keccak256` equals the onchain `manifestHash`.
4. Verify that `manifest.creatorAddress`, lowercased, equals the onchain `creator`, lowercased.

A tool passing all four checks is canonically registered: the manifest came from the endpoint's origin, its bytes match the onchain commitment, and the onchain registrant is the party the origin operator nominated. A tool failing check 4 indicates that some account other than the address declared in the manifest has registered this URL; consumers MUST NOT treat such entries as legitimate registrations of the tool.

The following pseudocode specifies check 2 precisely. Given an onchain `metadataURI` and the manifest's `endpoint`:

```
function verifyOriginBinding(metadataURI, endpoint):
    // Normalize both URIs per §4 URL Normalization. In particular:
    // scheme and host are lowercased (§4 rule 1); the default HTTPS
    // port 443 is elided rather than materialized (§4 rule 2); no
    // trailing slash is appended (§4 rule 3); no query or fragment
    // is permitted on `metadataURI` (§4 rule 4); the host is the
    // A-label (ACE-encoded) form (§4 rule 6). Both sides MUST be
    // normalized under the same rules before comparison.
    metadataURI = normalize(metadataURI)
    endpoint    = normalize(endpoint)

    // §2 requires endpoint to be https:// after normalization.
    require endpoint.scheme == "https"

    // §4 requires metadataURI to be https:// with the well-known path.
    require metadataURI.scheme == "https"
    require metadataURI.query  == ""        // no "?"
    require metadataURI.fragment == ""      // no "#"

    // Origin equality per RFC 6454: scheme, host, port must all match.
    // After normalization, both `port` values are either the same
    // explicit non-default port or both absent (default-443 elided
    // on each side), so byte-equal comparison is sufficient.
    require metadataURI.scheme == endpoint.scheme
    require metadataURI.host   == endpoint.host
    require metadataURI.port   == endpoint.port

    // Path must be /.well-known/ai-tool/<slug>.json and the slug must
    // match the grammar in §4.
    require metadataURI.path starts with "/.well-known/ai-tool/"
    require metadataURI.path ends with ".json"
    slug = path segment between "/.well-known/ai-tool/" and ".json"
    require slug matches /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/
    require 1 <= len(slug) <= 64
```

If any `require` fails, check 2 fails and the tool MUST be treated as unverified.

#### Handling Verification Failure

A consumer that cannot complete all four checks (network error, 4xx/5xx, 3xx redirect, TLS error, truncated response, timeout, BOM-prefixed response, non-NFC Unicode, JCS/hash mismatch, creator mismatch, URL-normalization failure such as a query string or fragment on `metadataURI`, non-ACE IDN host, or non-`https` scheme, slug-grammar violation, origin mismatch between `metadataURI` and `endpoint`) MUST treat the tool as unverified. An unverified tool MUST NOT be invoked on behalf of a user and MUST NOT be presented to an agent as a discovered tool. In particular:

- Consumers MUST NOT follow HTTP redirects when fetching `metadataURI`. A 3xx response MUST be treated as a verification failure. This rule applies to HTTPS→HTTPS redirects as well: the onchain `metadataURI` is already required to be `https://` (see §4), so the only redirects a consumer would observe are same-scheme redirects that silently rewrite the path or origin and defeat the hash commitment. Operators that need to move a manifest update the onchain `metadataURI` via `updateToolMetadata`.
- Consumers MUST NOT fall back to "open access" when fetch fails.
- Consumers MUST NOT fall back to a previously-verified manifest beyond a freshness window of their choosing. Consumers SHOULD define an explicit window appropriate to the surface they power: latency-sensitive interactive UIs can tolerate minutes (RECOMMENDED default: no more than 5 minutes); high-value invocation paths (payments, signing flows) SHOULD re-verify on every use. For any consumer that may cause a tool to be invoked on a user's behalf (agent frameworks, wallets, invocation proxies, or any surface exposing a "run this tool" affordance), a freshness window MUST NOT exceed 24 hours; a cache older than that MUST be treated as expired and re-verified before use. The 24-hour ceiling bounds the stale-manifest exploitation window if an endpoint is compromised. Purely informational surfaces that never surface an invocation affordance (e.g., indexer digests, historical registries) MAY use longer windows, but MUST re-verify before transitioning a cached entry to any surface that could lead to invocation.
- Consumers MAY surface the failure to the user with the specific failing step, but MUST NOT auto-retry against a relaxed ruleset.

Indexers SHOULD expose a per-tool `verified` flag derived from all four checks, so downstream surfaces (wallets, agent frameworks) can filter to canonical registrations without re-implementing the verification themselves.

The registry contract cannot enforce check 4 because it has no access to HTTP resources. Enforcement lives in consumers (indexers, agent frameworks, wallets). A naive consumer that skips the check is vulnerable, so consumers SHOULD surface the mismatch explicitly rather than silently accepting such registrations.

### 6. Manifest Hash Commitment

The `manifestHash` field in `ToolConfig` commits the canonicalized manifest bytes (see [Canonical Manifest Bytes](#canonical-manifest-bytes)) onchain at registration time. Even though `metadataURI` is a mutable pointer, the hash provides an immutable snapshot. Any change forces an `updateToolMetadata` transaction and emits `ToolMetadataUpdated` with the new URI and hash. Consumers that pin a specific `manifestHash` are unaffected by future updates until they explicitly re-approve. Indexers can track manifest evolution via the emitted events without polling.

### 7. ERC-165 Support

Implementations MUST support [ERC-165](https://eips.ethereum.org/EIPS/eip-165). When queried via `supportsInterface(bytes4)`, the contract MUST return `true` for the `IToolRegistry` interface ID. The interface ID is computed as the XOR of all function selectors defined in the `IToolRegistry` interface above.

The interface IDs defined by this ERC are:

| Interface | Interface ID |
| --- | --- |
| `IToolRegistry` | `0x609466bf` |
| `IAccessPredicate` | `0xa11ea958` |

The `IToolRegistry` id is reproducible from the Foundry test suite shipped with the reference implementation (`type(IToolRegistry).interfaceId`), pinned as a regression check so the interface cannot drift without an accompanying spec update.

Implementations MUST NOT modify the `IToolRegistry` function set in a way that changes the interface ID; any such change constitutes a new interface and MUST be published under a new identifier.

Predicate contracts MAY implement ERC-165 to advertise their capabilities, but this is NOT REQUIRED.

## Rationale

### Why a Predicate Pointer Instead of an Access Mode Enum

A registry could enumerate known access modes (e.g., open, NFT-gated, subscription) and implement each one natively. This approach is simple but fundamentally closed: every new gating pattern (DAO vote, reputation score, cross-chain proof, time-locked access, composable AND/OR gates) requires a protocol upgrade. A single `address accessPredicate` pointer delegates all access logic to an external contract that anyone can write and deploy. This pattern is well-established in Ethereum:

- **Seaport zones** gate order fulfillment via an external zone contract.
- **Uniswap v4 hooks** gate pool operations via hook contracts.
- **ERC-4337 paymasters** gate gas sponsorship via paymaster contracts.

`address(0)` is the natural encoding for "no gating." Tools that are freely accessible set `accessPredicate` to the zero address and never interact with the predicate system.

### Why Access Control Is on the Registry (Not Separate)

Creators should have the power to decide who can access their tools directly from the registry. Splitting access control into a separate contract forces consumers to interact with two contracts for the most common operation (checking whether they can use a tool). Embedding an optional predicate pointer in the registry adds one field to `ToolConfig` and one view function. This is a minimal change that gives creators first-class control over access without fragmenting the consumer experience.

### Why Both `hasAccess` and `tryHasAccess`

A predicate call has three possible outcomes that are semantically distinct: "access granted," "access denied," and "the predicate call itself failed" (revert, out-of-gas, non-canonical ABI return, zero-code predicate). A single-return view conflates the last two into the same `false` result, which is safe (the registry never grants access when the predicate malfunctions) but lossy: a naive consumer cannot tell whether they need to publish a Merkle proof, obtain an NFT, or file a bug against a broken predicate.

`tryHasAccess` exposes the three outcomes as `(ok, granted)` so that wallets, discovery UIs, and agent frameworks can surface a predicate malfunction distinctly (e.g., "this tool is temporarily unavailable"). Keeping `hasAccess` as a single-bool convenience wrapper preserves compatibility with the simplest integration path: a contract or frontend that only needs "can I use this?" reads one return value and treats malfunctions and denials identically, which is the safe default. Consumers that want richer reporting opt in to `tryHasAccess` without any new interface to learn beyond the extra return value.

### Why No Dedicated Active/Inactive Flag

Pausing a tool is already expressible through the predicate pointer: a creator pauses by pointing `accessPredicate` at an always-deny predicate, and un-pauses by pointing it back at the previous predicate (or `address(0)` for open access). A dedicated boolean flag would duplicate that capability in a second storage slot and a second function, so the registry carries only the predicate pointer and keeps its focus on "who decides" rather than on a specific decision.

### Why Predicate Introspection Is (Mostly) Out of Scope

The `IAccessPredicate` interface is deliberately minimal: one gating method (`hasAccess`) and one diagnostic identifier (`name`). `name()` earns its place because it lets indexers, explorers, and agent frameworks display "this tool is gated by `ERC721OwnerPredicate`" without ABI introspection or an external lookup table — a small surface cost for a clear consumer-facing benefit. Beyond that, richer introspection (the shape of `data`, the configuration interface, the policy semantics) is intentionally deferred. An autonomous consumer that discovers a predicate at runtime still needs out-of-band documentation from the predicate author to construct a valid `data` argument, the same situation Seaport zone implementations and Uniswap v4 hooks live with today.

A companion ERC MAY specify a predicate-descriptor interface for richer metadata. Keeping that out of the core interface preserves the cheapest-possible-predicate goal (an open-access or trivial gate is still ten lines of Solidity) and lets the descriptor shape be designed against real usage rather than speculatively. Predicate-level metadata is also partially redundant with tool-level metadata: a tool's manifest already declares how its predicate is used, including any expected shape of `data`, and the manifest is canonical via origin-binding and `manifestHash`. A predicate that wants to self-describe today can publish documentation alongside its source code and reference it from the deployments that use it.

### Why Pricing Is in the Manifest (Not the Contract)

Pricing is a discovery concern, not an onchain enforcement concern. An agent comparing two tools that serve the same purpose needs to know cost *before* invocation. Without standardized pricing in the manifest, each payment ecosystem ([x402](https://www.x402.org/), [Machine Payments Protocol](https://mpp.dev/), direct ERC-20 transfer) would invent its own manifest extension, making cross-protocol comparison impossible.

The pricing schema is deliberately minimal and protocol-agnostic: four fields that answer "how much, of what asset, to whom, via what protocol." `asset` and `recipient` use [CAIP-19](https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-19.md) and [CAIP-10](https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-10.md) respectively, which collapses "chain plus asset" and "chain plus address" into one canonical field each and keeps non-EVM namespaces first-class. The `protocol` field is an opaque string so the ERC does not depend on any specific payment system. Agents iterate the `pricing` array and select the first entry whose `protocol` they support, similar to HTTP content negotiation.

Complex pricing models (variable pricing, subscriptions, tiered billing) are concerns of the endpoint, not the manifest. The manifest declares the simplest useful signal: "this tool costs X, paid in token Y, on chain Z, via protocol P."

### Why Origin-Binding Plus Creator Self-Attestation

Origin-binding ties a manifest's provenance to DNS/TLS ownership of its endpoint. An attacker cannot serve a manifest at `https://api.example.com` unless they control `api.example.com` and can place the document at `/.well-known/ai-tool/<slug>.json`. The slugged form lets a single origin host many tools without fanning out to subdomains, and a single-tool origin simply picks any compliant slug. Origin-binding is lightweight, requires no onchain trust registry, and works with any HTTPS endpoint.

Origin-binding alone, however, is not sufficient for canonical registration. Because `registerTool` is permissionless, any account can point a registration at a URL it does not control. An attacker who reads a legitimate creator's well-known URL can register that URL under the attacker's own address with a malicious predicate. Consumers fetching the manifest would see a genuine, origin-bound, hash-matching document, but access would be gated by the attacker's contract.

Creator self-attestation (§5) closes this. The manifest declares which address is entitled to appear as the onchain `creator`, and consumers reject any registration whose onchain `creator` does not match.

Only the origin operator can write bytes at the well-known path, and those bytes are committed onchain via `manifestHash`, so the origin operator is the only party that can nominate a creator address. The two mechanisms together define a canonical registration: the manifest came from the endpoint's origin, its bytes match the onchain hash, and its declared creator matches the onchain creator. Every surface (wallets, agents, indexers) applies this rule and reaches the same answer, so consumers agree on which registration is authoritative without a trusted directory.

Enforcement is kept offchain because the registry contract has no access to HTTP. Moving enforcement onchain would require either a signature scheme (raising the barrier for non-Ethereum-native creators and tooling) or a trusted oracle (contradicting the permissionless goal). The offchain check is one field comparison after the hash check that consumers already perform, so the marginal cost is negligible.

### Relationship to ERC-8004

[ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) defines onchain agent identity. This ERC defines onchain tool identity. The two compose naturally: an ERC-8004 agent's service list MAY reference tools from this registry, and a tool creator MAY be an ERC-8004 agent address. They are kept separate because agent identity and tool identity serve different purposes and have different lifecycles.

## Backwards Compatibility

This ERC introduces new interfaces (`IToolRegistry`, `IAccessPredicate`) and does not modify any existing standards. It composes with [ERC-165](https://eips.ethereum.org/EIPS/eip-165) for interface detection without requiring changes to ERC-165 or any other existing ERC.

Predicate contracts are fully independent: any contract that implements the `IAccessPredicate` interface can be used, including contracts that were deployed before this ERC was published, provided they conform to the function signature.

## Reference Implementation

A Foundry-based reference implementation of `ToolRegistry`, `IToolRegistry`, and `IAccessPredicate` is maintained alongside this ERC at [github.com/ProjectOpenSea/tool-registry](https://github.com/ProjectOpenSea/tool-registry). The reference implementation pins the ERC-165 interface id, enforces the manifest-URI length cap described in Security Considerations, and exercises the predicate integration path (ERC-165 validation, non-canonical bool rejection, zero-code predicate handling, gas-capped `staticcall`) through its test suite. Consumers and implementers SHOULD use it as a conformance baseline; any downstream implementation MUST reproduce the pinned interface id and the behavior validated by the test suite.

## Security Considerations

### Predicate Gas Consumption

The registry delegates access checks to an external predicate contract via `staticcall`. A malicious or poorly written predicate could consume unbounded gas, causing `hasAccess` calls to revert or become prohibitively expensive. Implementations SHOULD cap the gas forwarded to predicate calls (e.g., `staticcall{gas: 200_000}`) and treat out-of-gas as "access denied."

The reference implementation uses a 200,000 gas cap, chosen so that realistic predicate logic completes comfortably below it:

- An ERC-20 or ERC-721 `balanceOf` check plus a comparison runs in roughly 5,000-10,000 gas.
- Merkle proof verification over a depth-20 tree (supporting ~1,000,000 leaves) runs in roughly 40,000-60,000 gas using OpenZeppelin's `MerkleProof` library.
- An ECDSA signature verification (`ecrecover` plus constant work) runs in roughly 5,000-10,000 gas.

A 200,000 gas cap leaves headroom of at least 2-3× over the most expensive common case (Merkle proof verification), which keeps the happy path well below the cap while still bounding worst-case gas so that a malfunctioning predicate cannot turn `hasAccess` into an expensive storage-depleting call. Implementations that expect more elaborate predicates (e.g., zero-knowledge proof verification) MAY choose a larger cap; implementations that only expect trivial gates MAY choose a smaller one. In both cases the outcome of a capped `staticcall` is the same: on OOG the call reverts, and the registry treats the revert as "access denied" (or, via `tryHasAccess`, as `(ok=false, granted=false)`).

Predicate authors and callers also need to account for [EIP-150](https://eips.ethereum.org/EIPS/eip-150)'s 63/64 rule: a staticcall forwards at most `63/64` of the caller's remaining gas, so the gas the predicate actually receives is `min(cap, floor(63/64 * gasLeft))`. A caller that invokes `hasAccess` with too little remaining gas can therefore starve a predicate that would otherwise succeed, causing a spurious "access denied" result. Predicate authors SHOULD budget the common path well below the cap (a practical rule of thumb is to keep happy-path execution under half of the cap) so minor variations in caller gas do not flip the outcome. Contracts that invoke `hasAccess` onchain SHOULD ensure they enter the call with at least `cap * 64 / 63` gas available.

### Predicate Upgradeability

If the `accessPredicate` is a proxy contract (e.g., an ERC-1967 transparent proxy or UUPS proxy), the predicate owner can silently change the access logic without the tool creator calling `setAccessPredicate`. This means tool consumers cannot rely solely on the `AccessPredicateUpdated` event to detect changes in access semantics. Consumers SHOULD check whether a predicate address contains proxy patterns (e.g., ERC-1967 storage slots) and SHOULD treat upgradeable predicates as higher risk than immutable ones.

### Registry Deployment

The registry contract itself can be deployed behind a proxy. An admin with proxy-upgrade authority could then swap the implementation for one that lies about `hasAccess`, `getToolConfig`, or `toolCount`, or that emits spoofed events. Consumers verifying a predicate's bytecode while blindly trusting a registry address miss this exposure.

Consumers SHOULD apply the same rigor to registry addresses that they apply to predicates:

- Check that the registry's code does not expose ERC-1967 proxy markers. If it does, treat the registry as higher risk.
- Pin the expected bytecode hash (or the deployment transaction) for any registry treated as canonical.
- Publish and cross-check the canonical registry address per chain via a well-known directory (e.g., a pinned value in each discovery layer's configuration).

Discovery layers (indexers, agent frameworks, wallets) SHOULD publish the registry bytecode hash alongside the registry address so downstream surfaces can verify the deployment has not been swapped. A registry deployed directly (no proxy) with its source verified on the canonical block explorer is the RECOMMENDED configuration.

### Predicate Reverting

Implementations MUST treat a reverting predicate call as "access denied" from `hasAccess` rather than bubbling the revert to the caller; this prevents a malfunctioning predicate from breaking the registry's view functions. Consumers that need to distinguish a clean denial from a malfunction SHOULD use `tryHasAccess` instead, which reports the predicate outcome as `(ok, granted)`: a malfunction surfaces as `(false, false)` while a clean denial surfaces as `(true, false)`.

### Predicate Reentrancy

Although `hasAccess` is a `view` function, the predicate it delegates to is an external contract. Implementations MUST call the predicate via `staticcall`, which the EVM forbids from mutating state. State-mutating entrypoints on the registry make no external calls to the predicate at all, so the registry exposes no reentrancy surface. Contracts that invoke `hasAccess` as part of a larger transaction are still responsible for their own reentrancy guards against any other external calls they make, but cannot be reentered through the predicate path itself.

### Account Parameter Is Advisory

The `account` argument to `IAccessPredicate.hasAccess` and `IToolRegistry.hasAccess` is a claim the caller makes about who they are asking on behalf of. It is not authenticated by the registry and is not bound to `msg.sender`. Any caller can query the access status of any address.

Predicates and downstream enforcers (tool endpoints, wallets, agent frameworks, contracts that gate behavior on the result) MUST NOT treat a `true` return value as proof that the current requester is `account`. Enforcers MUST independently bind `account` to the real principal before acting on a positive answer, for example by:

- checking `account == msg.sender` when the predicate is consulted from within a transaction initiated by `account`,
- requiring the caller to present a signature over a challenge in `data`, verified by the predicate or the endpoint,
- issuing a short-lived session token after an out-of-band authentication step.

A predicate that gates purely on `account` (e.g., "is this address a holder of NFT X?") is safe to consult but unsafe to act on without such binding. Ignoring this distinction is the most common way that correct-looking access gates become unsound.

### Zero-Code Access Predicates

Implementations of `IToolRegistry.registerTool` and `IToolRegistry.setAccessPredicate` that perform ERC-165 validation SHOULD treat addresses with no deployed code (externally-owned accounts, or CREATE2 addresses that have not yet been deployed) as accepted but unverifiable. ERC-165 cannot be queried against empty code, so such a predicate cannot be checked at registration time.

At invocation time, a staticcall to a zero-code address returns empty data, which the registry MUST treat as non-compliant (see [§1 `hasAccess`](#itoolregistry-interface)) and therefore as "access denied." A tool registered with a zero-code predicate is consequently inaccessible until a contract is deployed at that address.

Creators who rely on counterfactual deployment (registering a predicate before deploying it) SHOULD:

1. Verify that the CREATE2 salt and init-code commit to the intended predicate bytecode before registration.
2. Deploy the predicate before announcing the tool to consumers.
3. Prefer registering the tool after the predicate is deployed when counterfactual deployment is not required. Consumers who observe a zero-code predicate SHOULD surface it as "not yet available" rather than "open access."

### Registry Self-Reference and Predicate Selector Collision

`IToolRegistry.hasAccess(uint256,address,bytes)` and `IAccessPredicate.hasAccess(uint256,address,bytes)` share the selector `0xa7e3775b`, because they have identical names and argument lists. Absent validation, a creator could set `accessPredicate` to the registry's own address and the registry would recursively staticcall itself on every `hasAccess` query, halving the gas budget at each frame (EIP-150's 63/64 rule) until the staticcall fails and the outer call returns `false` by the malfunction rules in §1. No state is corrupted, but every access check on that tool becomes a dead branch.

Implementations that perform registration-time ERC-165 validation (see Zero-Code Access Predicates) block this at registration because the registry does not advertise `IAccessPredicate`, so the second ERC-165 probe returns `false` and `registerTool` / `setAccessPredicate` reverts with `InvalidAccessPredicate`. Implementations that skip ERC-165 validation remain safe at the call site (the gas cap bounds the recursion and strict return-decoding treats an exhausted staticcall as `(ok=false, granted=false)`), but SHOULD add a `predicate != address(this)` guard to surface the misconfiguration explicitly rather than silently registering a tool that will never grant access.

### Front-Running Tool Registration

Tool IDs are auto-incrementing counters, so there is no onchain name-squatting vector at the identifier layer. An attacker who front-runs a `registerTool` transaction obtains a different tool ID pointing to their own manifest, which does not affect the victim's subsequent registration.

A distinct risk is URL-squatting: an attacker registers the legitimate creator's `metadataURI` and matching `manifestHash` under the attacker's own address, attaching a malicious `accessPredicate`. Origin-binding does not prevent this, because the attacker is merely referencing a URL that already exists at the real operator's origin. Creator binding (§5) closes this by requiring the manifest itself to declare the onchain address permitted to register it; a registration whose onchain `creator` does not match the manifest's `creatorAddress` MUST be rejected by consumers.

Manifest `name` collisions, where two independent creators pick the same human-readable name on different origins, are still resolved by the discovery layer (indexers, agent frameworks), not by the registry. Discovery layers SHOULD rank tools by origin-binding plus creator-binding verification rather than registration order.

### Metadata URI Mutability

The `metadataURI` field is mutable: a tool creator can call `updateToolMetadata` to point to a new manifest at any time. However, the `manifestHash` commits the manifest bytes onchain. Consumers that pin a `manifestHash` can detect changes. The `ToolMetadataUpdated` event emits the new URI and hash, so indexers and consumers are notified of every change. Consumers SHOULD re-verify the manifest hash after fetching from a URI and SHOULD alert users when a previously pinned hash no longer matches.

### Pricing Staleness

Pricing lives in the manifest and is not committed anywhere that the endpoint is obligated to honor. A creator can rotate pricing at any time by publishing a new manifest and calling `updateToolMetadata` with the new hash. Agents that cached a manifest during discovery SHOULD re-fetch pricing close to invocation, and SHOULD be resilient to the endpoint returning a payment-required response whose amount differs from the cached manifest. Agents SHOULD NOT pre-approve payment amounts that assume the discovery-time manifest is authoritative beyond a short freshness window.

### Malicious Endpoints

Tool endpoints are creator-controlled URLs. The `endpoint` field MUST be an `https://` URL (see §2); consumers MUST reject manifests whose `endpoint` uses any other scheme. Consumers SHOULD reject endpoints that resolve to private IP ranges (RFC 1918, RFC 6598, loopback, link-local) to prevent SSRF attacks. Agent frameworks that invoke tool endpoints SHOULD enforce request timeouts and response size limits.

### Manifest Parser Hardening

A creator controls the bytes served at `metadataURI`, and a permissionless registration makes every fetched manifest effectively attacker-controlled. A consumer that parses without limits can be DoSed by a single malicious registration. Consumers MUST enforce the following ceilings and MUST reject any manifest that exceeds them:

| Limit | Value | Why |
| --- | --- | --- |
| Manifest byte size | 1 MiB (1,048,576 bytes) | Bounds HTTP body and parser memory; a fully-populated honest manifest with ten pricing entries and a moderately rich schema is well under 10 KiB. Consumers MUST truncate at the limit and treat oversize fetches as a verification failure. |
| `pricing.length` | 32 entries | Multi-chain, multi-protocol pricing still fits comfortably; prevents quadratic iteration in agent selection. |
| `inputs` / `outputs` schema depth | 16 levels | Deep enough for any real JSON Schema composition (`anyOf` of tagged unions, nested objects); prevents stack exhaustion in recursive validators. |
| `inputs` + `outputs` total schema nodes | 1,024 nodes | Covers rich schemas; prevents pathological fan-out attacks that create millions of subschemas via shallow-but-wide structures. |

Regex `pattern` values inside embedded schemas MUST be evaluated by a matcher immune to catastrophic backtracking (e.g., RE2, or an implementation with a bounded step count). A matcher with exponential worst-case behavior on attacker input is unsafe and MUST NOT be used.

Consumers SHOULD inspect the HTTP `Content-Length` response header, if present, and abort the request before reading the body when the advertised length exceeds 1 MiB. Streaming consumers that cannot rely on `Content-Length` SHOULD cap the incremental read at 1 MiB and abort (without silently truncating) on overflow, so an attacker cannot force the consumer to load a multi-megabyte payload into memory before the size check engages.

These limits are deliberately generous for honest tools and tight enough to make DoS-via-registration uneconomic.

### Remote `$ref` in Embedded Schemas

JSON Schema permits `$ref` to point at remote URIs. A creator-authored `inputs` or `outputs` schema that references `http://169.254.169.254/…`, private IP ranges, or attacker-owned URLs can turn every validator into an SSRF / fingerprinting oracle. Consumers MUST disable remote `$ref` resolution when validating against manifest-embedded schemas, or MUST sandbox any resolution behind the same egress policy applied to `endpoint` (no private IPs, HTTPS only, size-capped fetches, short timeouts). Local `$ref` (within the same schema document) remains safe and MAY be resolved.

### Rendering Manifest Content

Every string and URL in a fetched manifest is creator-controlled and MUST be treated as untrusted input by any surface that renders it. Consumers MUST apply defense-in-depth: validation at fetch time, contextual encoding at render time, and a restrictive Content Security Policy in the surrounding document.

The following normative rules apply to common render paths:

- **Text fields (`name`, `description`, `tags`).** Consumers MUST contextually encode these fields when rendering: HTML-escape for text nodes, attribute-escape for attributes, and JS-escape for script contexts. UIs that inject them into the DOM without encoding are vulnerable to stored XSS from a single malicious registration.
- **Markdown rendering of `description`.** Consumers that render Markdown MUST disable raw-HTML passthrough or sandbox the rendered output. A compliant Markdown renderer strips `<script>`, `<iframe>`, event handlers, and `javascript:` URLs, or runs under a CSP that neutralizes these surfaces.
- **`image` URIs.** Consumers MUST NOT accept `javascript:`, `file:`, `data:text/html`, or `vbscript:` URIs for a tool icon: these schemes enable script execution or local-filesystem exposure and have no legitimate icon use case. Consumers SHOULD NOT accept `http:` (MITM risk) or `blob:` (cross-context leakage risk) URIs; consumers that do accept either MUST apply the scheme-appropriate defenses in the Per-Scheme Rendering Guidance below.
- **`endpoint` and extension-namespaced URL fields as clickable links.** Consumers SHOULD NOT render `javascript:`, `file:`, or `blob:` schemes as links; `http:` links are permitted only with explicit user consent because of MITM risk; all external links SHOULD carry `rel="noopener noreferrer"` to prevent tab-nabbing.

#### Non-Normative: Per-Scheme Rendering Guidance for `image`

For any scheme consumers do accept, scheme-appropriate defenses should be layered on the normative rules above:

- `https://`: set `referrerpolicy="no-referrer"` and proxy through consumer-controlled infrastructure where feasible.
- `ipfs://`: resolve through a trusted gateway the consumer operates, not an arbitrary public gateway. A hostile gateway can inject response headers, set tracking cookies, or serve manipulated content even when the CID is content-addressed.
- `data:image/svg+xml`: reject outright, or render only inside a script-free sandbox (e.g., inside an `<img>` element rather than inline SVG, or an `<iframe sandbox="">`). SVG can embed `<script>` tags.
- `data:` (other): verify the declared MIME type against an allowlist of image types (e.g., `image/png`, `image/jpeg`, `image/webp`) before rendering.

### Origin-Binding Limitations

Origin-binding relies on DNS and TLS infrastructure. It is vulnerable to DNS hijacking, BGP attacks, and compromised certificate authorities. These are industry-wide risks, not specific to this ERC. Tools hosted exclusively on IPFS or other content-addressed networks cannot use origin-binding because there is no HTTP origin to bind to; consumers SHOULD treat such tools with reduced confidence compared to origin-bound tools.

Origin-binding also does not defend against internationalized-domain homograph attacks. Two ACE-encoded hostnames that differ at the byte level (e.g., `xn--...` of a Cyrillic string versus the Latin lookalike) produce different `metadataURI` values and are correctly distinguished by the well-known fetch, but a user comparing the two hostnames visually in a UI may not notice the substitution. Consumers rendering manifest origins to end-users SHOULD apply IDN display policies such as [UTS #39](https://www.unicode.org/reports/tr39/) restriction levels and SHOULD surface punycode for mixed-script or confusable hostnames so users have a chance to spot impersonation.

### Creator Key Compromise

If a tool creator's private key is compromised, an attacker can update the manifest URI or change the access predicate. This ERC does not include ownership transfer or multi-sig mechanisms on the registry itself, in order to keep the interface minimal: every such feature (two-step transfer, role-based access control, time-locks) is already expressible by registering the tool under a smart contract wallet and implementing the desired policy there.

Creators SHOULD therefore register tools under a smart contract wallet (e.g., Safe, an ERC-4337 account, a custom multisig) rather than an externally-owned account whenever the tool's access predicate is gating anything valuable. The registry treats `msg.sender` uniformly: any contract that can produce a valid Solidity call to `registerTool`, `updateToolMetadata`, or `setAccessPredicate` can act as a creator, so all existing wallet tooling (timelocks, guardians, key rotation modules) composes directly. Creators who register under an EOA accept that key compromise is unrecoverable at the registry layer and SHOULD re-register the tool under a fresh ID if a compromise occurs.

A contract-wallet creator whose authorization logic later becomes unreachable (self-destructed wallet, migration to a new address without state preservation, signer set that can no longer meet the wallet's threshold) leaves the registration frozen in its last-written state: the registry continues to report a valid `ToolConfig`, but no future `updateToolMetadata` or `setAccessPredicate` call from that creator can succeed. Creators who treat mutability as a precondition for safe operation (pause via predicate swap, URL rotation) SHOULD keep their wallet's recovery paths exercised; creators who prefer commitment-style immutability MAY treat the freeze as a feature. Consumers SHOULD NOT infer abandonment from staleness alone, because frozen-but-canonical and actively-maintained registrations look identical from onchain state.

## Appendix: Reference Test Vectors

This appendix pins reference values so that implementations can be checked byte-for-byte against a known-good producer. Vectors are generated by [`scripts/generate-test-vectors.ts`](https://github.com/ProjectOpenSea/tool-registry/blob/main/scripts/generate-test-vectors.ts) in the [companion repository](https://github.com/ProjectOpenSea/tool-registry); any conformant JCS (RFC 8785) + keccak256 pipeline MUST reproduce the hashes below when fed the listed manifests.

The reference generator was exercised against [`canonicalize@2.1.0`](https://www.npmjs.com/package/canonicalize/v/2.1.0) and [`@noble/hashes@2.0.1`](https://www.npmjs.com/package/@noble/hashes/v/2.0.1) on Node.js 20. Any RFC 8785 conformant implementation MUST produce the same output; these specific versions are named only to make the reference-generator lockfile reproducible.

All `keccak256` values are 32-byte outputs shown as `0x`-prefixed lowercase hex.

### Free-Tool Manifest

Semantic input (identical to the "Free Tool" example in §2):

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#tool-manifest-v1",
  "name": "nft-price-oracle",
  "description": "Returns estimated floor price for any NFT collection.",
  "endpoint": "https://tools.example.com/nft-price-oracle",
  "inputs": {
    "type": "object",
    "properties": {
      "collection": { "type": "string", "description": "Contract address" },
      "chainId": { "type": "integer" }
    },
    "required": ["collection", "chainId"]
  },
  "outputs": {
    "type": "object",
    "properties": {
      "floorPriceEth": { "type": "string" },
      "updatedAt": { "type": "string", "format": "date-time" }
    }
  },
  "version": "1.0.0",
  "tags": ["nft", "pricing", "oracle"],
  "creatorAddress": "0xabcdefabcdef1234567890abcdefabcdef123456"
}
```

JCS canonical bytes (UTF-8, 632 bytes, whitespace-free on a single line in the wire representation; rendered here without wrapping):

```
{"creatorAddress":"0xabcdefabcdef1234567890abcdefabcdef123456","description":"Returns estimated floor price for any NFT collection.","endpoint":"https://tools.example.com/nft-price-oracle","inputs":{"properties":{"chainId":{"type":"integer"},"collection":{"description":"Contract address","type":"string"}},"required":["collection","chainId"],"type":"object"},"name":"nft-price-oracle","outputs":{"properties":{"floorPriceEth":{"type":"string"},"updatedAt":{"format":"date-time","type":"string"}},"type":"object"},"tags":["nft","pricing","oracle"],"type":"https://eips.ethereum.org/EIPS/eip-XXXX#tool-manifest-v1","version":"1.0.0"}
```

- `manifestHash` = `0x85f160012d9fd30c7e82bc9d3959c90ec9df3c7d69009a343d8ee01904321290`

Matching `ToolConfig` (registered on `eip155:8453` at registry `0xaaaa…aaaa` as tool ID `1`):

```
ToolConfig {
    creator:         0xabcdefabcdef1234567890abcdefabcdef123456,
    metadataURI:     "https://tools.example.com/.well-known/ai-tool/nft-price-oracle.json",
    manifestHash:    0x85f160012d9fd30c7e82bc9d3959c90ec9df3c7d69009a343d8ee01904321290,
    accessPredicate: 0x0000000000000000000000000000000000000000
}
```

Canonical CAIP-19 tool reference: `eip155:8453/erc-xxxx:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/1`.

### Paid-Tool Manifest

Semantic input (identical to the "Paid Tool" example in §2):

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#tool-manifest-v1",
  "name": "premium-analytics",
  "description": "Advanced portfolio analytics for NFT holders.",
  "endpoint": "https://tools.example.com/premium-analytics",
  "inputs": {
    "type": "object",
    "properties": {
      "wallet": { "type": "string", "description": "Wallet address to analyze" }
    },
    "required": ["wallet"]
  },
  "outputs": {
    "type": "object",
    "properties": {
      "totalValue": { "type": "string" },
      "breakdown": { "type": "array" }
    }
  },
  "version": "1.0.0",
  "tags": ["analytics", "portfolio"],
  "pricing": [
    {
      "amount": "20000",
      "asset": "eip155:8453/erc20:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      "recipient": "eip155:8453:0xabcdef0123456789abcdef0123456789abcdef01",
      "protocol": "x402"
    },
    {
      "amount": "20000",
      "asset": "eip155:1/erc20:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      "recipient": "eip155:1:0xabcdef0123456789abcdef0123456789abcdef01",
      "protocol": "x402"
    }
  ],
  "creatorAddress": "0xabcdef0123456789abcdef0123456789abcdef01"
}
```

JCS canonical bytes (UTF-8, 922 bytes):

```
{"creatorAddress":"0xabcdef0123456789abcdef0123456789abcdef01","description":"Advanced portfolio analytics for NFT holders.","endpoint":"https://tools.example.com/premium-analytics","inputs":{"properties":{"wallet":{"description":"Wallet address to analyze","type":"string"}},"required":["wallet"],"type":"object"},"name":"premium-analytics","outputs":{"properties":{"breakdown":{"type":"array"},"totalValue":{"type":"string"}},"type":"object"},"pricing":[{"amount":"20000","asset":"eip155:8453/erc20:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913","protocol":"x402","recipient":"eip155:8453:0xabcdef0123456789abcdef0123456789abcdef01"},{"amount":"20000","asset":"eip155:1/erc20:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48","protocol":"x402","recipient":"eip155:1:0xabcdef0123456789abcdef0123456789abcdef01"}],"tags":["analytics","portfolio"],"type":"https://eips.ethereum.org/EIPS/eip-XXXX#tool-manifest-v1","version":"1.0.0"}
```

- `manifestHash` = `0xf5c2253fa557ef61e7b91fdfb3613c5a14acf6f986193a40aeb0b481dc6cbac3`

Matching `ToolConfig` (registered on `eip155:8453` at the same registry `0xaaaa…aaaa` as tool ID `2`, gated by predicate `0xbbbb…bbbb`):

```
ToolConfig {
    creator:         0xabcdef0123456789abcdef0123456789abcdef01,
    metadataURI:     "https://tools.example.com/.well-known/ai-tool/premium-analytics.json",
    manifestHash:    0xf5c2253fa557ef61e7b91fdfb3613c5a14acf6f986193a40aeb0b481dc6cbac3,
    accessPredicate: 0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
}
```

### NFC vs NFD Divergence

The two manifests below differ only in the Unicode form of the `name` field. Both look identical when rendered; both hash to different values, which is the exact failure mode the NFC rule in §2 is designed to prevent.

- NFC form: `name = "café-oracle"` with `é` as a single code point `U+00E9` (11 code points total).
  - Canonical byte length: 263.
  - `keccak256` = `0x1373e978af0e6c0e63f97c08d1b17ceaa0ffc2bb23508d740203eb71bae1a2db`.
- NFD form: `name = "café-oracle"` with `é` decomposed to `e` + combining acute `U+0301` (12 code points total).
  - Canonical byte length: 264.
  - `keccak256` = `0x9c00eb2ea9266c6c57f24db188cb1d48a419cda33ce566eb22230dd10c679b7d`.

The ERC requires the NFC form. A consumer that fetches the NFD form MUST reject it as a verification failure rather than silently re-normalizing, because silent re-normalization would change the bytes fed to `keccak256` and defeat the hash commitment.

### BOM vs No-BOM Divergence

Given a single canonical manifest (a minimal sample with `name = "bom-sample"`), the server-side encoding choice of whether to prefix the UTF-8 byte-order mark `EF BB BF` changes the hash:

- Without BOM: length `268` bytes, `keccak256` = `0x0c14a64a872b22356ab3d411017c8701e80b135c790706d710ac6f7cbde27e8b`.
- With BOM: length `271` bytes (= `268 + 3`), `keccak256` = `0x6ef38afe9c3b31c7200e392b8bcc098fa36645c20b9d58f1c910e4e858b99f6f`.

The ERC requires serving without a BOM. A consumer that receives an `EF BB BF`-prefixed response MUST treat it as a verification failure rather than silently stripping the prefix, because silent stripping would change the bytes fed to `keccak256`.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
