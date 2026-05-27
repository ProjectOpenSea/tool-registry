# tool-registry — Agent Conventions

Foundry/Solidity package implementing the ERC-8257 Agent Tool Registry standard.

## Quick Reference

```bash
cd packages/tool-registry
forge build                  # Compile contracts
forge test                   # Run all tests (including interface ID pins)
forge fmt --check            # Check formatting
forge fmt                    # Auto-format
forge lint src/ examples/    # Lint Solidity (also enforced via lint-staged)
```

Solidity version: `0.8.28` (set in `foundry.toml`).
Formatter: 120 char line width, 4-space tabs, no bracket spacing.

## Architecture

| File | Role |
|------|------|
| `src/interfaces/IToolRegistry.sol` | Canonical interface — all public functions the registry exposes |
| `src/interfaces/IAccessPredicate.sol` | Predicate interface — `hasAccess()` + `name()` |
| `src/interfaces/IRequirementTypes.sol` | Requirement-type selectors (`IERC721Holding`, `IERC1155Holding`, `ISubscription`) for predicate `kind` values |
| `src/ToolRegistry.sol` | Reference implementation |
| `examples/` | Canonical predicate implementations (ERC721, ERC1155, Subscription, Composite) |
| `test/` | Foundry tests; mocks live in `test/mocks/` for edge-case predicate behavior |
| `script/Deploy.s.sol` | Deterministic CREATE2 deployment script |
| `scripts/generate-test-vectors.ts` | TypeScript helper to produce ABI-encoded test inputs (its own pnpm project) |
| `scripts/check-abi-sync.sh` | CI script verifying TypeScript ABIs in `tool-sdk` match Forge build output |
| ERC-8257 spec (currently in review: https://github.com/ethereum/ERCs/pull/1723) | Standard — code must mirror its interface IDs and behavior |
| `lib/` | Foundry dependencies via git submodules (forge-std, OpenZeppelin, create2-helpers) |

## Review Checklist

When reviewing changes to this package, verify:

1. **ERC-165 interface IDs**: Adding or removing a function from `IToolRegistry` or `IAccessPredicate` changes the interface ID (XOR of function selectors). If the interface changed:
   - The pinned interface ID test in `test/ToolRegistry.t.sol` must be updated
   - The ERC-8257 spec must reflect the new ID — changes go through the upstream ERCs PR (https://github.com/ethereum/ERCs/pull/1723 while in review; switch to https://ercs.ethereum.org/ERCS/erc-8257 once merged)
   - This is a **breaking change** for third-party implementors — document it in the changeset

2. **Cross-file sync**: These files must stay in sync:
   - Solidity interfaces (`src/interfaces/`) ↔ TypeScript ABIs (`../tool-sdk/src/lib/onchain/abis.ts`)
   - Deployed addresses in `README.md` ↔ `../tool-sdk/src/lib/onchain/chains.ts`
   - Every function in the Solidity interface should have a corresponding entry in the TypeScript ABI
   - Requirement-type selectors in `src/interfaces/IRequirementTypes.sol` ↔ `kind` values in `../tool-sdk/SKILLS.md` "Known Predicates" section
   - Deployed predicate addresses in `README.md` ↔ `../tool-sdk/SKILLS.md` "Deployed Contracts" table
   - New predicates added to `examples/` must get a corresponding entry in `../tool-sdk/SKILLS.md`

3. **Access control on state-mutating functions**: Only the tool creator should be able to call `updateToolMetadata`, `setAccessPredicate`, and predicate configuration functions like `setCollections`. Verify `NotToolCreator` / creator checks exist.

4. **Multi-transaction atomicity**: Registration flows that require multiple transactions (e.g., `registerTool` then `setCollections`) can leave the tool in a partially configured state if the second TX fails. The CLI must print recovery instructions for the manual completion step.

5. **Predicate validation**: `_validatePredicate` uses ERC-165 `supportsInterface` to verify predicates. Changes to `IAccessPredicate` change the expected interface ID, breaking existing predicates. Call this out explicitly in changesets.

6. **Pure/view correctness**: `name()`, `version()`, and `hasAccess()` must be `view` or `pure`. State-reading predicates use `staticcall` — any attempt to mutate state in `hasAccess` will revert.

## Conventions

- Predicate contracts are multi-tenant: one deployment per chain, configured per `toolId`.
- Predicates key their config by `toolId` and pull the authoritative creator from the registry — no separate admin role.
- `address(0)` as `accessPredicate` means open access. Always-deny is a separate predicate contract, not a flag.
- Interface-only additions to `IAccessPredicate` or `IToolRegistry` are breaking changes (interface ID changes).
- The versioning scheme is `MAJOR.MINOR` (not semver). `"0.1"` = pre-release, `"1.0"` = first stable.

## Testing

- **Interface ID pin tests**: `test_interfaceId_*_pinned` tests assert exact interface ID values. Update them when interfaces change.
- **Mock predicates**: `test/mocks/` contains edge-case predicates (reverting, gas-burning, deny-all, etc.) for testing registry resilience.
- Run the full suite (`forge test`) after any change — interface ID tests catch accidental signature changes.
