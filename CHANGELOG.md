# @opensea/tool-registry

## 0.1.1

### Patch Changes

- 87466ed: docs: clarify that Manifest Parser Hardening caps don't jointly compose. The per-axis upper bounds (e.g. `access.requirements.length: 256` × `access.requirements[].data: 4,096` decoded bytes) would exceed the 1 MiB total-size cap if maxed simultaneously; conformant manifests trade off depth for breadth.
- 5443352: docs: second-pass logic fixes for the ERC draft. Tightens manifest hex-field casing to strict lowercase (`creatorAddress`, `access[].kind`/`data`, `attestation.enclaveHash`, `reproducibleBuild.buildHash`) for JCS-byte determinism, with uppercase hex listed as a verification failure. Mirrors onchain `getRequirements` caps (256 entries, 4,096-byte decoded `data`, 256-byte `label`) into the manifest parser. Restricts `access[].links` values to HTTPS URLs. Fixes a `MUST NOT` inversion in the `tryHasAccess` docstring introduced by the prior commit.
- 94bada5: docs: close logic gaps in the ERC draft. Restates `ToolNotFound` / `ToolIsDeregistered` reverts in each function's docstring; reconciles `setAccessPredicate` MUST-validate with the idempotent no-op carve-out; makes the verifiability `tier` consistency check bidirectional; extends the 256-byte `name()` cap to `version()`; renumbers Access (§4) and Verifiability (§5), bumping Origin-Binding to §6, Creator Binding to §7, Manifest Hash Commitment to §8, ERC-165 Support to §9.

## 0.1.0

Initial pre-release of the OpenSea Tool Registry — onchain registry for AI agent tools (ERC-Draft). Includes core registry contract, predicate gating primitives (ERC721/ERC1155 owner predicates, composite predicates), CREATE2 deploy script for Base, and Base mainnet beta deployment.
