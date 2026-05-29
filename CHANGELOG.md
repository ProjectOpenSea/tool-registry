# @opensea/tool-registry

## 0.5.0

### Minor Changes

- 1ce2300: Add `ERC20BalancePredicate` for ERC-20 token-balance-gated tool access. Ships a standalone `examples/ERC20BalancePredicate.sol`, a `script/DeployERC20BalancePredicate.s.sol` deploy script, the new `ERC20Balance` requirement type in `IRequirementTypes.sol`, and full test coverage.
- ad8cf93: Set the canonical `ERC20BalancePredicate` address (`0x1a834FC48B5f6e119c62C12a98b32137bCFA77cD`) on Ethereum mainnet and Base.
- f1636af: Deploy `ToolRegistry` and all five canonical predicates to Shape (chain 360) and Abstract (chain 2741) via deterministic CREATE2, at addresses identical to the existing Ethereum mainnet and Base deployments. Adds Shape and Abstract RPC configuration to `foundry.toml` and `.env.example`.

## 0.4.0

### Minor Changes

- 0c28091: Add `TraitGatedPredicate` for ERC-7496 dynamic trait gating. The predicate combines ERC-721 ownership with an on-chain trait value match, supports a separate traits contract (e.g. a renderer), and allows a configurable trait key with up to 32 allowed values per tool. It ships in `script/Deploy.s.sol` and a standalone `script/DeployTraitGatedPredicate.s.sol`, and is deployed deterministically via the Arachnid CREATE2 factory at the canonical address `0x10abF07CfA34Bf22372C57f27e8bd9C2DCF93fA1` on Ethereum mainnet and Base.

## 0.3.0

### Minor Changes

- 27a89da: Canonicalize `SubscriptionPredicate` v0.2 on Ethereum mainnet and Base. The predicate now ships in `script/Deploy.s.sol` at the deterministic CREATE2 address `0xCBe0cd9B1d99d95Baa9c58f2767246C52e461f25` (identical on chain 1 and 8453, deployed via the Arachnid factory with salt `bytes32(uint256(1))` and the v0.2 registry as constructor arg).

## 0.2.0

### Minor Changes

- 427e093: Redeploy `ToolRegistry` + canonical predicates as v0.2 on Ethereum mainnet and Base. The v0.2 registry returns `version() == "0.2"` and accepts predicates that advertise IAccessPredicate interfaceId `0xbdf9dc18` (hasAccess + name + getRequirements). New canonical addresses (identical on chain 1 and 8453): `ToolRegistry` `0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1`; `ERC721OwnerPredicate` `0xc8721c9A776958FfFfEb602DA1b708bf1D318379`; `ERC1155OwnerPredicate` `0x77373Dc3c1AE9A1e937eF3e5E08F4807D47c7c11`. Pre-beta: the previous v0.1 Base deployment is no longer canonical — tools registered there must be re-registered.

## 0.1.2

### Patch Changes

- 23adad6: docs: simplify the ERC draft by ~7%. Folds the standalone Manifest Hex-Field Casing subsection into the Canonical Manifest Bytes bullet (the per-field grammar is already inline at each field's row); replaces duplicated semantic-input JSON in Appendix A with pointers to the §2 example manifests; collapses the Verifiability Trust Model bullet list (which restated §5 verbatim) into a single intro paragraph that cross-references §5; merges Registry Self-Reference and Predicate Selector Collision into Predicate Validation at Registration; trims `hasAccess`'s docstring to a single cross-reference for the strict ABI-bool decode rules. No normative rules changed, no regexes/caps/thresholds touched, no §-renumbering. Pinned `manifestHash` test vectors in Appendix A still verify.

## 0.1.1

### Patch Changes

- 87466ed: docs: clarify that Manifest Parser Hardening caps don't jointly compose. The per-axis upper bounds (e.g. `access.requirements.length: 256` × `access.requirements[].data: 4,096` decoded bytes) would exceed the 1 MiB total-size cap if maxed simultaneously; conformant manifests trade off depth for breadth.
- 5443352: docs: second-pass logic fixes for the ERC draft. Tightens manifest hex-field casing to strict lowercase (`creatorAddress`, `access[].kind`/`data`, `attestation.enclaveHash`, `reproducibleBuild.buildHash`) for JCS-byte determinism, with uppercase hex listed as a verification failure. Mirrors onchain `getRequirements` caps (256 entries, 4,096-byte decoded `data`, 256-byte `label`) into the manifest parser. Restricts `access[].links` values to HTTPS URLs. Fixes a `MUST NOT` inversion in the `tryHasAccess` docstring introduced by the prior commit.
- 94bada5: docs: close logic gaps in the ERC draft. Restates `ToolNotFound` / `ToolIsDeregistered` reverts in each function's docstring; reconciles `setAccessPredicate` MUST-validate with the idempotent no-op carve-out; makes the verifiability `tier` consistency check bidirectional; extends the 256-byte `name()` cap to `version()`; renumbers Access (§4) and Verifiability (§5), bumping Origin-Binding to §6, Creator Binding to §7, Manifest Hash Commitment to §8, ERC-165 Support to §9.

## 0.1.0

Initial pre-release of the OpenSea Tool Registry — onchain registry for AI agent tools (ERC-Draft). Includes core registry contract, predicate gating primitives (ERC721/ERC1155 owner predicates, composite predicates), CREATE2 deploy script for Base, and Base mainnet beta deployment.
