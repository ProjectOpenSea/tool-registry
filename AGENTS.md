# tool-registry — Agent Conventions

Foundry/Solidity package implementing the ERC-8257 Agent Tool Registry standard.

## Quick commands

```bash
cd packages/tool-registry
forge build
forge test
forge fmt --check
forge lint src/ examples/
./scripts/check-abi-sync.sh   # after forge build; ABI ↔ tool-sdk drift
```

## Responsibilities

- `ToolRegistry` reference implementation and canonical interfaces.
- Example `IAccessPredicate` implementations under `examples/`.
- Deterministic CREATE2 deployment scripts.

## Rules

1. **Interface IDs are breaking changes**. Adding/removing a function in `IToolRegistry` or `IAccessPredicate` changes the ERC-165 interface ID. Update pinned tests and the ERC-8257 spec. This package is outside the pnpm workspace, so bump `package.json`/`CHANGELOG.md` by hand instead of writing a changeset.
2. **Cross-file sync** (same PR when changing any side):
   - Solidity interfaces ↔ TypeScript ABIs in `packages/tool-sdk/src/lib/onchain/abis.ts` (CI runs `scripts/check-abi-sync.sh`)
   - Deployed addresses in `README.md` ↔ `packages/tool-sdk/src/lib/onchain/chains.ts`
   - Requirement selectors in `IRequirementTypes.sol` ↔ `packages/tool-sdk/skill/references/known-predicates.md`
   - New predicates in `examples/` ↔ `packages/tool-sdk/skill/references/known-predicates.md`
   - New chains: `foundry.toml` RPC/etherscan entries, `README.md` chains column, `chains.ts` deployments, and skill docs.
3. **Access control**. State-mutating registry and predicate functions must verify the caller is the tool creator.
4. **Pure/view safety**. `name()`, `version()`, and `hasAccess()` must be `view`/`pure`; state mutation inside `staticcall` reverts.
5. **Atomicity**. Multi-transaction registration flows can leave partial state; CLI must print recovery instructions.

## Conventions

- Solidity `0.8.28`, 120-char line width, 4-space tabs, no bracket spacing.
- Multi-tenant predicates: one deployment per chain, configured per `toolId` with no separate admin.
- `address(0)` as `accessPredicate` means open access; always-deny is a separate predicate.
- Contract `version()` is `MAJOR.MINOR`, not semver (`package.json` versioning is separate).
