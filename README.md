# ERC-XXXX Tool Registry — Reference Implementation

Foundry reference implementation for the **ERC-XXXX Tool Registry Standard**: an onchain registry for AI agent tools with open, NFT-gated, and subscription access modes.

## Overview

The standard defines how AI agents discover and access tools through a shared onchain registry. It introduces three access modes:

- **OPEN** — anyone can invoke (free or paid per invocation)
- **NFT_GATED** — caller must hold a token from a bound ERC-721 or ERC-1155 collection
- **SUBSCRIPTION** — caller must hold an active ERC-5643 subscription NFT

## Contracts

### Core (Normative)

| Contract | Interface | Description |
|---|---|---|
| `ToolRegistry.sol` | `IToolRegistry` | Tool registration, metadata updates, lifecycle management, access delegation |
| `ToolAccessRegistry.sol` | `IToolAccessRegistry` | NFT-based access gating with collection bindings and subscription expiration checks |

### Extensions (Non-Normative, Appendix A)

| Contract | Interface | Description |
|---|---|---|
| `GatewayKeyRegistry.sol` | `IGatewayKeyRegistry` | Admin-managed gateway signing keys for EIP-712 invocation token verification |
| `ExecutionReceiptRegistry.sol` | `IExecutionReceiptRegistry` | Batch Merkle root posting and receipt verification |
| `ToolPayment.sol` | `IToolPayment` | Per-invocation payment config, balance tracking, and withdrawal |

## Setup

```bash
cd packages/tool-registry
forge install
forge build
```

## Test

```bash
forge test
```

## Gas Report

```bash
forge test --gas-report
```

## Architecture

`ToolRegistry` delegates all access checks to `ToolAccessRegistry` via the `IToolAccessRegistry.hasAccess()` interface. The two contracts are linked using a two-step initialization pattern to resolve the circular dependency:

```solidity
ToolRegistry registry = new ToolRegistry();
ToolAccessRegistry accessRegistry = new ToolAccessRegistry(address(registry));
registry.initialize(address(accessRegistry));
```

For `OPEN` tools, `hasAccess()` returns `true` unconditionally. For `NFT_GATED` tools, it checks `balanceOf` on bound collections (OR logic — any collection grants access). For `SUBSCRIPTION` tools, it additionally checks `IERC5643.expiresAt(tokenId) > block.timestamp`.

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) — ERC-165, ERC-721, ERC-1155, ERC-20, Ownable
- [Forge Std](https://github.com/foundry-rs/forge-std) — testing utilities
