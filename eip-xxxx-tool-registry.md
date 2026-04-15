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

This ERC defines an onchain registry standard for AI agent tools. This standard is the tool-layer counterpart to [ERC-8004 (Trustless Agents)](https://eips.ethereum.org/EIPS/eip-8004). Where ERC-8004 standardizes agent identity, reputation, and validation, this standard enables agents to discover and access tools through a shared onchain registry.

The standard introduces three access modes: **open** (anyone can invoke), **NFT-gated** (requires holding a specific ERC-721 or ERC-1155 token), and **subscription** (requires an active [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643) subscription NFT). Any access mode can be free or paid; pricing is independent of access control. Each registered tool has a metadata URI pointing to a standardized Tool Registration File describing its endpoint, input/output schemas, pricing, payment protocols, and access configuration.

The standard is gateway-agnostic and protocol-agnostic: it defines the registry and metadata format, not how tools are invoked or paid for. Any gateway, agent framework ([MCP](https://modelcontextprotocol.io/), A2A, etc.), or payment protocol ([x402](https://github.com/coinbase/x402), etc.) can integrate with the registry.

## Motivation

ERC-8004 provides Identity, Reputation, and Validation registries for agents. However, there is no equivalent standard for the *tools* that agents invoke. As the AI agent ecosystem matures, agents need a standardized way to:

### Discover Tools Onchain

Tool discovery is currently fragmented across proprietary APIs, documentation sites, and marketplace-specific catalogs. A shared onchain registry with metadata URIs pointing to standardized manifests (capabilities, pricing, input/output schemas, endpoint URLs) enables universal tool discovery by any agent framework.

### Gate Access with Flexible Models

Not all tools need NFT gating. An **open** mode enables an open tool economy where any agent can invoke any tool with free or paid per-invocation pricing. **NFT-gated** mode supports binding any existing ERC-721/ERC-1155 collection, enabling holders to access tools without changes to the original contract. Access passes can also be newly minted (tradeable or soulbound). NFT-gated tools may additionally charge per invocation. **Subscription** mode uses [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643) subscription NFTs for time-limited access with automatic revocation on expiration. Any mode can be free (no `pricing` object) or paid.

### Preserve Creator Control

Creators deploy tools on their own infrastructure. The standard does not specify a runtime, only an endpoint URL and manifest schema. Creators retain full control over their code, scaling, and hosting choices.

### Interoperate Across Agent Frameworks

Tools registered onchain can be discovered and invoked by any agent framework (MCP, A2A, or future protocols). The standard does not prescribe a specific agent-to-tool communication protocol or payment mechanism; it standardizes the registry and access layer that all protocols can build upon.

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “NOT RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Overview

The standard defines two onchain interfaces and one metadata format:

1. **Tool Identity Registry** (`IToolRegistry`) — Onchain registry where creators register tools, each assigned a unique ID with a metadata URI and access mode.
2. **Tool Registration File** — JSON metadata document (resolved from `metadataURI`) describing the tool’s endpoint, I/O schemas, pricing, and access configuration.
3. **Tool Access Registry** (`IToolAccessRegistry`) — NFT-based access gating. For `OPEN` tools, access is unconditional. For `NFT_GATED` tools, the caller must hold a token from a bound collection. For `SUBSCRIPTION` tools, the caller must hold a subscription NFT ([ERC-5643](https://eips.ethereum.org/EIPS/eip-5643)) that has not expired.

### 1. Tool Identity Registry

The Tool Identity Registry is the core interface. Each tool gets a unique onchain ID with a metadata URI pointing to its Tool Registration File.

#### Types

```solidity
/// @notice Access control mode for a registered tool.
enum AccessMode {
    /// Open access — anyone can invoke. Tool may be free or paid
    /// (pricing is declared in the Tool Registration File, not onchain).
    OPEN,
    /// Caller must hold a token from a bound NFT collection.
    NFT_GATED,
    /// Caller must hold an active ERC-5643 subscription NFT.
    SUBSCRIPTION
}

/// @notice Onchain configuration for a registered tool.
struct ToolConfig {
    address creator;          // Address that registered the tool
    string metadataURI;       // Resolves to Tool Registration File (JSON)
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
    event ToolMetadataUpdated(uint256 indexed toolId, string newURI);

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
    /// @param metadataURI URI that resolves to the Tool Registration File.
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

    /// @notice Get the total number of registered tools.
    function toolCount() external view returns (uint256);
}
```

### 2. Tool Registration File

The `metadataURI` in `ToolConfig` MUST resolve to a JSON document conforming to the Tool Registration File schema. This is analogous to ERC-8004’s Agent Registration File, serving as the manifest that describes a tool’s capabilities and configuration.

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
| `timeout_seconds` | integer | Maximum execution time (1-300, default 30) |
| `tags` | array | Discovery tags (max 10, lowercase alphanumeric + hyphens) |
| `services` | array | Compatible with ERC-8004 services array |
| `registrations` | array | Onchain registration references |

#### Pricing Object

When present, the `pricing` object describes the tool’s cost and accepted payment protocols. All amounts MUST be specified in the token’s smallest unit. For example, 0.02 USDC (6 decimals) is `"20000"`, and 0.01 ETH (18 decimals) is `"10000000000000000"`. This follows the convention established by [ERC-20](https://eips.ethereum.org/EIPS/eip-20), [ERC-2981](https://eips.ethereum.org/EIPS/eip-2981), and [Seaport](https://github.com/ProjectOpenSea/seaport), where all amounts are raw `uint256` values and `decimals()` is display-only.

The `token` field MUST be the ERC-20 contract address of the payment token on the specified chain. The `chainId` field MUST be the [EIP-155](https://eips.ethereum.org/EIPS/eip-155) numeric chain ID. For native currency (ETH), `token` MUST be the zero address (`0x0000000000000000000000000000000000000000`).

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

When `amount` is present, the cost is fixed per invocation. When `maxAmount` is present instead, the cost is variable up to the specified maximum (compatible with [x402](https://github.com/coinbase/x402) `upto` semantics). Tools MUST specify exactly one of `amount` or `maxAmount`.

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

The `billingPeriod` field accepts `"daily"`, `"weekly"`, `"monthly"`, or `"yearly"`. Subscription access is gated onchain via [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643) — the subscription NFT’s `expiresAt()` determines whether access is active.

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

The `protocols` array declares which payment protocols the tool’s endpoint accepts. Well-known protocol identifiers include:

| Identifier | Protocol | Description |
| --- | --- | --- |
| `x402` | [x402](https://github.com/coinbase/x402) | HTTP 402-based micropayments with `upto` support |
| `mpp` | [MPP](https://mpp.dev/) | Machine Payments Protocol for machine-to-machine payments |
| `erc20-transfer` | Direct ERC-20 | Direct onchain token transfer before invocation |

The `protocols` array MUST contain at least one entry when `pricing` is present. Gateways SHOULD select a protocol they support from the array. New protocol identifiers MAY be introduced without changes to this standard.

The pricing object is OPTIONAL. Free tools MAY omit it entirely.

#### Access Mode Variants

**Open** (anyone can invoke — free or paid):

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

Subscription access uses [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643) subscription NFTs. The bound collection MUST implement `IERC5643`. Access is granted only while `expiresAt(tokenId) > block.timestamp`.

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
  "timeout_seconds": 30,
  "tags": ["prediction-markets", "alpha", "trading"]
}
```

#### Example: Free Open Tool

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#registration-v1",
  "name": "gas-price-checker",
  "version": "1.0.0",
  "description": "Returns current gas prices across EVM chains",
  "endpoint": "https://gas.example.com",
  "inputs": {
    "type": "object",
    "properties": {
      "chainId": { "type": "integer", "description": "EIP-155 chain ID" }
    },
    "required": ["chainId"]
  },
  "outputs": {
    "type": "object",
    "properties": {
      "fast": { "type": "string" },
      "standard": { "type": "string" },
      "slow": { "type": "string" }
    }
  },
  "access": {
    "mode": "open"
  },
  "timeout_seconds": 10,
  "tags": ["gas", "utility"]
}
```

#### Example: NFT-Gated Tool with Per-Invocation Payment

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#registration-v1",
  "name": "exclusive-alpha-signals",
  "version": "1.0.0",
  "description": "Premium trading signals available only to NFT holders, charged per query",
  "image": "https://example.com/alpha-icon.png",
  "endpoint": "https://alpha.example.com",
  "inputs": {
    "type": "object",
    "properties": {
      "pair": { "type": "string", "description": "Trading pair (e.g., ETH/USDC)" }
    },
    "required": ["pair"]
  },
  "outputs": {
    "type": "object",
    "properties": {
      "signal": { "type": "string" },
      "strength": { "type": "number" }
    }
  },
  "pricing": {
    "model": "per-invocation",
    "amount": "50000",
    "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    "chainId": 8453,
    "protocols": ["x402"]
  },
  "access": {
    "mode": "nft",
    "collection": "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D"
  },
  "timeout_seconds": 15,
  "tags": ["trading", "alpha", "exclusive"]
}
```

#### Example: Subscription Tool

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#registration-v1",
  "name": "premium-research-agent",
  "version": "2.1.0",
  "description": "Deep research tool with unlimited queries for subscribers",
  "image": "https://example.com/research-icon.png",
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
  "timeout_seconds": 120,
  "tags": ["research", "deep-search", "premium"]
}
```

### 3. Tool Access Registry

The Tool Access Registry handles access control for all three modes. For `OPEN` tools, `hasAccess()` MUST return `true` unconditionally. For `NFT_GATED` tools, it checks `balanceOf` on bound collections. For `SUBSCRIPTION` tools, it checks both token ownership and subscription expiration via [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643)’s `expiresAt()`.

A tool MAY be bound to multiple collections (up to `MAX_COLLECTIONS`). Access is granted if the user holds a token from **any** bound collection (OR logic, not AND). For `SUBSCRIPTION` tools, the held token MUST also have `expiresAt(tokenId) > block.timestamp`.

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
/// @dev ERC-165 interface ID: 0x56860c64
interface IToolAccessRegistry /* is IERC165 */ {

    /// @notice Maximum number of collection bindings per tool.
    function MAX_COLLECTIONS() external pure returns (uint256); // 20

    // ──────────────────── Events ────────────────────

    event CollectionAdded(uint256 indexed toolId, address indexed collection, TokenStandard tokenStandard);
    event CollectionRemoved(uint256 indexed toolId, address indexed collection);

    // ──────────────────── Errors ────────────────────

    error MaxCollectionsReached(uint256 toolId);
    error CollectionNotFound(uint256 toolId, uint256 index);
    error InvalidCollection(address collection);
    error NotToolCreator(uint256 toolId, address caller);

    // ──────────────────── Access Check ────────────────────

    /// @notice Check whether `user` has access to `toolId`.
    /// @dev For OPEN tools, MUST return `true` unconditionally.
    ///      For NFT_GATED tools, returns `true` if user holds a token from
    ///      ANY bound collection (OR logic, not AND).
    ///      ERC-721: checks `balanceOf(user) > 0` on the collection.
    ///      ERC-1155: checks `balanceOf(user, tokenId) > 0`.
    ///      For SUBSCRIPTION tools, additionally checks that
    ///      `IERC5643(collection).expiresAt(tokenId) > block.timestamp`.
    ///      Expired subscriptions MUST return `false`.
    function hasAccess(address user, uint256 toolId) external view returns (bool);

    /// @notice Check access using a caller-supplied tokenId for SUBSCRIPTION expiry.
    /// @dev For SUBSCRIPTION tools with ERC-721 collections, the basic `hasAccess`
    ///      cannot determine which tokenId to check `expiresAt` on (since `balanceOf`
    ///      only confirms ownership of *some* token). This function allows the caller
    ///      to supply the specific tokenId they hold. For NFT_GATED tools, the proof
    ///      tokenId is ignored — `binding.tokenId` is always used.
    /// @param user     The account to check.
    /// @param toolId   The tool to check access for.
    /// @param tokenId  The caller's specific tokenId for subscription expiry verification.
    function hasAccessWithProof(address user, uint256 toolId, uint256 tokenId) external view returns (bool);

    // ──────────────────── Collection Management ────────────────────

    /// @notice Bind an NFT collection to a tool. Tool creator only.
    /// @dev A tool MAY have at most MAX_COLLECTIONS (20) bindings.
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

## Rationale

### Open Access as a First-Class Mode

Most indie tool creators want maximum reach; requiring users to hold a specific NFT reduces the addressable audience. `OPEN` tools have the simplest UX: discover and invoke. The `hasAccess()` function returns `true` unconditionally for these tools, regardless of whether the tool charges per invocation. Making open access a first-class `AccessMode` enum variant (rather than “NFT-gated with no collection bound”) makes the intent explicit and avoids edge cases. An `OPEN` tool can be free (no `pricing` object) or paid (with a `pricing` object declaring cost and protocols).

### NFT-Gated Access Supports Existing Collections

The Access Registry’s `addCollection()` function allows binding *any* existing ERC-721 or ERC-1155 collection to a tool. This adds utility to existing NFTs — holders of a PFP collection could get exclusive access to premium tools, creating new value for collections without requiring any changes to the original NFT contract. Recurring access is handled by the separate `SUBSCRIPTION` mode.

### Creator-Hosted Over Platform-Hosted

By requiring creators to host tools on their own infrastructure, the standard avoids specifying a runtime environment, sandbox model, or compute billing system. The gateway only needs the endpoint URL from the Tool Registration File. Creators retain full control over their tech stack, scaling, security, and deployment. This makes the standard maximally gateway-agnostic. Any entity can run a compliant gateway that reads the registry, verifies access, and proxies calls.

### Separate from ERC-8004

Tools have fundamentally different access patterns than agent identities. Agents need identity, reputation, and validation. Tools need access control (payment + NFT gating), endpoint discovery, and I/O schema definitions. Folding tool registration into ERC-8004 would couple agent identity with tool access control, making both standards more complex. A standalone ERC that references and composes with ERC-8004 keeps both standards focused and allows independent evolution.

### Declared Payment Protocols Over Prescribed Mechanisms

Rather than prescribing a specific payment mechanism, the standard allows creators to declare which payment protocols their endpoint accepts via the `protocols` array in the pricing object. This enables the ecosystem to evolve. New payment protocols (x402, MPP, direct ERC-20 transfers, or future protocols) can be adopted without changes to the registry standard. Gateways select a compatible protocol from the array, and agents can choose gateways based on protocol support. Gateway signing key management (EIP-712 invocation tokens) and execution receipt registries (Merkle-batched onchain proofs) remain orthogonal to tool discovery and access control. See [Appendix A](about:blank#appendix-a-extension-interfaces) for non-normative extension interfaces that address these concerns.

### Subscription as a First-Class Access Mode

Subscription access is a distinct `AccessMode` rather than a sub-type of `NFT_GATED` because the access check semantics differ: NFT-gated tools only check token ownership (`balanceOf > 0`), while subscription tools must additionally verify that the subscription has not expired (`expiresAt > block.timestamp`). Making this a separate enum variant ensures implementations cannot accidentally skip the expiration check. [ERC-5643](https://eips.ethereum.org/EIPS/eip-5643) was chosen because it extends ERC-721 with minimal additions (`renewSubscription`, `cancelSubscription`, `expiresAt`).

## Backwards Compatibility

This ERC introduces new interfaces and does not modify any existing standards. It is fully compatible with:

- **ERC-721 / ERC-1155**: Used for NFT-gated access control. The Access Registry reads `balanceOf` from existing collections without requiring any modifications.
- **ERC-8004**: An agent registered via ERC-8004 can discover and invoke tools registered via this ERC. The Tool Registration File’s `services` array is compatible with ERC-8004’s service declaration format.
- **ERC-5643**: Subscription-based access passes use ERC-5643’s `expiresAt()` interface for time-limited access.
- **ERC-165**: All interfaces declare ERC-165 interface IDs for runtime introspection.

No backwards compatibility issues exist.

## Reference Implementation

A complete reference implementation with Foundry tests (125 tests, all passing) is available at: [github.com/ProjectOpenSea/tool-registry](https://github.com/ProjectOpenSea/tool-registry)

The reference implementation includes the core interfaces defined in this standard plus the extension interfaces described in Appendix A:
- `ToolRegistry.sol` — Core registry with AccessMode, tool CRUD, `hasAccess()`
- `ToolAccessRegistry.sol` — NFT-gated access with collection bindings
- `GatewayKeyRegistry.sol` — Gateway signing key management (Extension)
- `ExecutionReceiptRegistry.sol` — Batch Merkle root posting and verification (Extension)
- `ToolPayment.sol` — Payment config, balances, and withdrawal (Extension)

## Security Considerations

### SSRF via Creator-Hosted Endpoints

A malicious tool creator could register an endpoint pointing to internal or cloud metadata services. **Mitigation**: Gateways MUST validate and sanitize endpoint URLs. Gateways SHOULD enforce HTTPS-only, reject private/reserved IP ranges, follow redirects cautiously, and implement request timeouts. The Tool Registration File schema requires HTTPS endpoints.

### NFT Flash Loan Attacks

An attacker could flash-loan an NFT to pass `hasAccess()`, invoke the tool, and return the NFT in the same transaction. **Mitigation**: Gateways SHOULD perform access checks in a context where flash loans cannot be exploited (e.g., at the start of a new transaction, not within a callback). Implementations MAY cache access check results at the block level. For high-value tools, creators MAY require a minimum hold duration.

### Malicious Tool Endpoints

A tool endpoint could return malicious data, take excessively long, or attempt to exfiltrate input data. **Mitigation**: Gateways MUST enforce the `timeout_seconds` from the Tool Registration File. Gateways SHOULD validate response structure against the declared `outputs` JSON Schema. Gateways SHOULD NOT forward raw error messages from tool endpoints to users.

### Front-Running Tool Registration

An attacker could monitor the mempool and front-run a tool registration to claim a desirable tool ID. **Mitigation**: Tool IDs are auto-incrementing counters, not user-chosen, so there is no “name squatting” attack. However, implementations MAY add a commit-reveal scheme if tool IDs gain economic significance. Tool metadata (name, description) is stored off-chain in the Tool Registration File, not onchain.

### Metadata URI Mutability

Tool creators can update their `metadataURI` at any time, potentially changing pricing, access mode descriptions, or endpoint URLs without onchain notice. **Mitigation**: All metadata updates emit `ToolMetadataUpdated` events for indexing and auditability. The `AccessMode` is stored onchain and cannot be changed via metadata updates alone. Gateways SHOULD cache and diff metadata to detect significant changes.

For stronger immutability guarantees, the `metadataURI` field supports several URI schemes beyond centralized HTTPS hosting:

- **IPFS** (`ipfs://<CID>`): Content-addressed and immutable. Recommended for tools whose metadata should never change after registration.
- **Arweave** (`ar://<hash>`): Permanent storage with economic guarantees of persistence.
- **Onchain / inline** (`data:application/json;base64,<encoded>`): The Tool Registration File can be embedded directly onchain as a Base64-encoded `data:` URI, analogous to [onchain NFT metadata](https://docs.opensea.io/docs/metadata-standards#onchain-metadata). This eliminates all external dependencies — the metadata is fully self-contained in the contract’s state and readable without any off-chain requests. This approach is best suited for tools with small, stable manifests.
- **`web3://`** ([ERC-4804](https://eips.ethereum.org/EIPS/eip-4804)): The `metadataURI` MAY use the `web3://` protocol to resolve metadata from another smart contract, enabling fully onchain and composable metadata that can be read by any `web3://`aware client without centralized infrastructure.

Creators SHOULD choose the URI scheme that matches their mutability and availability requirements. Gateways MUST support resolving `https://`, `ipfs://`, `ar://`, `data:`, and `web3://` URIs.

### Subscription Expiration Race Conditions

A subscription may expire between the time `hasAccess()` returns `true` and the time a tool invocation completes. **Mitigation**: Gateways SHOULD check `expiresAt()` at the start of each invocation and reject requests where the subscription expires within the tool’s `timeout_seconds` window. Implementations SHOULD treat `expiresAt(tokenId) < block.timestamp + timeout_seconds` as insufficient access. Creators MAY add a grace period to avoid penalizing users whose subscriptions expire mid-invocation.

## Appendix A: Extension Interfaces

The following interfaces are non-normative. They describe common patterns that gateway implementations MAY adopt to complement the core registry standard. These are provided as RECOMMENDED starting points, not requirements.

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
///         not validate field semantics onchain — receipts are hashed offchain
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

Gateways MAY use a standardized payment interface for per-invocation payments. This is compatible with [x402](https://github.com/coinbase/x402) `upto` semantics: the tool declares a `maxPrice` ceiling, the creator reports a usage-based `chargeAmount` per invocation (`chargeAmount <= maxPrice`), and on failure/timeout the charge is zero with no onchain transaction needed. The `settlePayment` function is restricted to the tool creator (trusted gateway operator) to prevent griefing via front-run zero-cost settlements. Invocation deduplication is scoped per tool so the same `invocationId` can legitimately appear across different tools. The interface does not require any specific payment protocol.

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

The core `IToolAccessRegistry` checks `balanceOf`/`ownerOf` directly onchain, which requires the NFT collection to live on the same chain as the registry. This extension enables tool creators to gate access on NFT collections deployed on other chains (e.g., gate on a mainnet collection while the registry lives on Base).

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
    address user;               // Account claiming access
    uint256 chainId;            // Remote chain where balance was checked
    address collection;         // NFT contract on the remote chain
    uint256 tokenId;            // Token ID held by the user
    uint64 checkedAt;           // Timestamp when balance was verified offchain
    uint64 expiresAt;           // Subscription expiry (0 if not SUBSCRIPTION mode)
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
///   3. Verify proof.toolId, proof.user, proof.chainId, proof.collection
///      match a registered CrossChainBinding for the tool.
///   4. Verify proof.checkedAt is within the staleness window
///      (block.timestamp - proof.checkedAt <= stalenessWindow).
///   5. For SUBSCRIPTION tools, verify proof.expiresAt > block.timestamp.
///   6. Return true if all checks pass.
/// @param user    The account claiming access.
/// @param toolId  The tool to check access for.
/// @param proof   Gateway-signed cross-chain ownership proof.
function hasAccessWithRemoteProof(
    address user,
    uint256 toolId,
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

The `checkedAt` timestamp in the proof determines how fresh the offchain balance check is. Implementations SHOULD enforce a configurable staleness window per tool:

- **Default**: 5 minutes (300 seconds).
- **Shorter windows** (e.g., 60 seconds) increase security but require more frequent attestations and worse UX.
- **Longer windows** (e.g., 15 minutes) improve UX but increase the risk of stale proofs (e.g., user transferred the NFT after the check).

Tool creators SHOULD be able to configure the staleness window for their tool. Gateways SHOULD refresh attestations proactively before the window expires.

### B.6 EIP-712 Domain Separator

The EIP-712 domain separator for cross-chain proofs MUST include:

- `name`: `"ToolRegistryCrossChain"`
- `version`: `"1"`
- `chainId`: The chain ID where the Tool Registry (not the NFT collection) is deployed
- `verifyingContract`: The Tool Access Registry contract address

Including the registry's chain ID and address prevents cross-deployment replay attacks where a proof valid on one chain's registry is reused on another.

### B.7 Trust Model

The gateway mediates tool invocations (routing requests, enforcing access, validating payments). The user already trusts the gateway to:

1. Correctly check same-chain `balanceOf` before proxying
2. Forward requests honestly to the tool endpoint
3. Validate payments accurately

Adding remote-chain balance verification to this list does not expand the trust boundary. The attestation is cryptographically bound to a specific user, tool, chain, collection, and timestamp. A compromised gateway key can forge attestations, but this risk already exists for same-chain access, where a compromised gateway could bypass `hasAccess()` entirely.

### B.8 Future Upgrade Path

The `hasAccessWithRemoteProof` interface is designed to be forward-compatible with trustless verification. The gateway attestation model can be replaced with trustless storage proofs (e.g., [Herodotus](https://www.herodotus.dev/), [Lagrange](https://www.lagrange.dev/), [Axiom](https://www.axiom.xyz/)) in a future version without changing the external interface — only the verification logic inside `hasAccessWithRemoteProof` would change from "recover EIP-712 signer and check gateway key registry" to "verify storage proof against the remote chain's state root."

This migration path allows deployments to start with gateway attestations (simpler, available today) and upgrade to trustless proofs as the infrastructure matures, without breaking existing tool registrations or collection bindings.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
