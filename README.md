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
| `TraitGatedPredicate.sol` | ERC-721 ownership + ERC-7496 dynamic trait value match. Supports a separate traits contract (e.g. a renderer). Configurable trait key and up to 32 allowed values per tool |
| `ERC20BalancePredicate.sol` | Account holds ≥ configurable `minBalance` of a specified ERC-20 token (`balanceOf >= minBalance`) |

## Deploy

`script/Deploy.s.sol` deploys `ToolRegistry`, `ERC721OwnerPredicate`, `ERC1155OwnerPredicate`, `SubscriptionPredicate`, and `TraitGatedPredicate` deterministically via the Arachnid keyless CREATE2 factory (pre-deployed at `0x4e59...956C` on every major chain). Re-running with the same salt is a no-op once the address is occupied; swapping in `_SALT` for a vanity salt later deploys the new address on chains that haven't seen it without disturbing existing chains.

To deploy **only the TraitGatedPredicate** (without redeploying other contracts), use the standalone script:

```bash
REGISTRY=0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1 \
NETWORKS=base forge script script/DeployTraitGatedPredicate.s.sol --sig "run()" -vvv \
    --account beta-deployer --sender $DEPLOYER --broadcast --verify
```

To deploy **only the ERC20BalancePredicate**:

```bash
REGISTRY=0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1 \
NETWORKS=base forge script script/DeployERC20BalancePredicate.s.sol --sig "run()" -vvv \
    --account beta-deployer --sender $DEPLOYER --broadcast --verify
```

### Live addresses (pre-beta, salt `bytes32(uint256(1))`)

Canonical v0.2 deployments — same CREATE2 address on every supported chain.

| Contract | Address | Chains |
|---|---|---|
| `ToolRegistry` (v0.2) | [`0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1`](https://etherscan.io/address/0x265bb2dbfc0a8165c9a1941eb1372f349bad2cf1#code) | Ethereum mainnet, Base, Shape, Abstract, Monad |
| `ERC721OwnerPredicate` (v0.2) | [`0xc8721c9A776958FfFfEb602DA1b708bf1D318379`](https://etherscan.io/address/0xc8721c9a776958ffffeb602da1b708bf1d318379#code) | Ethereum mainnet, Base, Shape, Abstract, Monad |
| `ERC1155OwnerPredicate` (v0.2) | [`0x77373Dc3c1AE9A1e937eF3e5E08F4807D47c7c11`](https://etherscan.io/address/0x77373dc3c1ae9a1e937ef3e5e08f4807d47c7c11#code) | Ethereum mainnet, Base, Shape, Abstract, Monad |
| `SubscriptionPredicate` (v0.2) | [`0xCBe0cd9B1d99d95Baa9c58f2767246C52e461f25`](https://etherscan.io/address/0xcbe0cd9b1d99d95baa9c58f2767246c52e461f25#code) | Ethereum mainnet, Base, Shape, Abstract, Monad |
| `TraitGatedPredicate` (v0.2) | [`0x10abF07CfA34Bf22372C57f27e8bd9C2DCF93fA1`](https://etherscan.io/address/0x10abf07cfa34bf22372c57f27e8bd9c2dcf93fa1#code) | Ethereum mainnet, Base, Shape, Abstract, Monad |
| `ERC20BalancePredicate` (v0.2) | [`0x1a834FC48B5f6e119c62C12a98b32137bCFA77cD`](https://etherscan.io/address/0x1a834fc48b5f6e119c62c12a98b32137bcfa77cd#code) | Ethereum mainnet, Base, Shape, Abstract, Monad |

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
