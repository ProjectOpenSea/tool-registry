#!/usr/bin/env bash
# Verifies that the IToolRegistryABI in tool-sdk/abis.ts matches the Forge
# build output.  Exits non-zero on drift so CI catches stale TypeScript ABIs.
#
# Usage:  ./scripts/check-abi-sync.sh          (from packages/tool-registry/)
# Prereq: `forge build` must have been run first.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
FORGE_JSON="$REPO_ROOT/packages/tool-registry/out/IToolRegistry.sol/IToolRegistry.json"
ABIS_TS="$REPO_ROOT/packages/tool-sdk/src/lib/onchain/abis.ts"

if [[ ! -f "$FORGE_JSON" ]]; then
  echo "ERROR: Forge build output not found at $FORGE_JSON"
  echo "       Run 'forge build' first."
  exit 1
fi

if [[ ! -f "$ABIS_TS" ]]; then
  echo "ERROR: TypeScript ABI file not found at $ABIS_TS"
  exit 1
fi

# Extract a normalised JSON representation from both sources and diff them.
# "Normalised" means: sorted by (type, name), stripped of Forge-only fields
# (internalType, anonymous), inputs sorted to a consistent shape.
node --input-type=module -e "
import { readFileSync } from 'fs';

// --- Forge ABI (source of truth) ---
const forge = JSON.parse(readFileSync('$FORGE_JSON', 'utf8')).abi;

function strip(obj) {
  if (Array.isArray(obj)) return obj.map(strip);
  if (obj && typeof obj === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(obj)) {
      if (k === 'internalType' || k === 'anonymous') continue;
      out[k] = strip(v);
    }
    return out;
  }
  return obj;
}

function sortKey(e) {
  const order = { event: 0, error: 1, function: 2 };
  return (order[e.type] ?? 99) + ':' + (e.name ?? '');
}

const forgeNorm = strip(forge).sort((a, b) => sortKey(a).localeCompare(sortKey(b)));

// --- TypeScript ABI ---
const tsSource = readFileSync('$ABIS_TS', 'utf8');
// Extract the array between 'export const IToolRegistryABI = [' and '] as const'
const match = tsSource.match(/export const IToolRegistryABI\s*=\s*(\[[\s\S]*?\])\s*as\s*const/);
if (!match) {
  console.error('ERROR: Could not find IToolRegistryABI in abis.ts');
  process.exit(1);
}
// Evaluate the array literal (safe: only contains object/array/string/number/boolean literals)
const tsAbi = eval('(' + match[1] + ')');
const tsNorm = strip(tsAbi).sort((a, b) => sortKey(a).localeCompare(sortKey(b)));

// --- Compare ---
const forgeStr = JSON.stringify(forgeNorm, null, 2);
const tsStr = JSON.stringify(tsNorm, null, 2);

if (forgeStr === tsStr) {
  console.log('OK: IToolRegistryABI in abis.ts matches Forge build output.');
  process.exit(0);
} else {
  console.error('MISMATCH: IToolRegistryABI in abis.ts does not match Forge build output.');
  console.error('');
  console.error('Expected (from Forge):');
  console.error(forgeStr);
  console.error('');
  console.error('Actual (from abis.ts):');
  console.error(tsStr);
  console.error('');
  console.error('Please regenerate abis.ts from the compiled Solidity interface.');
  process.exit(1);
}
"
