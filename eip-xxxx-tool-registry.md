---
eip: XXXX
title: Tool Registry Standard
description: Onchain registry for AI agent tools with open, NFT-gated, and subscription access modes
author: <tbd>
discussions-to: https://ethereum-magicians.org/t/eip-xxxx-tool-registry-standard/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2026-04-13
requires: 165, 721, 1155, 5643
---

## Abstract

This ERC defines an onchain registry for AI agent tools: the tool-layer counterpart to [ERC-8004 (Trustless Agents)](https://eips.ethereum.org/EIPS/eip-8004). Each registered tool has a unique onchain ID, an access mode (**open**, **NFT-gated** via ERC-721/ERC-1155, or **subscription** via [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643)), and a metadata URI pointing to a standardized JSON manifest describing the tool's endpoint, I/O schemas, pricing, and access configuration. Any access mode can be free or paid; pricing is independent of access control.

## Motivation

ERC-8004 standardizes agent identity, reputation, and validation, but there is no equivalent standard for the *tools* agents invoke. Tool discovery is fragmented across proprietary APIs and documentation sites. This ERC fills that gap with an onchain registry that provides: universal tool discovery via metadata URIs and standardized manifests; flexible access control (open, NFT-gated, or subscription); creator-hosted endpoints with no prescribed runtime; and interoperability across agent frameworks (MCP, A2A, etc.) and payment protocols (x402, etc.).

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
/// @dev ERC-165 interface ID: 0x41a32136
interface IToolRegistry /* is IERC165 */ {

    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a new tool is registered.
    event ToolRegistered(uint256 indexed toolId, address indexed creator, AccessMode accessMode);

    /// @notice Emitted when a tool's metadata URI is updated.
    /// @dev Emits both the prior and new URI so indexers and gateways can diff
    ///      manifests offchain without re-fetching the previous URI. Critical
    ///      manifest fields that can change silently (notably `pricing.token`,
    ///      `pricing.chainId`, and `endpoint`) are diffable only via this event.
    event ToolMetadataUpdated(uint256 indexed toolId, string oldURI, string newURI);

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

    /// @notice The provided metadata URI is empty or invalid.
    error InvalidMetadataURI();

    // ──────────────────── Registration ────────────────────

    /// @notice Register a new tool.
    /// @dev The tool's `creator` is set to `msg.sender` and cannot be changed.
    /// @param metadataURI URI that resolves to the Tool Manifest.
    /// @param accessMode  Access control mode (OPEN, NFT_GATED, or SUBSCRIPTION).
    /// @return toolId     The unique identifier assigned to the tool.
    function registerTool(string calldata metadataURI, AccessMode accessMode)
        external
        returns (uint256 toolId);

    // ──────────────────── Metadata ────────────────────

    /// @notice Update a tool's metadata URI. Creator only.
    /// @param toolId The tool to update.
    /// @param newURI The new metadata URI.
    function updateToolMetadata(uint256 toolId, string calldata newURI) external;

    // ──────────────────── Lifecycle ────────────────────

    /// @notice Deactivate a tool. Creator only.
    function deactivateTool(uint256 toolId) external;

    /// @notice Reactivate a previously deactivated tool. Creator only.
    function reactivateTool(uint256 toolId) external;

    // ──────────────────── Views ────────────────────

    /// @notice Get the full configuration for a tool.
    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory);

    /// @notice Check whether an account has access to invoke a tool.
    /// @dev For OPEN tools, MUST return true for any account.
    ///      For NFT_GATED tools, MUST check the Access Registry.
    ///      For SUBSCRIPTION tools, MUST check the Access Registry
    ///      (which verifies ERC-5643 expiration).
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

The `metadataURI` in `ToolConfig` MUST resolve to a JSON document conforming to the schema below. Gateways MUST validate that the `type` field matches a known schema version identifier and MUST reject manifests with an unknown or missing `type`. This prevents silent schema drift and ensures that future schema revisions can be introduced without breaking existing tools.

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

When present, the `pricing` object describes cost and accepted payment protocols. All amounts MUST be in the token's smallest unit (raw `uint256`; e.g., 0.02 USDC = `"20000"`). The `token` field MUST be the ERC-20 contract address on the specified chain, or the zero address for native currency. The `chainId` field MUST be the [EIP-155](https://eips.ethereum.org/EIPS/eip-155) chain ID.

**Per-invocation pricing (fixed cost):**

```json
{
  "model": "per-invocation",
  "amount": "20000",
  "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  "chainId": 8453,
  "protocols": ["x402"]
}
```

**Variable-cost pricing (e.g., inference-based tools):**

```json
{
  "model": "per-invocation",
  "maxAmount": "500000",
  "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  "chainId": 8453,
  "protocols": ["x402", "mpp"]
}
```

Tools MUST specify exactly one of `amount` (fixed) or `maxAmount` (variable, compatible with [x402](https://github.com/coinbase/x402) `upto` semantics).

**Subscription pricing:**

```json
{
  "model": "subscription",
  "subscriptionAmount": "10000000",
  "billingPeriod": "monthly",
  "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  "chainId": 8453,
  "protocols": ["x402", "erc20-transfer"]
}
```

Subscription access is gated onchain via [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643). The NFT's `expiresAt()` determines whether access is active.

#### Pricing Fields

| Field | Type | Description |
| --- | --- | --- |
| `model` | string | `"per-invocation"` or `"subscription"` |
| `amount` | string | Fixed cost per invocation in raw token units (mutually exclusive with `maxAmount`) |
| `maxAmount` | string | Maximum variable cost in raw token units (mutually exclusive with `amount`) |
| `subscriptionAmount` | string | Subscription cost per billing period in raw token units |
| `billingPeriod` | string | `"daily"`, `"weekly"`, `"monthly"`, or `"yearly"` |
| `token` | string | ERC-20 token contract address (zero address for native currency) |
| `chainId` | integer | [EIP-155](https://eips.ethereum.org/EIPS/eip-155) numeric chain ID |
| `protocols` | array | Accepted payment protocol identifiers (see below) |

Protocol identifiers are opaque strings. The `protocols` array MUST contain at least one entry when `pricing` is present. Gateways SHOULD select a protocol they support from the array. New protocol identifiers MAY be introduced without changes to this standard. The pricing object is OPTIONAL; free tools omit it entirely.

A non-normative registry of well-known protocol identifiers is maintained at [`docs/protocol-identifiers.md`](https://github.com/ProjectOpenSea/tool-registry/blob/main/docs/protocol-identifiers.md) in the reference implementation repository. At time of writing, the registry includes `x402` ([x402](https://github.com/coinbase/x402), HTTP 402 micropayments with `upto` support), `mpp` ([MPP](https://mpp.dev/), machine-to-machine payments), and `erc20-transfer` (direct ERC-20 transfer before invocation). Identifiers in the registry are informative; interoperability requires only that gateway and manifest agree on a shared string.

#### Access Mode Variants

**Open** (anyone can invoke, free or paid):

```json
{ "mode": "open" }
```

**Existing collection (ERC-721)**:

```json
{
  "mode": "nft",
  "collection": "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D"
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
  "collection": "0x1234...abcd",
  "billingPeriod": "monthly"
}
```

The bound collection MUST implement `IERC5643`. Access is granted only while `expiresAt(tokenId) > block.timestamp`.

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
    "amount": "20000",
    "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    "chainId": 8453,
    "protocols": ["x402"]
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
    "subscriptionAmount": "10000000",
    "billingPeriod": "monthly",
    "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    "chainId": 8453,
    "protocols": ["x402", "erc20-transfer"]
  },
  "access": {
    "mode": "subscription",
    "collection": "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01",
    "billingPeriod": "monthly"
  },
  "timeoutSeconds": 120,
  "tags": ["research", "deep-search", "premium"]
}
```

### 3. Tool Access Registry

The Tool Access Registry handles NFT-based access gating. A tool MAY be bound to multiple collections (up to `MAX_COLLECTIONS`). Access is granted if the user holds a token from **any** bound collection (OR logic). For `SUBSCRIPTION` tools, the held token MUST also have `expiresAt(tokenId) > block.timestamp`.

`SUBSCRIPTION` tools MUST bind only ERC-721 collections (which ERC-5643 extends). Binding an ERC-1155 collection to a `SUBSCRIPTION` tool is out of scope for this version of the standard: ERC-5643 defines `expiresAt(uint256 tokenId)` for ERC-721 tokens, and a per-`(owner, tokenId)` expiration semantic for semi-fungible tokens is not yet standardized. Implementations MUST revert in `addCollection` when a caller attempts to bind an `ERC1155` collection to a tool whose `accessMode` is `SUBSCRIPTION`.

#### Types

```solidity
/// @notice Token standard for collection bindings.
enum TokenStandard { ERC721, ERC1155 }

/// @notice Binding between a tool and an NFT collection that grants access.
struct CollectionBinding {
    address collection;           // NFT contract address
    TokenStandard tokenStandard;  // ERC-721 or ERC-1155
    uint256 tokenId;              // Only used for ERC-1155 (ignored for ERC-721)
    bool active;                  // Whether this binding is currently active
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
    /// @dev Implementations MUST enforce the value returned by `MAX_COLLECTIONS()`
    ///      as a hard cap on the number of bindings per tool (returning
    ///      `MaxCollectionsReached` from `addCollection` once the cap is reached).
    ///      The returned value MUST be >= 1 and SHOULD NOT exceed 100 to bound the
    ///      gas cost of `hasAccess` (which iterates bindings) and `getCollections`.
    ///      Conforming implementations SHOULD return 20 unless a deployment has
    ///      a documented reason to deviate.
    function MAX_COLLECTIONS() external view returns (uint256);

    // ──────────────────── Events ────────────────────

    event CollectionAdded(uint256 indexed toolId, address indexed collection, TokenStandard tokenStandard);
    event CollectionRemoved(uint256 indexed toolId, address indexed collection);

    // ──────────────────── Errors ────────────────────

    error MaxCollectionsReached(uint256 toolId);
    error CollectionNotFound(uint256 toolId, uint256 index);
    error InvalidCollection(address collection);
    error NotToolCreator(uint256 toolId, address caller);
    error UnsupportedStandardForSubscription(uint256 toolId, TokenStandard standard);

    // ──────────────────── Access Check ────────────────────

    /// @notice Check whether `account` has access to `toolId`.
    /// @dev For OPEN tools, MUST return `true` unconditionally.
    ///      For NFT_GATED tools, returns `true` if `account` holds a token from
    ///      ANY bound collection (OR logic, not AND).
    ///      ERC-721: checks `balanceOf(account) > 0` on the collection.
    ///      ERC-1155: checks `balanceOf(account, tokenId) > 0`.
    ///      For SUBSCRIPTION tools, additionally checks that
    ///      `IERC5643(collection).expiresAt(tokenId) > block.timestamp`.
    ///      Expired subscriptions MUST return `false`.
    ///      Argument order matches `IToolRegistry.hasAccess` so a single
    ///      contract MAY implement both interfaces with one function body.
    function hasAccess(uint256 toolId, address account) external view returns (bool);

    /// @notice Check access using a caller-supplied tokenId for SUBSCRIPTION expiry.
    /// @dev For SUBSCRIPTION tools with ERC-721 collections, the basic `hasAccess`
    ///      cannot determine which tokenId to check `expiresAt` on (since `balanceOf`
    ///      only confirms ownership of *some* token). This function allows the caller
    ///      to supply the specific tokenId they hold. For NFT_GATED tools, the proof
    ///      tokenId is ignored; `binding.tokenId` is always used.
    /// @param toolId   The tool to check access for.
    /// @param account  The account to check.
    /// @param tokenId  The caller's specific tokenId for subscription expiry verification.
    function hasAccessWithProof(uint256 toolId, address account, uint256 tokenId) external view returns (bool);

    // ──────────────────── Collection Management ────────────────────

    /// @notice Bind an NFT collection to a tool. Tool creator only.
    /// @dev A tool MUST have at most `MAX_COLLECTIONS()` bindings.
    ///      MUST revert with `UnsupportedStandardForSubscription` if `standard`
    ///      is `ERC1155` and the tool's `accessMode` is `SUBSCRIPTION`.
    function addCollection(
        uint256 toolId,
        address collection,
        TokenStandard standard,
        uint256 tokenId
    ) external;

    /// @notice Remove a collection binding by index. Tool creator only.
    function removeCollection(uint256 toolId, uint256 index) external;

    /// @notice Get all collection bindings for a tool.
    function getCollections(uint256 toolId) external view returns (CollectionBinding[] memory);
}
```

### Interface IDs

Each interface in this standard declares an ERC-165 interface ID. Per ERC-165, the interface ID is the XOR of the 4-byte function selectors of every external/public function declared on the interface. Events, errors, structs, and enums are not selectors and are excluded from the XOR. Inherited interfaces (e.g., `IERC165` itself) are not included in the reported ID unless explicitly noted.

A function selector is `bytes4(keccak256(canonicalSignature))`, where enum parameters are encoded as their underlying integer type (e.g., `AccessMode` becomes `uint8`) and struct parameters use their canonical tuple encoding. The selectors used for each interface in this standard are listed below. Reference implementations MUST verify that `supportsInterface(id)` returns `true` for the listed `id`.

**`IToolRegistry`** (ID: `0x41a32136`): XOR of

- `registerTool(string,uint8)`
- `updateToolMetadata(uint256,string)`
- `deactivateTool(uint256)`
- `reactivateTool(uint256)`
- `getToolConfig(uint256)`
- `hasAccess(uint256,address)`
- `toolCount()`

**`IToolAccessRegistry`** (ID: `0x542e220b`): XOR of

- `MAX_COLLECTIONS()`
- `hasAccess(uint256,address)`
- `hasAccessWithProof(uint256,address,uint256)`
- `addCollection(uint256,address,uint8,uint256)`
- `removeCollection(uint256,uint256)`
- `getCollections(uint256)`

Note: `IToolRegistry.hasAccess` and `IToolAccessRegistry.hasAccess` intentionally share the same selector so a single contract implementing both interfaces provides one function body.

**`IGatewayKeyRegistry`** (ID: `0xf5c37176`): XOR of

- `addGatewayKey(address)`
- `removeGatewayKey(address)`
- `isValidGatewayKey(address)`

**`IExecutionReceiptRegistry`** (ID: `0x9e391f7c`): XOR of

- `postBatch(bytes32,uint256)`
- `verifyReceipt(bytes32,bytes32[],uint256,uint256)`
- `getBatch(uint256)`
- `batchCount()`

**`IToolPayment`** (ID: `0xe1fc6949`): XOR of

- `setPaymentConfig(uint256,address,uint256,address,uint256)`
- `settlePayment(uint256,bytes32,address,uint256)`
- `getPaymentConfig(uint256)`
- `getBalance(uint256)`
- `withdraw(uint256)`
- `getPlatformBalance(uint256)`
- `withdrawPlatformFees(uint256)`

The reference implementation is the canonical source for computed values. Each ID is locked by a `test_interfaceId_<IInterface>_matchesSpec` test that asserts `type(I).interfaceId` against the value listed above; changes to any interface shape MUST be accompanied by a spec update.

## Rationale

### Open Access as a First-Class Mode

Making open access a first-class `AccessMode` enum variant (rather than "NFT-gated with no collection bound") makes intent explicit and avoids edge cases. `OPEN` tools can be free or paid.

### NFT-Gated Access Supports Existing Collections

`addCollection()` binds *any* existing ERC-721 or ERC-1155 collection to a tool; no changes to the original NFT contract are required. This adds utility to existing NFTs without new deployments.

### Creator-Hosted Over Platform-Hosted

The standard specifies an endpoint URL and manifest schema, not a runtime. Creators retain full control over hosting, scaling, and deployment. Any entity can run a compliant gateway.

### Separate from ERC-8004

Agents and tools differ in ownership (agents are autonomous; tools are creator-operated), lifecycle (tools version and deactivate independently of any agent), and access control (tools need NFT-gated and subscription-gated invocation as first-class modes). A standalone registry that composes with ERC-8004 keeps both standards focused and lets each evolve independently.

### Declared Payment Protocols Over Prescribed Mechanisms

Creators declare accepted payment protocols via the `protocols` array. New protocols can be adopted without changes to the registry standard. Gateway key management and execution receipts are orthogonal; see [Appendix A](#appendix-a-extension-interfaces).

### Subscription as a First-Class Access Mode

`SUBSCRIPTION` is a distinct `AccessMode` because the access check differs: it must additionally verify `expiresAt > block.timestamp`. A separate enum variant ensures implementations cannot accidentally skip the expiration check. ERC-5643 was chosen because it extends ERC-721 with minimal additions (`renewSubscription`, `cancelSubscription`, `expiresAt`).

## Backwards Compatibility

This ERC introduces new interfaces and does not modify existing standards. It composes with ERC-721, ERC-1155, ERC-5643, ERC-8004, and ERC-165 without requiring changes to any of them.

## Reference Implementation

A complete Foundry reference implementation (core + Appendix A extensions) is available at: [github.com/ProjectOpenSea/tool-registry](https://github.com/ProjectOpenSea/tool-registry)

## Security Considerations

### SSRF via Creator-Hosted Endpoints

A malicious creator could register an endpoint pointing to internal services. Gateways MUST validate endpoint URLs, enforce HTTPS-only, and reject private/reserved IP ranges.

### NFT Flash Loan Attacks

An attacker could flash-loan an NFT to pass `hasAccess()` and return it in the same transaction. Gateways SHOULD perform access checks outside callback contexts. Implementations MAY cache results at the block level.

### Malicious Tool Endpoints

Gateways MUST enforce `timeoutSeconds`. Gateways SHOULD validate responses against the declared `outputs` schema and SHOULD NOT forward raw error messages to users.

### Front-Running Tool Registration

Tool IDs are auto-incrementing counters, not user-chosen, so there is no name-squatting vector. Metadata is stored offchain in the Tool Manifest.

### Metadata URI Mutability

Creators can update `metadataURI` at any time. The `AccessMode` is stored onchain and cannot be changed via metadata alone, but every other manifest field, including `endpoint`, `pricing.token`, `pricing.chainId`, `pricing.amount`, and `inputs`/`outputs` schemas, can change silently on a metadata update. A creator who builds reputation on a benign manifest could swap the endpoint or redirect payments to a different chain/token after the fact, creating a rug vector against existing users.

Mitigations:

- `ToolMetadataUpdated` emits both `oldURI` and `newURI` so gateways and indexers can diff the full manifest on every update.
- Gateways MUST re-fetch and re-validate the manifest on every `ToolMetadataUpdated` event before continuing to route requests. Gateways SHOULD alert or halt routing when pricing-critical fields (`token`, `chainId`, `amount`, `maxAmount`) change.
- Agents and agent frameworks SHOULD pin a specific manifest hash or content-addressed URI (IPFS/Arweave) for repeated invocations rather than trusting the current `metadataURI` indefinitely.

For stronger immutability, the `metadataURI` supports: **IPFS** (`ipfs://<CID>`), **Arweave** (`ar://<hash>`), **inline** (`data:application/json;base64,...`), and **`web3://`** ([ERC-4804](https://eips.ethereum.org/EIPS/eip-4804)). Gateways MUST support resolving `https://`, `ipfs://`, `ar://`, `data:`, and `web3://` URIs.

### Subscription Expiration Race Conditions

A subscription may expire mid-invocation. Gateways SHOULD reject an invocation when `expiresAt(tokenId) < block.timestamp + timeoutSeconds`, so that a subscription cannot expire while the tool is still running. Creators MAY set `gracePeriodSeconds` in the manifest to extend access past `expiresAt` by that many seconds, avoiding penalization of users whose subscriptions lapse during or immediately before an invocation. When `gracePeriodSeconds > 0`, gateways SHOULD treat access as valid while `expiresAt(tokenId) + gracePeriodSeconds >= block.timestamp + timeoutSeconds`.

## Appendix A: Extension Interfaces

The following interfaces are non-normative extensions that gateway implementations MAY adopt.

### A.1 Gateway Signing Key Registry

Gateways that proxy tool invocations MAY register their [EIP-712](https://eips.ethereum.org/EIPS/eip-712) signing keys onchain so that creators can trustlessly verify invocation tokens.

```solidity
/// @title IGatewayKeyRegistry
/// @notice Registry of gateway signing keys for EIP-712 invocation token verification.
/// @dev ERC-165 interface ID: 0xf5c37176
interface IGatewayKeyRegistry /* is IERC165 */ {

    event GatewayKeyAdded(address indexed key);
    event GatewayKeyRemoved(address indexed key);

    error KeyAlreadyRegistered(address key);
    error KeyNotRegistered(address key);
    error InvalidKey();
    error Unauthorized();

    /// @notice Register a new gateway signing key. Admin only.
    /// @dev "Admin" is implementation-defined (e.g., contract owner, multi-sig, DAO).
    ///      Deployments SHOULD protect admin key operations with time-locks or
    ///      multi-sig governance. A compromised admin key can add arbitrary
    ///      gateway signers, enabling forged invocation tokens and cross-chain proofs.
    function addGatewayKey(address key) external;

    /// @notice Remove a gateway signing key. Admin only.
    function removeGatewayKey(address key) external;

    /// @notice Check whether a key is a registered gateway signing key.
    function isValidGatewayKey(address key) external view returns (bool);
}
```

### EIP-712 Invocation Token

When a gateway proxies a tool invocation, it SHOULD sign an EIP-712 typed data structure:

```solidity
struct InvocationToken {
    bytes32 invocationId;   // Unique invocation identifier (scoped per tool for deduplication)
    uint256 toolId;         // Tool being invoked
    address caller;         // Agent/user requesting the invocation
    bytes32 inputHash;      // keccak256 of the input data
    uint256 maxPayment;     // Maximum payment amount authorized
    uint256 nonce;          // Replay protection
    uint256 deadline;       // Expiry timestamp
}
```

The EIP-712 domain separator SHOULD include:
- `name`: `"ToolRegistryGateway"`
- `version`: `"1"`
- `chainId`: The chain ID where the Tool Registry is deployed
- `verifyingContract`: The Gateway Key Registry contract address

### A.2 Execution Receipt Registry

Gateways MAY post verifiable proofs of tool execution onchain as batched Merkle roots to amortize gas costs.

```solidity
/// @notice Canonical offchain schema for execution receipts. The registry does
///         not validate field semantics onchain; receipts are hashed offchain
///         and verified via Merkle proof against a posted root.
struct ExecutionReceipt {
    bytes32 invocationId;   // Matches the invocation token
    uint256 toolId;         // Tool that was invoked
    address caller;         // Agent/user who invoked the tool
    bytes32 inputHash;      // keccak256 of the input data
    bytes32 outputHash;     // keccak256 of the output data
    bool success;           // Whether the execution succeeded
    uint256 chargeAmount;   // Creator-specified usage-based charge ($0 on failure)
    uint256 maxPrice;       // Tool's maximum price ceiling (from manifest)
    uint256 timestamp;      // Block timestamp of the invocation
}

/// @title IExecutionReceiptRegistry
/// @notice Batch-posted Merkle roots of tool execution receipts.
/// @dev ERC-165 interface ID: 0x9e391f7c
interface IExecutionReceiptRegistry /* is IERC165 */ {

    event BatchPosted(uint256 indexed batchId, bytes32 merkleRoot, uint256 receiptCount);

    error EmptyBatch();
    error BatchNotFound(uint256 batchId);
    error InvalidProof();
    error Unauthorized();

    /// @notice Post a batch of execution receipts as a Merkle root.
    /// @dev Authorization is implementation-defined. The reference implementation
    ///      restricts this to the contract owner (`onlyOwner`). Implementations
    ///      MUST restrict access to trusted parties (e.g., admin, registered gateway
    ///      key holders) to prevent pollution of the receipt registry with
    ///      fabricated Merkle roots.
    function postBatch(bytes32 merkleRoot, uint256 receiptCount) external;

    /// @notice Verify that a specific receipt is included in a batch.
    function verifyReceipt(
        bytes32 receiptHash,
        bytes32[] calldata proof,
        uint256 batchId,
        uint256 index
    ) external view returns (bool valid);

    /// @notice Get a posted batch by ID.
    function getBatch(uint256 batchId) external view returns (bytes32 merkleRoot, uint256 receiptCount);

    /// @notice Get the total number of posted batches.
    function batchCount() external view returns (uint256);
}
```

### A.3 Payment Interface

Gateways MAY use a standardized payment interface for per-invocation payments. Compatible with [x402](https://github.com/coinbase/x402) `upto` semantics: the tool declares a `maxPrice` ceiling, the creator reports a usage-based `chargeAmount` per invocation (`chargeAmount <= maxPrice`), and on failure the charge is zero. `settlePayment` is restricted to the tool creator to prevent griefing. Invocation deduplication is scoped per tool.

```solidity
/// @notice Payment configuration for a tool.
struct PaymentConfig {
    address token;            // Payment token address (e.g., USDC)
    uint256 maxPrice;         // Maximum price ceiling per invocation in token units
    address recipient;        // Creator wallet or PaymentSplitter contract
    uint256 platformFeeBps;   // Platform fee in basis points
}

/// @title IToolPayment
/// @notice Per-invocation payment interface.
/// @dev ERC-165 interface ID: 0xe1fc6949
interface IToolPayment /* is IERC165 */ {

    event PaymentConfigSet(uint256 indexed toolId, address token, uint256 maxPrice, address recipient, uint256 platformFeeBps);
    event Withdrawal(uint256 indexed toolId, address indexed recipient, uint256 amount);
    event PaymentSettled(uint256 indexed toolId, bytes32 indexed invocationId, address indexed user, uint256 amount);

    error NoBalance(uint256 toolId);
    error NoPlatformBalance(uint256 toolId);
    error InvalidPaymentConfig();
    error TransferFailed();
    error NotToolCreator(uint256 toolId, address caller);
    error ToolNotFound(uint256 toolId);
    error ChargeExceedsMaxPrice(uint256 toolId, uint256 maxPrice, uint256 chargeAmount);
    error InvocationAlreadySettled(bytes32 invocationId);
    error NotPlatformFeeRecipient();
    error UnexpectedETH();
    error OutstandingBalance(uint256 toolId);
    error ToolInactive(uint256 toolId);
    error NotAuthorized(uint256 toolId, address caller);

    /// @notice Set or update the payment configuration for a tool. Creator only.
    /// @dev MUST revert with `OutstandingBalance` if the payment token is being changed
    ///      while the tool has non-zero balances or platform balances, to prevent
    ///      mixed-denomination accounting.
    /// @param toolId          The tool to configure.
    /// @param token           ERC-20 token address (zero address for native ETH).
    /// @param maxPrice        Maximum price ceiling per invocation in raw token units.
    /// @param recipient       Creator wallet or PaymentSplitter contract.
    /// @param platformFeeBps  Platform fee in basis points (0-10000).
    ///         Implementations MUST revert if `platformFeeBps > 10000`.
    ///         Implementations MUST revert with `InvalidPaymentConfig` if
    ///         `recipient` is the zero address.
    function setPaymentConfig(
        uint256 toolId,
        address token,
        uint256 maxPrice,
        address recipient,
        uint256 platformFeeBps
    ) external;

    /// @notice Settle payment for a tool invocation. Creator only.
    /// @dev The `chargeAmount` is the creator-specified usage-based charge, which
    ///      MUST be <= `maxPrice`. MUST reject duplicate `invocationId`s (scoped
    ///      per tool). MUST revert on deactivated tools (`ToolInactive`).
    ///      For native ETH, `msg.value` MUST be >= `chargeAmount`; excess is refunded.
    ///      For ERC-20 tokens, transfers `chargeAmount` from `msg.sender` to the contract.
    ///      When `chargeAmount` is 0, the ERC-20 transfer SHOULD be skipped to avoid
    ///      reverts on non-standard tokens.
    ///      On failure/timeout, `chargeAmount` is 0 and no onchain transaction is needed.
    ///      MUST revert with `UnexpectedETH` if `msg.value > 0` on an ERC-20 path.
    /// @param toolId        The tool being paid for.
    /// @param invocationId  Unique identifier for this invocation (replay protection).
    /// @param user          The agent/user who invoked the tool (for offchain audit).
    ///         This value is creator-asserted and NOT verified onchain.
    ///         Consumers of `PaymentSettled` events SHOULD treat the `user`
    ///         field as a claim by the creator, not a verified identity.
    /// @param chargeAmount  Creator-specified charge in raw token units (must be <= maxPrice).
    function settlePayment(uint256 toolId, bytes32 invocationId, address user, uint256 chargeAmount) external payable;

    /// @notice Get the payment configuration for a tool.
    function getPaymentConfig(uint256 toolId) external view returns (PaymentConfig memory);

    /// @notice Get the accumulated balance available for withdrawal.
    function getBalance(uint256 toolId) external view returns (uint256);

    /// @notice Withdraw accumulated earnings for a tool. Creator or recipient only.
    /// @dev For native ETH tools, implementations MUST use reentrancy guards
    ///      (e.g., OpenZeppelin ReentrancyGuard) or the checks-effects-interactions
    ///      pattern to prevent reentrancy on ETH withdrawal.
    function withdraw(uint256 toolId) external;

    /// @notice Get the accumulated platform fee balance for a tool.
    function getPlatformBalance(uint256 toolId) external view returns (uint256);

    /// @notice Withdraw accumulated platform fees for a tool.
    /// @dev The platform fee recipient is set at deployment time (immutable
    ///      constructor parameter in the reference implementation). Only the
    ///      platform fee recipient can call this function.
    ///      For native ETH tools, the same reentrancy guidance as `withdraw()` applies.
    function withdrawPlatformFees(uint256 toolId) external;
}
```

## Appendix B: Cross-Chain NFT Access Gating (Non-Normative)

The core `IToolAccessRegistry` requires the NFT collection to live on the same chain as the registry. This extension enables gating on collections deployed on other chains.

### B.1 Cross-Chain Binding

A new binding type alongside `CollectionBinding` allows creators to specify remote-chain collections:

```solidity
/// @notice Binding between a tool and an NFT collection on a remote chain.
struct CrossChainBinding {
    uint256 chainId;              // EIP-155 chain ID where the collection lives
    address collection;           // NFT contract address on the remote chain
    TokenStandard tokenStandard;  // ERC-721 or ERC-1155
    uint256 tokenId;              // Only used for ERC-1155 (ignored for ERC-721)
    bool active;                  // Whether this binding is currently active
}
```

Tool creators explicitly opt in by adding cross-chain bindings (with `chainId` + `collection` address). This is per-tool, not global. Cross-chain bindings SHOULD have their own cap (`MAX_CROSS_CHAIN_COLLECTIONS`) independent of the same-chain `MAX_COLLECTIONS` limit.

### B.2 Gateway Attestation

Since the registry contract cannot read state from a remote chain, a registered gateway key signs an [EIP-712](https://eips.ethereum.org/EIPS/eip-712) attestation proving the user holds the required token on the remote chain:

```solidity
/// @notice Gateway-signed proof of NFT ownership on a remote chain.
struct CrossChainProof {
    uint256 toolId;             // Tool being accessed
    address account;            // Account claiming access
    uint256 chainId;            // Remote chain where balance was checked
    address collection;         // NFT contract on the remote chain
    uint256 tokenId;            // Token ID held by the account
    uint256 checkedAt;          // Timestamp when balance was verified offchain
    uint256 expiresAt;          // Subscription expiry (0 if not SUBSCRIPTION mode)
    bytes gatewaySignature;     // EIP-712 signature from a valid gateway key
}
```

The `expiresAt` field is populated from the remote chain's `IERC5643.expiresAt(tokenId)` call when the tool uses `SUBSCRIPTION` mode with a cross-chain collection. For `NFT_GATED` tools, this field SHOULD be `0`.

### B.3 Access Check Function

```solidity
/// @notice Check access using a gateway-signed cross-chain ownership proof.
/// @dev Verification steps:
///   1. Recover signer from EIP-712 signature.
///   2. Verify signer is a valid key in IGatewayKeyRegistry.
///   3. Verify proof.toolId, proof.account, proof.chainId, proof.collection
///      match a registered CrossChainBinding for the tool.
///   4. Verify proof.checkedAt is within the staleness window
///      (block.timestamp - proof.checkedAt <= stalenessWindow).
///   5. For SUBSCRIPTION tools, verify proof.expiresAt > block.timestamp.
///   6. Return true if all checks pass.
/// @param toolId   The tool to check access for.
/// @param account  The account claiming access.
/// @param proof    Gateway-signed cross-chain ownership proof.
function hasAccessWithRemoteProof(
    uint256 toolId,
    address account,
    CrossChainProof calldata proof
) external view returns (bool);
```

### B.4 Collection Management

```solidity
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

/// @notice Bind a remote-chain NFT collection to a tool. Creator only.
function addCrossChainCollection(
    uint256 toolId,
    uint256 chainId,
    address collection,
    TokenStandard standard,
    uint256 tokenId
) external;

/// @notice Remove a cross-chain collection binding by index. Creator only.
function removeCrossChainCollection(uint256 toolId, uint256 index) external;
```

### B.5 Staleness Window

Implementations SHOULD enforce a configurable staleness window per tool (default: 300 seconds). Gateways SHOULD refresh attestations proactively before the window expires.

### B.6 EIP-712 Domain Separator

The EIP-712 domain separator for cross-chain proofs MUST include:

- `name`: `"ToolRegistryCrossChain"`
- `version`: `"1"`
- `chainId`: The chain ID where the Tool Registry is deployed
- `verifyingContract`: The Tool Access Registry contract address

### B.7 Trust Model

The user already trusts the gateway to check same-chain `balanceOf`, forward requests, and validate payments. Adding remote-chain balance verification does not expand the trust boundary. The attestation is cryptographically bound to a specific user, tool, chain, collection, and timestamp.

### B.8 Future Upgrade Path

The gateway attestation model can be replaced with trustless storage proofs (e.g., [Herodotus](https://www.herodotus.dev/), [Lagrange](https://www.lagrange.dev/), [Axiom](https://www.axiom.xyz/)) without changing the external `hasAccessWithRemoteProof` interface; only the internal verification logic changes.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
