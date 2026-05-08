# ERC-8257 Agent Tool Registry: Reference Implementation

Foundry reference implementation for the **ERC-8257 Agent Tool Registry**: a minimal onchain registry for AI agent tools with extensible predicate-based access control.

Pairs with [`@opensea/tool-sdk`](https://github.com/ProjectOpenSea/tool-sdk) — the TypeScript SDK and CLI for authoring tool manifests, registering tools onchain, and gating tool endpoints against this registry.

## Overview

The standard defines how AI agents discover and access tools through a shared onchain registry that anyone may write to and anyone may read from. Each tool optionally points to an access-predicate contract that gates invocation. The standard deliberately excludes payment, cross-chain gating, and subscription logic, keeping them as orthogonal concerns.

- **Open access**: `accessPredicate` is `address(0)` — anyone can invoke
- **Predicate-gated**: `accessPredicate` points to an external contract implementing `IAccessPredicate` — any access model (NFT gating, subscriptions, allowlists, DAO votes, reputation scores) is expressible as a predicate contract without modifying the registry

## Contracts

| Contract | Interfaces | Description |
|---|---|---|
| `ToolRegistry.sol` | `IToolRegistry` | Tool registration, metadata updates, access delegation |

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

`ToolRegistry` handles tool registration and metadata updates. Access checks are delegated to an external predicate contract via `staticcall`. If a tool's `accessPredicate` is `address(0)`, the tool is open-access. Otherwise, the registry calls `IAccessPredicate(accessPredicate).hasAccess(toolId, account, data)`. Creators who want to temporarily disable a tool point `accessPredicate` at an always-deny predicate rather than carry a dedicated pause flag.

## Example predicates

Reference predicates under `examples/` (not part of the canonical ERC). All multi-tenant: deploy once per chain and configure independently per tool — the predicate keys its config by `toolId` and pulls the authoritative creator from the registry on every write, so any tool creator can configure their own slot without an admin role.

| Contract | Gate |
|---|---|
| `ERC721OwnerPredicate.sol` | Account owns ≥1 token (`balanceOf > 0`) in any of up to 10 configured ERC-721 collections |
| `ERC1155OwnerPredicate.sol` | Account owns ≥1 of any configured `(collection, tokenId)` pair across up to 10 ERC-1155 collections |
| `SubscriptionPredicate.sol` | NFT-tier-with-expiration subscription model |
| `CompositePredicate.sol` | Combines up to 3 leaf `IAccessPredicate` contracts under AND-all / OR-any with optional per-term negation, fail-closed on sub-call failure |

## Deploy

`script/Deploy.s.sol` deploys `ToolRegistry`, `ERC721OwnerPredicate`, and `ERC1155OwnerPredicate` deterministically via the Arachnid keyless CREATE2 factory (pre-deployed at `0x4e59...956C` on every major chain). Re-running with the same salt is a no-op once the address is occupied; swapping in `_SALT` for a vanity salt later deploys the new address on chains that haven't seen it without disturbing existing chains.

### Live addresses (beta, salt `bytes32(uint256(1))`)

| Contract | Base mainnet |
|---|---|
| `ToolRegistry` (v0.1) | [`0x7291BbFbC368C2D478eCe1eA30de31F612a34856`](https://basescan.org/address/0x7291bbfbc368c2d478ece1ea30de31f612a34856#code) |
| `ERC721OwnerPredicate` (v0.2) | [`0xd1F703D0B90BB7106fAebBfbcAdD2B07BDc4c769`](https://basescan.org/address/0xd1f703d0b90bb7106faebbfbcadd2b07bdc4c769#code) |
| `ERC1155OwnerPredicate` (v0.2) | [`0xc179b9d4D9B7ffe0CdA608134729f72003380A7e`](https://basescan.org/address/0xc179b9d4d9b7ffe0cda608134729f72003380a7e#code) |

Each contract advertises its identity onchain via `name()` and `version()` (registry) or `name()` (predicates). See the EIP draft for the version-string format.

### Run

```bash
cp .env.example .env       # fill in BASE_RPC_URL, ETHERSCAN_API_KEY, and one of DEPLOYER (+ keystore) or DEPLOYER_PRIVATE_KEY

# Dry-run (simulation only)
NETWORKS=base forge script script/Deploy.s.sol --sig "run()" -vvv

# Broadcast + verify (keystore-based — preferred)
cast wallet import beta-deployer --interactive   # one-time keystore import
NETWORKS=base forge script script/Deploy.s.sol --sig "run()" -vvv \
    --account beta-deployer --sender $DEPLOYER --broadcast --verify

# Broadcast + verify (raw private key — one-shot)
DEPLOYER_PRIVATE_KEY=0x... NETWORKS=base forge script script/Deploy.s.sol \
    --sig "run()" -vvv --broadcast --verify
```

The deploy script reads `NETWORKS` (comma-separated keys from `[rpc_endpoints]` in `foundry.toml`) and forks each in turn. Verification uses the Etherscan v2 unified API key (`ETHERSCAN_API_KEY`), which works across all Etherscan-supported chains including Base.

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts): ERC-165
- [Forge Std](https://github.com/foundry-rs/forge-std): testing utilities
- [create2-helpers](https://github.com/emo-eth/create2-helpers): CREATE2 deploy script base
