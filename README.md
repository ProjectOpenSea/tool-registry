# ERC-8257 Agent Tool Registry: Reference Implementation

Foundry reference implementation of the **ERC-8257 Agent Tool Registry**, a minimal onchain registry for AI agent tools with predicate-based access control.

[`@opensea/tool-sdk`](https://github.com/ProjectOpenSea/tool-sdk) is the TypeScript SDK and CLI for writing tool manifests, registering tools, and gating tool endpoints against this registry.

## Overview

Anyone can register a tool in the registry, and anyone can read it. Each tool has an optional access predicate:

- If `accessPredicate` is `address(0)`, anyone can invoke the tool.
- Otherwise it points to a contract implementing `IAccessPredicate`. NFT gating, subscriptions, allowlists, DAO votes, and reputation scores can all be written as predicates without changing the registry.

Payment, cross-chain gating, and subscription billing are out of scope for the standard.

## Contracts

| Contract | Interfaces | Description |
|---|---|---|
| `ToolRegistry.sol` | `IToolRegistry` | Tool registration, metadata updates, access delegation |

`ToolRegistry` stores tools and their metadata. For a gated tool it checks access with a `staticcall` to `IAccessPredicate(accessPredicate).hasAccess(toolId, account, data)`. There is no pause flag: to disable a tool temporarily, point `accessPredicate` at a predicate that always denies.

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

## Gas report

```bash
forge test --gas-report
```

## Example predicates

The predicates in `examples/` are references, not part of the ERC. Each is multi-tenant: deploy it once per chain and every tool keeps its own config, keyed by `toolId`. On each config write the predicate reads the tool's creator from the registry, so creators configure their own tools without an admin role.

| Contract | Gate |
|---|---|
| `ERC721OwnerPredicate.sol` | Account owns at least one token (`balanceOf > 0`) in any of up to 10 configured ERC-721 collections |
| `ERC1155OwnerPredicate.sol` | Account owns at least one of any configured `(collection, tokenId)` pair, across up to 10 ERC-1155 collections with up to 16 token IDs each |
| `SubscriptionPredicate.sol` | Subscription: an NFT tier with an expiration time |
| `CompositePredicate.sol` | Combines up to 3 `IAccessPredicate` contracts with AND or OR, optionally negating each term. Fails closed if a sub-call fails |
| `TraitGatedPredicate.sol` | ERC-721 ownership plus a matching ERC-7496 dynamic trait value. The traits can live on a separate contract (such as a renderer). Each tool sets the trait key and up to 32 allowed values |
| `ERC20BalancePredicate.sol` | Account holds at least `minBalance` of a configured ERC-20 token (`balanceOf >= minBalance`) |

## Deploy

`script/Deploy.s.sol` deploys `ToolRegistry`, `ERC721OwnerPredicate`, `ERC1155OwnerPredicate`, `SubscriptionPredicate`, and `TraitGatedPredicate` through the Arachnid keyless CREATE2 factory (`0x4e59...956C`, already deployed on every major chain), so addresses match across chains. Re-running with the same salt does nothing where the address is already occupied. Changing `_SALT` (for a vanity address, say) deploys the new address on chains that lack it and leaves existing deployments alone.

`ERC20BalancePredicate` and `TraitGatedPredicate` also have standalone scripts, so you can deploy either one without the rest:

```bash
REGISTRY=0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1 \
NETWORKS=base forge script script/DeployTraitGatedPredicate.s.sol --sig "run()" -vvv \
    --account beta-deployer --sender $DEPLOYER --broadcast --verify
```

```bash
REGISTRY=0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1 \
NETWORKS=base forge script script/DeployERC20BalancePredicate.s.sol --sig "run()" -vvv \
    --account beta-deployer --sender $DEPLOYER --broadcast --verify
```

### Live addresses (pre-beta, salt `bytes32(uint256(1))`)

Canonical v0.2 deployments, at the same CREATE2 address on every supported chain.

| Contract | Address | Chains |
|---|---|---|
| `ToolRegistry` (v0.2) | [`0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1`](https://etherscan.io/address/0x265bb2dbfc0a8165c9a1941eb1372f349bad2cf1#code) | Ethereum mainnet, Base, Shape, Abstract, Monad, Robinhood Chain |
| `ERC721OwnerPredicate` (v0.2) | [`0xc8721c9A776958FfFfEb602DA1b708bf1D318379`](https://etherscan.io/address/0xc8721c9a776958ffffeb602da1b708bf1d318379#code) | Ethereum mainnet, Base, Shape, Abstract, Monad, Robinhood Chain |
| `ERC1155OwnerPredicate` (v0.2) | [`0x77373Dc3c1AE9A1e937eF3e5E08F4807D47c7c11`](https://etherscan.io/address/0x77373dc3c1ae9a1e937ef3e5e08f4807d47c7c11#code) | Ethereum mainnet, Base, Shape, Abstract, Monad, Robinhood Chain |
| `SubscriptionPredicate` (v0.2) | [`0xCBe0cd9B1d99d95Baa9c58f2767246C52e461f25`](https://etherscan.io/address/0xcbe0cd9b1d99d95baa9c58f2767246c52e461f25#code) | Ethereum mainnet, Base, Shape, Abstract, Monad, Robinhood Chain |
| `TraitGatedPredicate` (v0.2) | [`0x10abF07CfA34Bf22372C57f27e8bd9C2DCF93fA1`](https://etherscan.io/address/0x10abf07cfa34bf22372c57f27e8bd9c2dcf93fa1#code) | Ethereum mainnet, Base, Shape, Abstract, Monad, Robinhood Chain |
| `ERC20BalancePredicate` (v0.2) | [`0x1a834FC48B5f6e119c62C12a98b32137bCFA77cD`](https://etherscan.io/address/0x1a834fc48b5f6e119c62c12a98b32137bcfa77cd#code) | Ethereum mainnet, Base, Shape, Abstract, Monad, Robinhood Chain |

The registry reports its identity onchain through `name()` and `version()`, and each predicate through `name()`. The EIP draft defines the version string format.

### Run

```bash
cp .env.example .env       # fill in BASE_RPC_URL, ETHERSCAN_API_KEY, and one of DEPLOYER (+ keystore) or DEPLOYER_PRIVATE_KEY

# Dry-run (simulation only)
NETWORKS=base forge script script/Deploy.s.sol --sig "run()" -vvv

# Broadcast + verify (keystore-based, preferred)
cast wallet import beta-deployer --interactive   # one-time keystore import
NETWORKS=base forge script script/Deploy.s.sol --sig "run()" -vvv \
    --account beta-deployer --sender $DEPLOYER --broadcast --verify

# Broadcast + verify (raw private key, one-shot)
DEPLOYER_PRIVATE_KEY=0x... NETWORKS=base forge script script/Deploy.s.sol \
    --sig "run()" -vvv --broadcast --verify
```

`NETWORKS` is a comma-separated list of keys from `[rpc_endpoints]` in `foundry.toml`, and the script forks each network in turn. Verification uses one Etherscan v2 API key (`ETHERSCAN_API_KEY`), which covers every Etherscan-supported chain, Base included.

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts): ERC-165
- [Forge Std](https://github.com/foundry-rs/forge-std): testing utilities
- [create2-helpers](https://github.com/emo-eth/create2-helpers): CREATE2 deploy script base

## Contributing

Read-only mirror of a private monorepo, updated on each release. Pull requests are welcome, and we bring accepted changes into the monorepo.

## Security

Found a vulnerability? Report it through OpenSea's Bugcrowd program at https://bugcrowd.com/engagements/opensea rather than opening a public issue. See [SECURITY.md](SECURITY.md).
