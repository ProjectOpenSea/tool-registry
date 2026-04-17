# ERC-XXXX Agent Tool Registry: Reference Implementation

Foundry reference implementation for the **ERC-XXXX Agent Tool Registry**: an onchain registry for AI agent tools with open, NFT-gated (same- and cross-chain), and subscription access modes.

## Overview

The standard defines how AI agents discover and access tools through a shared onchain registry that anyone may write to and anyone may read from. It introduces three access modes:

- **OPEN**: anyone can invoke (free or paid per invocation)
- **NFT_GATED**: caller must hold a token from a bound ERC-721 or ERC-1155 collection (same-chain by `balanceOf`, or cross-chain via a gateway-signed EIP-712 attestation)
- **SUBSCRIPTION**: caller must hold an active ERC-5643 subscription NFT

## Contracts

| Contract | Interfaces | Description |
|---|---|---|
| `ToolRegistry.sol` | `IToolRegistry` | Tool registration, metadata updates, lifecycle management, access delegation |
| `ToolAccessRegistry.sol` | `IToolAccessRegistry`, `IToolAccessRegistryCrossChain` | Same-chain and cross-chain NFT-gating, collection bindings, subscription expiration checks |
| `GatewayKeyRegistry.sol` | `IGatewayKeyRegistry` | Admin-managed gateway signing keys for EIP-712 cross-chain attestations. Required when cross-chain bindings are used; MAY be omitted otherwise |

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

`ToolRegistry` delegates all access checks to `ToolAccessRegistry` via the `IToolAccessRegistry.hasAccess()` interface. The two contracts are linked using a two-step initialization pattern to resolve the circular dependency. `ToolAccessRegistry` also takes an `IGatewayKeyRegistry` address for cross-chain attestation verification; pass `address(0)` if the deployment does not offer cross-chain bindings.

```solidity
ToolRegistry registry = new ToolRegistry();
GatewayKeyRegistry keyRegistry = new GatewayKeyRegistry(admin);
ToolAccessRegistry accessRegistry = new ToolAccessRegistry(address(registry), address(keyRegistry));
registry.initialize(address(accessRegistry));
```

For `OPEN` tools, `hasAccess()` returns `true` unconditionally. For `NFT_GATED` tools, it checks `balanceOf` on bound collections (OR logic: any collection grants access). For `SUBSCRIPTION` tools, callers use `hasAccessWithProof(toolId, account, tokenId)` which also checks `IERC5643.expiresAt(tokenId) > block.timestamp`. Cross-chain `NFT_GATED` bindings use `hasAccessWithRemoteProof(toolId, account, proof)`, which recovers the gateway signer from an EIP-712 attestation and verifies it against `GatewayKeyRegistry`.

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts): ERC-165, ERC-721, ERC-1155, ERC-20, Ownable
- [Forge Std](https://github.com/foundry-rs/forge-std): testing utilities
