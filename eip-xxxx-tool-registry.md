---
eip: XXXX
title: Agent Tool Registry
description: Onchain registry for AI agent tools, with open, NFT-gated, and subscription access modes
author: Cody Sears (@CodySearsOS), Ryan Ghods (@ryanio)
discussions-to: https://ethereum-magicians.org/t/eip-xxxx-agent-tool-registry/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2026-04-13
requires: 165, 712, 721, 1155, 5643
---

## Abstract

This ERC specifies an onchain registry for AI agent tools and three onchain access modes layered on top of it. Any account may register a tool, and each registered tool declares one of three access modes: **open**, **NFT-gated** (ERC-721/ERC-1155, with optional cross-chain collections attested via gateway-signed [EIP-712](https://eips.ethereum.org/EIPS/eip-712)), or **subscription** ([ERC-5643](https://eips.ethereum.org/EIPS/eip-5643)). A standardized JSON manifest, committed by content hash, describes the tool's endpoint, I/O schemas, and accepted payments. Payment flows directly to the recipient via the chosen protocol; fee splits and platform economics are deliberately out of scope.

## Motivation

**Discovery is fragmented.** AI agent tools are scattered across proprietary catalogs with no uniform onchain source of truth.

**Onchain access control does not exist.** Creators who want to restrict tool invocation to specific holders or subscribers fall back on offchain, per-creator mechanisms.

This ERC provides a permissionless onchain registry with three first-class access modes (open, NFT-gated, subscription), including cross-chain NFT gating.

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “NOT RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### 1. Tool Identity Registry

#### Types

```solidity
/// @notice Access control mode for a registered tool.
enum AccessMode {
    /// Open access: anyone can invoke. Tool may be free or paid
    /// (pricing is declared in the Tool Manifest, not onchain).
    OPEN,
    /// Caller must hold a token from a bound NFT collection.
    NFT_GATED,
    /// Caller must hold an active ERC-5643 subscription NFT.
    SUBSCRIPTION
}

/// @notice Onchain configuration for a registered tool.
struct ToolConfig {
    address creator;          // Address that registered the tool
    string metadataURI;       // Resolves to Tool Manifest (JSON)
    bytes32 manifestHash;     // keccak256 of the canonical manifest bytes served at metadataURI
    AccessMode accessMode;    // OPEN, NFT_GATED, or SUBSCRIPTION
    bool active;              // Whether the tool is currently active
}
```

#### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IToolRegistry
/// @notice Onchain registry for AI agent tools.
/// @dev ERC-165 interface ID: 0x1d6a0290
interface IToolRegistry /* is IERC165 */ {

    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a new tool is registered.
    event ToolRegistered(uint256 indexed toolId, address indexed creator, AccessMode accessMode, bytes32 manifestHash);

    /// @notice Emitted when a tool's metadata URI and/or manifest hash is updated.
    /// @dev Emits both the prior and new URI and hash so indexers and gateways can
    ///      diff and commit to the new manifest without racing the creator. A pinned
    ///      `manifestHash` is the only binding commitment; `metadataURI` alone is
    ///      mutable pointer state. Consumers SHOULD pin by `manifestHash` for repeat
    ///      invocations.
    event ToolMetadataUpdated(uint256 indexed toolId, string oldURI, string newURI, bytes32 oldHash, bytes32 newHash);

    /// @notice Emitted when a tool is deactivated.
    event ToolDeactivated(uint256 indexed toolId);

    /// @notice Emitted when a tool is reactivated.
    event ToolReactivated(uint256 indexed toolId);

    // ──────────────────── Errors ────────────────────

    /// @notice The specified tool ID does not exist.
    error ToolNotFound(uint256 toolId);

    /// @notice Caller is not the tool's creator.
    error NotToolCreator(uint256 toolId, address caller);

    /// @notice The tool is already in the requested active state.
    error ToolAlreadyActive(uint256 toolId);

    /// @notice The tool is already in the requested inactive state.
    error ToolAlreadyInactive(uint256 toolId);

    /// @notice The provided metadata URI is invalid.
    /// @dev Implementations MUST revert with this error when `metadataURI` is
    ///      the empty string. Implementations MAY additionally reject URIs that
    ///      fail implementation-specific validation (e.g., length caps).
    error InvalidMetadataURI();

    /// @notice The provided manifest hash is `bytes32(0)`.
    /// @dev `keccak256` of any real content cannot produce `bytes32(0)`, so
    ///      a zero hash is semantically meaningless as a commitment.
    error InvalidManifestHash();

    // ──────────────────── Registration ────────────────────

    /// @notice Register a new tool.
    /// @dev The tool's `creator` is set to `msg.sender` and cannot be changed.
    ///      `manifestHash` is `keccak256` over the canonical manifest bytes
    ///      served at `metadataURI`. Gateways and agents SHOULD reject manifests
    ///      whose `keccak256` does not match the onchain hash; verification is
    ///      the only mechanism that makes the onchain commitment binding.
    ///      Implementations MUST revert with `InvalidManifestHash` if
    ///      `manifestHash` is `bytes32(0)`, since `keccak256` of any real
    ///      content cannot produce that value. Implementations MUST revert with
    ///      `InvalidMetadataURI` if `metadataURI` is the empty string.
    /// @param metadataURI  URI that resolves to the Tool Manifest.
    /// @param manifestHash keccak256 of the canonical manifest bytes.
    /// @param accessMode   Access control mode (OPEN, NFT_GATED, or SUBSCRIPTION).
    /// @return toolId      The unique identifier assigned to the tool.
    function registerTool(string calldata metadataURI, bytes32 manifestHash, AccessMode accessMode)
        external
        returns (uint256 toolId);

    // ──────────────────── Metadata ────────────────────

    /// @notice Update a tool's metadata URI and manifest hash. Creator only.
    /// @dev The `manifestHash` MUST be updated atomically with the URI. Consumers
    ///      that pinned a previous `manifestHash` are unaffected by the update;
    ///      they continue to use the pinned manifest until they explicitly opt
    ///      into the new hash. Implementations MUST revert with
    ///      `InvalidManifestHash` if `newHash` is `bytes32(0)`, and with
    ///      `InvalidMetadataURI` if `newURI` is the empty string.
    /// @param toolId  The tool to update.
    /// @param newURI  The new metadata URI.
    /// @param newHash keccak256 of the canonical manifest bytes served at `newURI`.
    function updateToolMetadata(uint256 toolId, string calldata newURI, bytes32 newHash) external;

    // ──────────────────── Lifecycle ────────────────────

    /// @notice Deactivate a tool. Creator only.
    function deactivateTool(uint256 toolId) external;

    /// @notice Reactivate a previously deactivated tool. Creator only.
    function reactivateTool(uint256 toolId) external;

    // ──────────────────── Views ────────────────────

    /// @notice Get the full configuration for a tool.
    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory);

    /// @notice Check whether an account has access to invoke a tool.
    /// @dev If the tool is not `active`, MUST return `false` regardless of mode.
    ///      For OPEN tools, MUST return `true` for any account when active.
    ///      For NFT_GATED tools, MUST return `true` iff `account` holds a token
    ///      from ANY bound collection (see `IToolAccessRegistry`).
    ///      For SUBSCRIPTION tools, this function MUST return `false`
    ///      unconditionally. SUBSCRIPTION access cannot be determined from
    ///      `balanceOf` alone because the caller's specific `tokenId` is
    ///      required to check `IERC5643.expiresAt`. Consumers MUST use
    ///      `IToolAccessRegistry.hasAccessWithProof` for SUBSCRIPTION tools.
    function hasAccess(uint256 toolId, address account) external view returns (bool);

    /// @notice Get the total number of registered tools, including deactivated ones.
    /// @dev Tool IDs are assigned sequentially starting from 1. Implementations
    ///      MUST NOT decrement or reuse tool IDs when tools are deactivated, so
    ///      `toolCount()` equals the highest assigned tool ID. Callers SHOULD use
    ///      `getToolConfig(toolId).active` to filter active tools during pagination.
    function toolCount() external view returns (uint256);
}
```

#### Tool ID Scope

Tool IDs are scoped to the `(chainId, registryAddress)` tuple. Two independent deployments of this registry (on the same or different chains) MAY assign tool ID `42` to unrelated tools. Offchain consumers (indexers, wallets, agent frameworks) MUST qualify tool references with the deploying chain ID and registry address. The RECOMMENDED canonical identifier format follows CAIP-19: `eip155:<chainId>/erc-xxxx:<registryAddress>/<toolId>`.

### 2. Tool Manifest

The `metadataURI` in `ToolConfig` MUST resolve to a JSON document conforming to the schema below. Gateways SHOULD validate that the `type` field matches a known schema version identifier and SHOULD reject manifests with an unknown or missing `type`. This prevents silent schema drift and ensures that future schema revisions can be introduced without breaking existing tools.

#### Required Fields

| Field | Type | Description |
| --- | --- | --- |
| `type` | string | Schema version identifier (e.g., `https://eips.ethereum.org/EIPS/eip-XXXX#registration-v1`) |
| `name` | string | Tool name (lowercase alphanumeric + hyphens, 1-64 chars) |
| `version` | string | Semantic version (e.g., `1.0.0`) |
| `description` | string | Human-readable description (1-500 chars) |
| `endpoint` | string | Creator-hosted HTTPS URL |
| `inputs` | object | JSON Schema defining tool input parameters |
| `outputs` | object | JSON Schema defining tool output parameters |
| `access` | object | Access mode configuration (see below) |

#### Optional Fields

| Field | Type | Description |
| --- | --- | --- |
| `image` | string | Tool icon URL |
| `pricing` | object | Payment configuration (see below) |
| `timeoutSeconds` | integer | Maximum execution time (1-300, default 30) |
| `gracePeriodSeconds` | integer | Subscription grace period (0-86400, default 0); see [Subscription Expiration Race Conditions](#subscription-expiration-race-conditions) |
| `tags` | array | Discovery tags (lowercase alphanumeric + hyphens) |
| `services` | array | Compatible with ERC-8004 services array |
| `registrations` | array | Onchain registration references |

#### Pricing Object

When present, the `pricing` object describes the tool's payment model and the set of payment options the creator will accept. The top-level object names the model (`per-invocation` or `subscription`) and, for subscriptions, the billing period. It also carries an `accepts` array: each element is one acceptable payment option, specifying token, chain, recipient, amount (or `maxAmount`, or `subscriptionAmount`), and payment protocols. A consumer or gateway MAY choose any element of `accepts` whose chain and protocol it supports.

All amounts MUST be in the token's smallest unit (raw `uint256`; e.g., 0.02 USDC = `"20000"`). Each `token` field MUST be the ERC-20 contract address on the specified chain, or the zero address for native currency. Each `chainId` field MUST be the [EIP-155](https://eips.ethereum.org/EIPS/eip-155) chain ID.

The `recipient` field on each accept option is the address to which that option's payment protocol MUST route funds. It MAY be a creator-owned EOA, a splitter contract, a DAO treasury router, or a platform-provided fee-taking splitter that forwards to the creator after retaining a listing fee. For `subscription` models, the `recipient` MAY be the subscription collection itself (or a mint/renew facade) so that payment and entitlement issuance happen atomically; see [Subscription Acquisition Flow](#subscription-acquisition-flow). This ERC does not specify fee splits, withdrawal mechanics, or platform economics. Those are properties of whatever contract sits at `recipient`. Because the entire `pricing` object (including every `recipient` in `accepts`) is committed by `manifestHash`, consumers that pinned a prior manifest continue paying the pinned addresses; changes emit `ToolMetadataUpdated` and are visible to indexers.

**Per-invocation pricing (fixed cost, single option):**

```json
{
  "model": "per-invocation",
  "accepts": [
    {
      "amount": "20000",
      "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      "chainId": 8453,
      "recipient": "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01",
      "protocols": ["x402"]
    }
  ]
}
```

**Per-invocation pricing (multi-chain, mixed fixed and variable):**

```json
{
  "model": "per-invocation",
  "accepts": [
    {
      "amount": "20000",
      "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      "chainId": 8453,
      "recipient": "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01",
      "protocols": ["x402"]
    },
    {
      "maxAmount": "500000",
      "token": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "chainId": 1,
      "recipient": "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01",
      "protocols": ["x402", "mpp"]
    }
  ]
}
```

Each accept option MUST specify exactly one of `amount` (fixed) or `maxAmount` (variable). Gateways interpret the choice according to the selected payment protocol (for example, `x402` uses `exact` scheme semantics for `amount` and `upto` semantics for `maxAmount`).

**Subscription pricing:**

```json
{
  "model": "subscription",
  "billingPeriod": "monthly",
  "accepts": [
    {
      "subscriptionAmount": "10000000",
      "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      "chainId": 8453,
      "recipient": "0x1111111111111111111111111111111111111111",
      "protocols": ["erc20-transfer"]
    }
  ]
}
```

Subscription access is gated onchain via [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643). The NFT's `expiresAt()` determines whether access is active. `billingPeriod` is declared once at the top level because it governs the subscription entitlement clock, which is a single tool-wide property regardless of which accept option a subscriber used to pay.

#### Pricing Fields

**Top-level fields:**

| Field | Type | Description |
| --- | --- | --- |
| `model` | string | `"per-invocation"` or `"subscription"` |
| `billingPeriod` | string | `"daily"`, `"weekly"`, `"monthly"`, or `"yearly"`. REQUIRED when `model` is `"subscription"`; MUST be omitted otherwise |
| `accepts` | array | Non-empty list of payment options the creator will accept (see per-option fields below) |

**Per-option fields (each element of `accepts`):**

| Field | Type | Description |
| --- | --- | --- |
| `amount` | string | Fixed cost per invocation in raw token units (per-invocation only; mutually exclusive with `maxAmount`) |
| `maxAmount` | string | Maximum variable cost in raw token units (per-invocation only; mutually exclusive with `amount`) |
| `subscriptionAmount` | string | Subscription cost per billing period in raw token units (subscription only) |
| `token` | string | ERC-20 token contract address (zero address for native currency) |
| `chainId` | integer | [EIP-155](https://eips.ethereum.org/EIPS/eip-155) numeric chain ID |
| `recipient` | string | Address that receives payment for this option (EOA, splitter contract, platform splitter, etc.); MUST be present and MUST NOT be the zero address |
| `protocols` | array | Accepted payment protocol identifiers for this option (see below); MUST contain at least one entry |

Constraints:

- `accepts` MUST contain at least one option when `pricing` is present.
- Within a single option, exactly one of `amount`, `maxAmount`, or `subscriptionAmount` MUST be set, and it MUST be consistent with the top-level `model` (`amount`/`maxAmount` only when `model` is `per-invocation`; `subscriptionAmount` only when `model` is `subscription`).
- `recipient` MUST be present on every option and MUST NOT be the zero address. Gateways SHOULD reject manifests with any option missing or zeroing `recipient`.
- `protocols` MUST contain at least one entry on every option. Gateways SHOULD select an `(accepts entry, protocol)` pair they support. New protocol identifiers MAY be introduced without changes to this standard.
- When an option uses `maxAmount`, at least one `protocol` on that option MUST support variable (upto) pricing semantics. Pairing `maxAmount` with a protocol that only supports exact amounts (e.g., a plain `erc20-transfer`) is invalid: the gateway has no unambiguous way to interpret the cap. Gateways SHOULD reject any option that pairs `maxAmount` with no variable-pricing-capable protocol. The non-normative registry (below) marks each protocol with its supported modes.
- The pricing object is OPTIONAL; free tools omit it entirely.
- Two options MAY share the same `(chainId, token)` pair (for example, to offer the same price under two different protocols with distinct recipients). Consumers MUST NOT assume `(chainId, token)` uniqueness across `accepts`.

A non-normative registry of well-known protocol identifiers is maintained at [`docs/protocol-identifiers.md`](https://github.com/ProjectOpenSea/tool-registry/blob/main/docs/protocol-identifiers.md) in the reference implementation repository. At time of writing, the registry includes `x402` ([x402](https://github.com/coinbase/x402), HTTP 402 micropayments with `upto` support), `mpp` ([MPP](https://mpp.dev/), machine-to-machine payments), and `erc20-transfer` (direct ERC-20 transfer before invocation). Identifiers in the registry are informative; interoperability requires only that gateway and manifest agree on a shared string. Each entry in the registry also declares whether the protocol supports `exact`, `upto`, or both pricing modes, which determines its eligibility for `amount`- vs `maxAmount`-bearing options.

#### Billing Period Durations

The `billingPeriod` string is a fixed-length interval, measured in seconds from the subscription NFT's mint (or most recent renewal) timestamp. Manifests and gateways MUST treat it as a number of seconds, not a calendar unit:

| `billingPeriod` | Seconds | Equivalent |
| --- | --- | --- |
| `"daily"` | `86400` | 1 × 24 × 3600 |
| `"weekly"` | `604800` | 7 × 24 × 3600 |
| `"monthly"` | `2592000` | 30 × 24 × 3600 |
| `"yearly"` | `31536000` | 365 × 24 × 3600 |

`"monthly"` is pinned to 30 days and `"yearly"` to 365 days so that the onchain entitlement clock is unambiguous and leap-year/calendar behavior cannot desynchronize gateways and collections. Subscription NFT contracts implementing ERC-5643 MAY expose alternate renewal semantics internally, but the `expiresAt(tokenId)` value that gateways rely on MUST be consistent with the duration declared in the manifest.

#### Subscription Acquisition Flow

This ERC does not specify a mint/renew contract interface for subscription NFTs; any ERC-5643-compliant collection is acceptable. The following non-normative flow describes how a `subscription` manifest is typically realized end-to-end, so that implementers do not independently reinvent the handshake:

1. A consumer selects a subscription tool and reads its manifest. The `access` block names the bound collection; the `pricing.accepts` array names one or more `(chainId, token, amount, recipient, protocols)` options.
2. The consumer selects an accept option whose chain and protocol they support.
3. The consumer executes the payment against the selected option's `recipient`. For a subscription, the `recipient` SHOULD be a contract that, as part of receiving payment, mints or renews the ERC-5643 subscription NFT to the payer. This MAY be the subscription collection itself, a dedicated mint/renew facade, or a splitter that atomically triggers minting on the collection.
4. The consumer invokes the tool via a gateway. The gateway checks access via `IToolAccessRegistry.hasAccessWithProof(toolId, account, tokenId)`, passing the tokenId that was minted/renewed in step 3.

Because the coupling between payment and mint happens in the `recipient` contract (not in this registry), different deployments can use different entitlement mechanics (pull-based mint, off-chain relayer, 4337 paymaster flow, etc.) without any change to this standard.

#### Access Mode Variants

**Open** (anyone can invoke, free or paid):

```json
{ "mode": "open" }
```

**Existing collection (ERC-721)**:

```json
{
  "mode": "nft",
  "collection": "0xd9b78A2F1dAFc8Bb9c60961790d2beefEBEE56f4"
}
```

**Existing collection (ERC-1155 + token ID)**:

```json
{
  "mode": "nft",
  "collection": "0x1234...abcd",
  "tokenId": "42"
}
```

**Subscription** (time-limited access via ERC-5643):

```json
{
  "mode": "subscription",
  "collection": "0x1234...abcd"
}
```

The bound collection MUST implement `IERC5643`. The onchain access check is strict: `expiresAt(tokenId) > block.timestamp`. Gateways MAY extend the effective access window by the manifest-declared `gracePeriodSeconds` at the application layer; see [Subscription Expiration Race Conditions](#subscription-expiration-race-conditions). The onchain contract does not and cannot read the offchain manifest, so `gracePeriodSeconds` has no effect on the result of `hasAccessWithProof`. Subscription access does not declare a `billingPeriod` here; the top-level `pricing.billingPeriod` is the single source of truth for the entitlement clock.

#### Example: Paid Open Tool (Per-Invocation)

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#registration-v1",
  "name": "polymarket-alpha",
  "version": "1.0.0",
  "description": "Analyzes Polymarket prediction markets for trading signals",
  "image": "https://example.com/tool-icon.png",
  "endpoint": "https://my-tool.vercel.app",
  "inputs": {
    "type": "object",
    "properties": {
      "market_query": { "type": "string", "description": "What market to analyze" }
    },
    "required": ["market_query"]
  },
  "outputs": {
    "type": "object",
    "properties": {
      "analysis": { "type": "string" },
      "confidence": { "type": "number" }
    }
  },
  "pricing": {
    "model": "per-invocation",
    "accepts": [
      {
        "amount": "20000",
        "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        "chainId": 8453,
        "recipient": "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01",
        "protocols": ["x402"]
      }
    ]
  },
  "access": {
    "mode": "open"
  },
  "timeoutSeconds": 30,
  "tags": ["prediction-markets", "alpha", "trading"]
}
```

#### Example: Subscription Tool

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#registration-v1",
  "name": "premium-research-agent",
  "version": "2.1.0",
  "description": "Deep research tool with unlimited queries for subscribers",
  "endpoint": "https://research.example.com",
  "inputs": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Research question" },
      "depth": { "type": "string", "enum": ["quick", "standard", "deep"] }
    },
    "required": ["query"]
  },
  "outputs": {
    "type": "object",
    "properties": {
      "report": { "type": "string" },
      "sources": { "type": "array", "items": { "type": "string" } }
    }
  },
  "pricing": {
    "model": "subscription",
    "billingPeriod": "monthly",
    "accepts": [
      {
        "subscriptionAmount": "10000000",
        "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        "chainId": 8453,
        "recipient": "0x1111111111111111111111111111111111111111",
        "protocols": ["erc20-transfer"]
      }
    ]
  },
  "access": {
    "mode": "subscription",
    "collection": "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01"
  },
  "timeoutSeconds": 120,
  "gracePeriodSeconds": 3600,
  "tags": ["research", "deep-search", "premium"]
}
```

### 3. Tool Access Registry

The Tool Access Registry handles NFT-based access gating. A tool MAY be bound to multiple collections (up to `MAX_COLLECTIONS`). Access is granted if the user holds a token from **any** bound collection (OR logic). For `SUBSCRIPTION` tools, the held token MUST also have `expiresAt(tokenId) > block.timestamp`.

Access checks call external contracts (`balanceOf`, `ownerOf`, `expiresAt`) on each bound collection. Implementations MUST treat a reverting external call as "no balance" for that binding and continue iteration with the next binding; a single misbehaving collection (self-destructed code, non-conforming ABI, adversarial revert) MUST NOT DoS access checks for other bindings or bubble up as a revert to consumers. See [Revert Resilience for Bound Collections](#revert-resilience-for-bound-collections).

`SUBSCRIPTION` tools MUST bind only ERC-721 collections (which ERC-5643 extends). Binding an ERC-1155 collection to a `SUBSCRIPTION` tool is out of scope for this version of the standard: ERC-5643 defines `expiresAt(uint256 tokenId)` for ERC-721 tokens, and a per-`(owner, tokenId)` expiration semantic for semi-fungible tokens is not yet standardized. Implementations MUST revert in `addCollection` when a caller attempts to bind an `ERC1155` collection to a tool whose `accessMode` is `SUBSCRIPTION`.

#### Types

```solidity
/// @notice Token standard for collection bindings.
enum TokenStandard { ERC721, ERC1155 }

/// @notice Binding between a tool and an NFT collection that grants access.
/// @dev `tokenId` MUST be zero when `tokenStandard == ERC721`. ERC-721 uses
///      `balanceOf(account)` and ignores any tokenId at bind time; a non-zero
///      value would be dead state and is rejected in `addCollection`.
struct CollectionBinding {
    address collection;           // NFT contract address
    TokenStandard tokenStandard;  // ERC-721 or ERC-1155
    uint256 tokenId;              // ERC-1155 only; MUST be 0 for ERC-721
}
```

#### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IToolAccessRegistry
/// @notice NFT-based access gating for tools with payment-only passthrough.
/// @dev ERC-165 interface ID: 0x542e220b
interface IToolAccessRegistry /* is IERC165 */ {

    /// @notice Maximum number of collection bindings per tool.
    /// @dev Implementations MUST return exactly `20`. This value is pinned by the
    ///      standard so that interoperating contracts and indexers can assume a
    ///      bounded iteration cost for `hasAccess` (which performs an external
    ///      `balanceOf` call per binding) and `getCollections`. Implementations
    ///      MUST revert `addCollection` with `MaxCollectionsReached` once 20
    ///      bindings are present for a tool. Future revisions of this standard
    ///      MAY raise the cap; individual deployments MUST NOT.
    function MAX_COLLECTIONS() external view returns (uint256);

    // ──────────────────── Events ────────────────────

    event CollectionAdded(uint256 indexed toolId, address indexed collection, TokenStandard tokenStandard);
    event CollectionRemoved(uint256 indexed toolId, address indexed collection);

    // ──────────────────── Errors ────────────────────

    error MaxCollectionsReached(uint256 toolId);
    error CollectionNotFound(uint256 toolId, uint256 index);
    /// @notice The binding at `index` did not match the caller's expected collection.
    /// @dev Raised by `removeCollection` when the caller's `expectedCollection`
    ///      does not match the binding at `index` at the time the call lands.
    ///      This protects against races where concurrent removals shift indices.
    error CollectionMismatch(uint256 toolId, uint256 index, address expected, address actual);
    error InvalidCollection(address collection);
    error NotToolCreator(uint256 toolId, address caller);
    error UnsupportedStandardForSubscription(uint256 toolId, TokenStandard standard);

    // ──────────────────── Access Check ────────────────────

    /// @notice Check whether `account` has access to `toolId`.
    /// @dev If the tool is not `active`, MUST return `false` regardless of mode.
    ///      For OPEN tools, MUST return `true` when active.
    ///      For NFT_GATED tools, returns `true` if `account` holds a token from
    ///      ANY bound collection (OR logic, not AND).
    ///      ERC-721: checks `balanceOf(account) > 0` on the collection.
    ///      ERC-1155: checks `balanceOf(account, tokenId) > 0`.
    ///      Each external call MUST be revert-resilient: a reverting call on a
    ///      bound collection is treated as "no balance" for that binding, and
    ///      iteration continues. A single misbehaving binding MUST NOT DoS the
    ///      access check or bubble up as a revert to the caller.
    ///      For SUBSCRIPTION tools, this function MUST return `false`
    ///      unconditionally; `balanceOf` cannot disambiguate which `tokenId`
    ///      to check `expiresAt` on. Consumers MUST use `hasAccessWithProof`
    ///      for SUBSCRIPTION tools. This prevents a silent security failure
    ///      where expired subscriptions would pass a `balanceOf`-only check.
    ///      Argument order matches `IToolRegistry.hasAccess` so a single
    ///      contract MAY implement both interfaces with one function body.
    function hasAccess(uint256 toolId, address account) external view returns (bool);

    /// @notice Check access using a caller-supplied tokenId for SUBSCRIPTION expiry.
    /// @dev This is the ONLY valid access check for SUBSCRIPTION tools. For
    ///      SUBSCRIPTION tools with ERC-721 collections, the basic `hasAccess`
    ///      cannot determine which tokenId to check `expiresAt` on (since
    ///      `balanceOf` only confirms ownership of *some* token). This function
    ///      requires the caller to supply the specific tokenId they hold.
    ///      If the tool is not `active`, MUST return `false` regardless of mode.
    ///      For SUBSCRIPTION tools, MUST verify:
    ///        (a) `account` owns `tokenId` in a bound collection, AND
    ///        (b) `IERC5643(collection).expiresAt(tokenId) > block.timestamp`.
    ///      The onchain check is strict. `gracePeriodSeconds` from the
    ///      offchain manifest is a gateway-layer hint only and MUST NOT be
    ///      applied here; see "Subscription Expiration Race Conditions".
    ///      Each external call (`ownerOf`, `expiresAt`, `balanceOf`) MUST be
    ///      revert-resilient: a reverting call on a bound collection is treated
    ///      as "does not grant access" for that binding, and iteration
    ///      continues.
    ///      For NFT_GATED tools, the proof tokenId is ignored; `binding.tokenId`
    ///      is always used, and the function behaves identically to `hasAccess`.
    /// @param toolId   The tool to check access for.
    /// @param account  The account to check.
    /// @param tokenId  The caller's specific tokenId for subscription expiry verification.
    function hasAccessWithProof(uint256 toolId, address account, uint256 tokenId) external view returns (bool);

    // ──────────────────── Collection Management ────────────────────

    /// @notice Bind an NFT collection to a tool. Tool creator only.
    /// @dev A tool MUST have at most `MAX_COLLECTIONS()` bindings.
    ///      MUST revert with `UnsupportedStandardForSubscription` if `standard`
    ///      is `ERC1155` and the tool's `accessMode` is `SUBSCRIPTION`.
    ///      MUST revert with `InvalidCollection` if `standard` is `ERC721` and
    ///      `tokenId != 0`, since ERC-721 bindings use `balanceOf(account)` and
    ///      a nonzero `tokenId` would be silently ignored state.
    function addCollection(
        uint256 toolId,
        address collection,
        TokenStandard standard,
        uint256 tokenId
    ) external;

    /// @notice Remove a collection binding by index. Tool creator only.
    /// @dev Implementations MUST verify that the binding at `index` has
    ///      `collection == expectedCollection` at the time the call lands and
    ///      MUST revert with `CollectionMismatch` otherwise. This is a
    ///      compare-and-swap style guard against index races: if a concurrent
    ///      removal shifts the array, a caller who read the old layout will
    ///      fail loudly instead of removing the wrong binding. Callers SHOULD
    ///      re-fetch `getCollections` and retry on mismatch.
    function removeCollection(uint256 toolId, uint256 index, address expectedCollection) external;

    /// @notice Get all collection bindings for a tool.
    function getCollections(uint256 toolId) external view returns (CollectionBinding[] memory);
}
```

### 4. Gateway Key Registry

Deployments that offer cross-chain bindings (§5) MUST implement this interface. Deployments that offer only same-chain access (§3) MAY omit it.

Gateway signing keys are the onchain trust anchor for cross-chain attestations: the Tool Access Registry recovers the signer of each `CrossChainProof` and checks that the recovered address is registered here. A compromised admin key can register arbitrary signers and thereby forge cross-chain attestations, so deployments SHOULD protect admin operations with a time-lock or multi-sig. Implementations MUST NOT permit the admin role to be renounced to the zero address while the registry is still referenced by a `ToolAccessRegistry`: renouncing would strand the registry with no way to add or remove keys, and transfer to a successor admin MUST be used instead. Admin transfers SHOULD be two-step (the successor admin MUST explicitly accept the role before it takes effect) so that a mistyped or compromised transfer target cannot silently brick the registry; this is a structural complement to the non-renounceable admin role.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IGatewayKeyRegistry
/// @notice Registry of gateway signing keys for EIP-712 cross-chain attestations.
/// @dev ERC-165 interface ID: 0xf5c37176
interface IGatewayKeyRegistry /* is IERC165 */ {

    // ──────────────────── Events ────────────────────

    event GatewayKeyAdded(address indexed key);
    event GatewayKeyRemoved(address indexed key);

    // ──────────────────── Errors ────────────────────

    error KeyAlreadyRegistered(address key);
    error KeyNotRegistered(address key);
    /// @notice The supplied key is invalid.
    /// @dev Implementations MUST revert with this error when the supplied key
    ///      is `address(0)`. Implementations MAY additionally reject keys that
    ///      fail implementation-specific validation.
    error InvalidKey();
    error Unauthorized();

    // ──────────────────── Functions ────────────────────

    /// @notice Register a new gateway signing key. Admin only.
    /// @dev "Admin" is implementation-defined (e.g., contract owner, multi-sig, DAO).
    ///      Deployments SHOULD protect admin key operations with time-locks or
    ///      multi-sig governance. MUST revert with `InvalidKey` if `key` is
    ///      `address(0)`.
    function addGatewayKey(address key) external;

    /// @notice Remove a gateway signing key. Admin only.
    function removeGatewayKey(address key) external;

    /// @notice Check whether a key is a registered gateway signing key.
    function isValidGatewayKey(address key) external view returns (bool);
}
```

### 5. Cross-Chain NFT Gating

The `IToolAccessRegistry` interface (§3) requires bound NFT collections to live on the registry's chain. This section extends **NFT_GATED** access to collections deployed on other chains, using gateway-signed [EIP-712](https://eips.ethereum.org/EIPS/eip-712) attestations as the onchain trust anchor. A tool deployed on one chain can therefore gate on an existing NFT community living on another (for example, a tool on Base that checks holders of a mainnet ERC-721).

Cross-chain support is OPTIONAL. A deployment that does not bind cross-chain collections MAY implement only §3. A deployment that offers cross-chain bindings MUST implement both this interface and `IGatewayKeyRegistry` (§4).

Scope: `NFT_GATED` tools only. `SUBSCRIPTION` cross-chain bindings are out of scope for this revision. The gateway would be attesting to time-varying remote state (`expiresAt`), which adds a staleness race on top of the existing one. `SUBSCRIPTION` tools MUST bind same-chain ERC-5643 collections via `IToolAccessRegistry`. A future revision MAY re-introduce cross-chain `SUBSCRIPTION` as a pure extension without breaking existing cross-chain `NFT_GATED` tools.

#### Types

```solidity
/// @notice Binding between an NFT_GATED tool and an NFT collection on a remote chain.
/// @dev As in the same-chain binding, `tokenId` MUST be zero when
///      `tokenStandard == ERC721` and is rejected at bind time otherwise.
struct CrossChainBinding {
    uint256 chainId;              // EIP-155 chain ID where the collection lives
    address collection;           // NFT contract address on the remote chain
    TokenStandard tokenStandard;  // ERC-721 or ERC-1155
    uint256 tokenId;              // ERC-1155 only; MUST be 0 for ERC-721
}

/// @notice Gateway-signed proof of NFT ownership on a remote chain.
struct CrossChainProof {
    uint256 toolId;             // Tool being accessed
    address account;            // Account claiming access
    uint256 chainId;            // Remote chain where balance was checked
    address collection;         // NFT contract on the remote chain
    uint256 tokenId;            // Token ID held by the account
    uint256 checkedAt;          // Timestamp when balance was verified offchain
    bytes gatewaySignature;     // EIP-712 signature from a valid gateway key
}
```

Tool creators explicitly opt in to cross-chain gating by binding `(chainId, collection)` pairs via `addCrossChainCollection`. Cross-chain bindings are independent from same-chain bindings (§3) and have their own cap.

#### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IToolAccessRegistryCrossChain
/// @notice Cross-chain NFT gating extension to IToolAccessRegistry.
interface IToolAccessRegistryCrossChain /* is IERC165 */ {

    // ──────────────────── Events ────────────────────

    event CrossChainBindingAdded(
        uint256 indexed toolId,
        uint256 chainId,
        address indexed collection,
        TokenStandard tokenStandard
    );
    event CrossChainBindingRemoved(
        uint256 indexed toolId,
        uint256 chainId,
        address indexed collection
    );

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
    /// @dev Implementations MUST return exactly `20`.
    function MAX_CROSS_CHAIN_COLLECTIONS() external view returns (uint256);

    /// @notice Staleness window for cross-chain proofs, in seconds.
    /// @dev Implementations MUST return `300` (5 minutes). Gateways SHOULD
    ///      refresh attestations proactively before expiry.
    function STALENESS_WINDOW() external view returns (uint256);

    // ──────────────────── Access Check ────────────────────

    /// @notice Check access using a gateway-signed cross-chain ownership proof.
    /// @dev Verification order (checks are ordered from cheap O(1) comparisons
    ///      toward the O(n) binding loop and ECDSA recovery last):
    ///   1. Tool MUST be active. OPEN tools return `true` without any proof
    ///      verification. SUBSCRIPTION tools return `false` unconditionally
    ///      (cross-chain SUBSCRIPTION is out of scope).
    ///   2. `proof.toolId == toolId` and `proof.account == account`.
    ///   3. `proof.checkedAt <= block.timestamp` and
    ///      `block.timestamp - proof.checkedAt <= STALENESS_WINDOW()`.
    ///   4. `(proof.chainId, proof.collection)` matches a `CrossChainBinding`
    ///      for the tool; for ERC-1155 bindings `proof.tokenId` MUST also
    ///      match the bound tokenId.
    ///   5. EIP-712 signature over `CrossChainProof` recovers to an address
    ///      registered in `IGatewayKeyRegistry` (§4).
    ///      Return `true` iff all checks pass.
    function hasAccessWithRemoteProof(
        uint256 toolId,
        address account,
        CrossChainProof calldata proof
    ) external view returns (bool);

    // ──────────────────── Collection Management ────────────────────

    /// @notice Bind a remote-chain NFT collection to a tool. Creator only.
    /// @dev MUST revert with `MaxCrossChainCollectionsReached` once the cap
    ///      is reached. MUST revert with `SubscriptionCrossChainUnsupported`
    ///      if the tool's `accessMode` is `SUBSCRIPTION`. MUST revert with
    ///      `InvalidCollection` if `standard` is `ERC721` and `tokenId != 0`.
    function addCrossChainCollection(
        uint256 toolId,
        uint256 chainId,
        address collection,
        TokenStandard standard,
        uint256 tokenId
    ) external;

    /// @notice Remove a cross-chain collection binding by index. Creator only.
    /// @dev Implementations MUST verify that the binding at `index` has
    ///      `(chainId, collection) == (expectedChainId, expectedCollection)` at
    ///      the time the call lands and MUST revert with
    ///      `CrossChainBindingMismatch` otherwise. Both fields are part of the
    ///      CAS key because the same collection address can legitimately be
    ///      bound on multiple remote chains (e.g. deterministic CREATE2
    ///      deployments); matching on the address alone would let a race
    ///      remove the binding for the wrong chain. Same CAS intent as
    ///      `IToolAccessRegistry.removeCollection`.
    function removeCrossChainCollection(
        uint256 toolId,
        uint256 index,
        uint256 expectedChainId,
        address expectedCollection
    ) external;

    /// @notice Get all cross-chain collection bindings for a tool.
    function getCrossChainCollections(uint256 toolId)
        external
        view
        returns (CrossChainBinding[] memory);
}
```

#### EIP-712 Domain Separator

The EIP-712 domain separator for cross-chain proofs MUST be:

- `name`: `"ToolRegistryCrossChain"`
- `version`: `"1"`
- `chainId`: The chain ID where the Tool Access Registry is deployed
- `verifyingContract`: The Tool Access Registry contract address

The `CrossChainProof` type hash is computed from the canonical struct encoding, excluding `gatewaySignature`:

```
CrossChainProof(uint256 toolId,address account,uint256 chainId,address collection,uint256 tokenId,uint256 checkedAt)
```

#### Trust Model

The user already trusts the gateway to serve the tool endpoint, check same-chain `balanceOf`, and route payments. Adding remote-chain balance verification via the same gateway does not expand the trust boundary. The attestation is cryptographically bound to a specific user, tool, chain, collection, and timestamp, and the staleness window bounds the period during which a compromised gateway could issue valid proofs for a revoked or transferred token.

Three consequences of the staleness model are worth making explicit:

- **Revocation latency.** Removing a gateway key from `IGatewayKeyRegistry` does not invalidate proofs issued before removal. A signed proof with `checkedAt` inside the staleness window remains verifiable until `block.timestamp - checkedAt > STALENESS_WINDOW()`. In the worst case, revocation takes effect `STALENESS_WINDOW()` seconds after the registry update.
- **Post-transfer replay.** A `CrossChainProof` is replayable for the duration of the staleness window. If a user transfers (or burns) the attested token after `checkedAt`, the same proof still verifies until `block.timestamp - checkedAt > STALENESS_WINDOW()`. Gateways SHOULD refuse to issue new proofs for tokens they believe have moved, and high-value tools MAY shorten the effective window by rejecting proofs whose `checkedAt` is older than a consumer-specified threshold. A future revision MAY add a `nonce` or `blockNumber` field to `CrossChainProof` to enable stricter, per-call verification; the current struct and typehash are intentionally narrow so that such a field can be introduced as a separate typed attestation without breaking existing bindings.
- **Cross-registry replay.** The EIP-712 domain separator includes the `verifyingContract` (the Tool Access Registry address) and the local `chainId`, so a valid proof for Registry-A on chain C cannot be replayed against Registry-B on the same chain. Deployments that share gateway keys across chains or contracts still get replay protection from the domain separator; no additional proof-level binding is required.

#### Future Upgrade Path

The gateway attestation model can be replaced with trustless storage proofs (e.g., [Herodotus](https://www.herodotus.dev/), [Lagrange](https://www.lagrange.dev/), [Axiom](https://www.axiom.xyz/)) in a future revision without changing the external `hasAccessWithRemoteProof` interface; only the internal verification logic changes.

### Interface IDs

Each interface in this standard declares an ERC-165 interface ID. Per ERC-165, the interface ID is the XOR of the 4-byte function selectors of every external/public function declared on the interface. Events, errors, structs, and enums are not selectors and are excluded from the XOR. Inherited interfaces (e.g., `IERC165` itself) are not included in the reported ID unless explicitly noted.

A function selector is `bytes4(keccak256(canonicalSignature))`, where enum parameters are encoded as their underlying integer type (e.g., `AccessMode` becomes `uint8`) and struct parameters use their canonical tuple encoding. The selectors used for each interface in this standard are listed below.

While this standard is in Draft status and function signatures may continue to evolve, concrete interface IDs are **not** pinned in this document. The reference implementation is the canonical source: each ID is locked by a `test_interfaceId_<IInterface>_matchesSpec` test that asserts `type(I).interfaceId` against a value checked in at the same commit as the interface. Any change to an interface's shape MUST be accompanied by a spec update and a new ID in the reference implementation, and `supportsInterface(id)` MUST return `true` for the ID produced by the shipped interface shape.

**`IToolRegistry`**: XOR of

- `registerTool(string,bytes32,uint8)`
- `updateToolMetadata(uint256,string,bytes32)`
- `deactivateTool(uint256)`
- `reactivateTool(uint256)`
- `getToolConfig(uint256)`
- `hasAccess(uint256,address)`
- `toolCount()`

**`IToolAccessRegistry`**: XOR of

- `MAX_COLLECTIONS()`
- `hasAccess(uint256,address)`
- `hasAccessWithProof(uint256,address,uint256)`
- `addCollection(uint256,address,uint8,uint256)`
- `removeCollection(uint256,uint256,address)`
- `getCollections(uint256)`

Note: `IToolRegistry.hasAccess(uint256,address)` and `IToolAccessRegistry.hasAccess(uint256,address)` intentionally share the same function selector so a single contract implementing both interfaces can provide one function body. A combined implementation MUST still return `true` from `supportsInterface` for both interface IDs separately.

**`IGatewayKeyRegistry`**: XOR of

- `addGatewayKey(address)`
- `removeGatewayKey(address)`
- `isValidGatewayKey(address)`

**`IToolAccessRegistryCrossChain`**: XOR of

- `MAX_CROSS_CHAIN_COLLECTIONS()`
- `STALENESS_WINDOW()`
- `hasAccessWithRemoteProof(uint256,address,(uint256,address,uint256,address,uint256,uint256,bytes))`
- `addCrossChainCollection(uint256,uint256,address,uint8,uint256)`
- `removeCrossChainCollection(uint256,uint256,uint256,address)`
- `getCrossChainCollections(uint256)`

## Rationale

### Open Access as a First-Class Mode

Making open access a first-class `AccessMode` enum variant (rather than "NFT-gated with no collection bound") makes intent explicit and avoids edge cases. `OPEN` tools can be free or paid.

### NFT-Gated Access Supports Existing Collections

`addCollection()` binds *any* existing ERC-721 or ERC-1155 collection to a tool; no changes to the original NFT contract are required. This adds utility to existing NFTs without new deployments.

### Creator-Hosted Over Platform-Hosted

The standard specifies an endpoint URL and manifest schema, not a runtime. Creators retain full control over hosting, scaling, and deployment. Any entity can run a compliant gateway.

### Separate from ERC-8004

A natural question is whether this functionality should be folded into ERC-8004 as an extension to the services array. It is kept separate for three reasons. First, **scope**: ERC-8004 focuses on agent identity, reputation, and validation; onchain gating of tool invocations is an orthogonal concern that is cleaner to specify on its own. Second, **lifecycle**: tools version, deactivate, and repoint to new endpoints independently of any agent, and an agent-scoped registry would couple those lifecycles. Third, **reuse**: tools registered under this standard can be invoked by ERC-8004 agents, by non-ERC-8004 clients (MCP, A2A, direct HTTP), or by other contracts, and a standalone registry keeps these call sites symmetric. The two standards compose cleanly: an ERC-8004 agent MAY reference tools registered here in its services array.

### Payment via Manifest-Declared Recipient

Payment is not an onchain concern of this standard. The `pricing` object declares a non-empty `accepts` array; each element names a token, chain, amount (or `maxAmount`, or `subscriptionAmount`), accepted payment protocols, and a `recipient` address. The payment protocol (x402, mpp, direct ERC-20 transfer, etc.) routes funds directly to that option's `recipient`, which may be an EOA, a payment splitter contract, a platform fee-taking splitter, or any contract the creator chooses. Fee splits, platform economics, and withdrawal mechanics are properties of the recipient contract, not the protocol. Modeling payment as a list of acceptable options (rather than a single token/chain tuple) keeps the standard payment-agnostic and composable with existing split/treasury tooling while still committing every `recipient` onchain via `manifestHash` so consumers can pin against silent redirection.

### Subscription as a First-Class Access Mode

`SUBSCRIPTION` is a distinct `AccessMode` because the access check differs: it must additionally verify `expiresAt > block.timestamp`. A separate enum variant ensures implementations cannot accidentally skip the expiration check. ERC-5643 was chosen because it extends ERC-721 with minimal additions (`renewSubscription`, `cancelSubscription`, `expiresAt`).

### Onchain Manifest Hash Commitment

Storing only a `metadataURI` makes every offchain field (endpoint, pricing, schemas) silently mutable under a stable reputation. Adding `bytes32 manifestHash` to `ToolConfig` commits the exact manifest bytes onchain. Any change forces an `updateToolMetadata` transaction and emits `ToolMetadataUpdated` with both old and new hashes. This keeps the registry fully dynamic (creators can version, fix, and improve manifests) while making every change witnessed and pin-able. Consumers that pin a specific `manifestHash` are unaffected by future updates until they explicitly re-approve. A pure content-addressed URI (IPFS/Arweave) is insufficient on its own because the `metadataURI` field itself is mutable. An onchain commitment to the bytes is the only way to bind the pointer to the content.

### Cross-Chain NFT Gating via Gateway Attestation

A registry contract cannot read balances from a foreign chain. Two patterns fill that gap: gateway-signed attestations or trustless storage proofs (Herodotus, Lagrange, Axiom). Gateway attestations are chosen as the first-class mechanism for two reasons. First, the user already trusts the gateway to serve the endpoint, check same-chain `balanceOf`, and route payments, so remote-chain balance verification does not expand the trust boundary. Second, the `hasAccessWithRemoteProof` interface surface is identical for both patterns, so a future revision can swap in storage proofs without affecting consumers. The staleness window bounds the period during which a compromised gateway could issue valid proofs for a revoked or transferred token.

Cross-chain is scoped to `NFT_GATED` tools only. Attesting to `SUBSCRIPTION` expiration adds a second staleness race (snapshot time vs. actual expiry time) on top of the same-chain race, for a narrow use case; keeping it out of v1 tightens the trust model and leaves the door open for a clean addition later.

### Gateway Key Registry as Onchain Trust Anchor

Cross-chain attestations require a way to decide which signers are legitimate. Rather than baking signer identity into each tool's access config (per-tool key management) or trusting an offchain reputation system, this standard defines a compact onchain registry of valid gateway keys. The Tool Access Registry recovers the signer of each `CrossChainProof` and checks inclusion in this registry. Deployments that offer only same-chain access do not need the Gateway Key Registry and MAY omit it.

### `hasAccess` Returns False for Subscription Tools

`IToolRegistry.hasAccess(toolId, account)` and `IToolAccessRegistry.hasAccess(toolId, account)` both return `false` unconditionally for `SUBSCRIPTION` tools. This is intentional: `balanceOf` alone cannot identify *which* `tokenId` an account holds, and ERC-5643's `expiresAt(tokenId)` requires a specific token. A function that returned `true` based on mere ownership would silently admit expired subscriptions. Forcing callers to `hasAccessWithProof(toolId, account, tokenId)` for subscriptions makes the expiration check structurally unavoidable.

### Compare-and-Swap on Binding Removal

Collection bindings are stored in indexed arrays, and `removeCollection` / `removeCrossChainCollection` take an index to identify which binding to drop. Index-addressed removal is fragile under concurrency: if a creator reads `getCollections`, submits two removals in parallel, and the first removal shifts the array, the second call could delete the wrong binding. Rather than mandate a specific internal layout (shift vs. swap-pop), this standard requires callers to pass the expected binding they believe occupies `index`. For same-chain bindings this is `expectedCollection`, and implementations MUST revert with `CollectionMismatch` on a miss. For cross-chain bindings the CAS key is the full `(expectedChainId, expectedCollection)` pair, and implementations MUST revert with `CrossChainBindingMismatch` on a miss; matching on the address alone is insufficient because the same collection address can legitimately be bound on multiple remote chains (e.g. deterministic CREATE2 deployments), and a race could otherwise remove the binding for the wrong chain. The result is a compare-and-swap: racing callers fail loudly and can retry against fresh state, instead of silently dropping the wrong binding.

### Fixed-Length Billing Periods

`billingPeriod` values are pinned to fixed second counts (e.g., `"monthly" = 2_592_000s`) rather than calendar units. Calendar-aligned billing (last-day-of-month, anniversary semantics) can be implemented inside the subscription collection contract if desired, but the manifest-level clock that gateways use to police access is fixed-length. Without this, `expiresAt` returned by the collection and the period the gateway believes it purchased could silently drift apart across leap years and month-length variation.

## Backwards Compatibility

This ERC introduces new interfaces and does not modify existing standards. It composes with ERC-165, EIP-712, ERC-721, ERC-1155, ERC-5643, and ERC-8004 without requiring changes to any of them.

## Reference Implementation

A Foundry reference implementation is available at: [github.com/ProjectOpenSea/tool-registry](https://github.com/ProjectOpenSea/tool-registry)

## Security Considerations

### SSRF via Creator-Hosted Endpoints

A malicious creator could register an endpoint pointing to internal services. Gateways SHOULD validate endpoint URLs, enforce HTTPS-only, and reject private/reserved IP ranges.

### NFT Flash Loan Attacks

An attacker could flash-loan an NFT to pass `hasAccess()` and return it in the same transaction. `balanceOf` on the current chain head reflects the temporarily-held balance even though the attacker never really owned the token from the user's perspective.

Gateways SHOULD mitigate this in one of two ways:

- **Confirmation depth.** Perform `balanceOf` against a block `N` blocks behind the chain head (`eth_call` at `blockNumber = head - N`). A flash-loan taken in block `H` will not appear in block `H - N` for reasonable `N`, breaking the attack. `N` SHOULD be chosen per chain based on reorg depth and finality (for example, a small number of blocks on fast-finality L2s; more on pre-finality L1 tips).
- **Block-level caching of `hasAccess`.** Cache the access decision for `(toolId, account)` within a single block so that multiple RPC reads inside the same block do not observe temporary mid-block state shifts. This is weaker than confirmation depth alone.

For high-value tools, creators MAY additionally require a minimum continuous hold duration enforced at the tool endpoint (e.g., by checking transfer history), but this is out of scope for the registry itself.

### Revert Resilience for Bound Collections

The Tool Access Registry calls external contracts (`balanceOf`, `ownerOf`, `expiresAt`) on each bound collection during access checks. A bound collection can misbehave in three ways that matter for gating: its contract may be self-destructed, it may implement an incompatible ABI, or (in an adversarial setting) it may deliberately revert on `balanceOf`. Under OR semantics, a single such binding placed early in the array would otherwise cause the entire loop to revert, denying access to holders of legitimate later bindings and bubbling the revert up to consumers that gate on `hasAccess`.

Implementations MUST therefore wrap every external call on a bound collection in a `try/catch` (or equivalent low-level guard) and treat a revert as "no balance" for that binding. Iteration MUST continue with the next binding, and `hasAccess` / `hasAccessWithProof` MUST return a boolean rather than bubble up the inner revert. Creators retain the ability to remove a misbehaving binding via `removeCollection`, but the access check MUST remain live for other bindings in the meantime.

### Malicious Tool Endpoints

Gateways SHOULD enforce `timeoutSeconds`, validate responses against the declared `outputs` schema, and SHOULD NOT forward raw error messages to users.

### Front-Running Tool Registration

Tool IDs are auto-incrementing counters, not user-chosen, so there is no onchain name-squatting vector at the identifier layer.

The manifest `name` and `tags` fields, however, are offchain strings that any creator can set to any value. A malicious creator can register a tool whose manifest claims the `name` of a popular existing tool. Collision resolution is out of scope for this standard and is delegated to the discovery layer: indexers, marketplaces, and agent frameworks are expected to disambiguate by `(chainId, registryAddress, toolId)` (see CAIP-19 canonical form) and MAY layer reputation, verification badges, or allowlists on top of the raw registry. Consumers MUST NOT use the manifest `name` as an authoritative identifier.

### Metadata URI Mutability

Creators can update `metadataURI` at any time. The `AccessMode` is stored onchain and cannot be changed via metadata alone. Every other manifest field, including `endpoint`, every entry of `pricing.accepts` (token, chain, amount, recipient, protocols), and `inputs`/`outputs` schemas, lives offchain in the manifest JSON.

`ToolConfig.manifestHash` commits to the exact manifest bytes onchain. A change to any field in the manifest requires the creator to submit an `updateToolMetadata` transaction that atomically updates both the URI and hash, emitting `ToolMetadataUpdated(oldURI, newURI, oldHash, newHash)`. A creator cannot silently swap the endpoint, repoint payments to another recipient/chain/token, or alter schemas. Any such change is witnessed onchain, indexable, and pin-able.

Consumer guidance:

- Agents and agent frameworks SHOULD pin a specific `manifestHash` (from the time they first approved the tool) for repeated invocations. A pinned consumer is unaffected by future `updateToolMetadata` calls until they explicitly re-approve the new hash.
- Gateways SHOULD verify `keccak256(manifestBytes) == ToolConfig.manifestHash` before serving any request. A mismatch indicates either a serving bug or a malicious substitution at the URI layer and MUST be treated as an invalid tool.
- Indexers SHOULD subscribe to `ToolMetadataUpdated` and expose hash history so reputation systems can weight tools by manifest stability.

For stronger guarantees, creators MAY use content-addressed URIs (IPFS/Arweave). The onchain `manifestHash` still governs; content-addressing adds retrieval integrity but is not a substitute for the onchain commitment.

For stronger immutability, the `metadataURI` supports: **IPFS** (`ipfs://<CID>`), **Arweave** (`ar://<hash>`), **inline** (`data:application/json;base64,...`), and **`web3://`** ([ERC-4804](https://eips.ethereum.org/EIPS/eip-4804)). Gateways SHOULD support resolving `https://`, `ipfs://`, `ar://`, `data:`, and `web3://` URIs. Regardless of scheme, consumers SHOULD verify the fetched bytes against `manifestHash` before using the manifest.

### Subscription Expiration Race Conditions

A subscription may expire mid-invocation. Gateways SHOULD reject an invocation when `expiresAt(tokenId) < block.timestamp + timeoutSeconds`, so that a subscription cannot expire while the tool is still running. Creators MAY set `gracePeriodSeconds` in the manifest to extend access past `expiresAt` by that many seconds, avoiding penalization of users whose subscriptions lapse during or immediately before an invocation. When `gracePeriodSeconds > 0`, gateways SHOULD treat access as valid while `expiresAt(tokenId) + gracePeriodSeconds >= block.timestamp + timeoutSeconds`.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
