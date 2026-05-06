/**
 * Generates the reference test vectors for the ERC-Draft Tool Registry spec.
 *
 * Produces:
 *   - The JCS (RFC 8785) canonical bytes for two reference manifests.
 *   - The keccak256 hash of each canonical byte sequence.
 *   - Hash-divergence vectors for NFC-vs-NFD and with-BOM-vs-without-BOM.
 *
 * Run:  pnpm install && pnpm generate   (from this directory)
 */

import { keccak_256 } from "@noble/hashes/sha3.js"
import { bytesToHex } from "@noble/hashes/utils.js"
import canonicalize from "canonicalize"

type Manifest = Record<string, unknown>

function jcsBytes(obj: unknown): Uint8Array {
  const canonical = canonicalize(obj)
  if (canonical === undefined) {
    throw new Error("JCS canonicalization returned undefined")
  }
  return new TextEncoder().encode(canonical)
}

function kh(b: Uint8Array): string {
  return `0x${bytesToHex(keccak_256(b))}`
}

const FREE_TOOL: Manifest = {
  type: "https://eips.ethereum.org/EIPS/eip-draft#tool-manifest-v1",
  name: "nft-price-oracle",
  description: "Returns estimated floor price for any NFT collection.",
  endpoint: "https://tools.example.com/nft-price-oracle",
  inputs: {
    type: "object",
    properties: {
      collection: { type: "string", description: "Contract address" },
      chainId: { type: "integer" },
    },
    required: ["collection", "chainId"],
  },
  outputs: {
    type: "object",
    properties: {
      floorPriceEth: { type: "string" },
      updatedAt: { type: "string", format: "date-time" },
    },
  },
  version: "1.0.0",
  tags: ["nft", "pricing", "oracle"],
  creatorAddress: "0xabcdefabcdef1234567890abcdefabcdef123456",
}

const PAID_TOOL: Manifest = {
  type: "https://eips.ethereum.org/EIPS/eip-draft#tool-manifest-v1",
  name: "premium-analytics",
  description: "Advanced portfolio analytics for NFT holders.",
  endpoint: "https://tools.example.com/premium-analytics",
  inputs: {
    type: "object",
    properties: {
      wallet: { type: "string", description: "Wallet address to analyze" },
    },
    required: ["wallet"],
  },
  outputs: {
    type: "object",
    properties: {
      totalValue: { type: "string" },
      breakdown: { type: "array" },
    },
  },
  version: "1.0.0",
  tags: ["analytics", "portfolio"],
  pricing: [
    {
      amount: "20000",
      asset: "eip155:8453/erc20:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      recipient: "eip155:8453:0xabcdef0123456789abcdef0123456789abcdef01",
      protocol: "x402",
    },
    {
      amount: "20000",
      asset: "eip155:1/erc20:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      recipient: "eip155:1:0xabcdef0123456789abcdef0123456789abcdef01",
      protocol: "x402",
    },
  ],
  creatorAddress: "0xabcdef0123456789abcdef0123456789abcdef01",
}

function showReference(label: string, obj: Manifest): void {
  const canonical = jcsBytes(obj)
  const h = kh(canonical)
  console.log(`\n### ${label}\n`)
  console.log(`- Canonical byte length: ${canonical.length}`)
  console.log(`- keccak256:             ${h}`)
  console.log("- Canonical bytes (JCS, UTF-8):")
  console.log()
  console.log(`  ${new TextDecoder().decode(canonical)}`)
}

function showMatchingToolConfig(args: {
  label: string
  obj: Manifest
  toolId: number
  registryChain: string
  registryAddr: string
  predicate: string
}): void {
  const canonical = jcsBytes(args.obj)
  const h = kh(canonical)
  const metadataURI = `https://tools.example.com/.well-known/ai-tool/${args.obj.name}.json`
  console.log(`\n### ${args.label}: matching ToolConfig\n`)
  console.log("```")
  console.log("ToolConfig {")
  console.log(`    creator:         ${args.obj.creatorAddress},`)
  console.log(`    metadataURI:     '${metadataURI}',`)
  console.log(`    manifestHash:    ${h},`)
  console.log(`    accessPredicate: ${args.predicate}`)
  console.log("}")
  console.log("```")
  console.log()
  console.log(
    `- Tool ID (scoped to \`${args.registryChain}\` and \`${args.registryAddr}\`): \`${args.toolId}\``,
  )
  console.log(
    `- Canonical CAIP-19 tool reference: \`${args.registryChain}/erc-draft:${args.registryAddr}/${args.toolId}\``,
  )
}

function showNfcNfdDivergence(): void {
  // `name` uses a single non-ASCII grapheme ("café-oracle") that has
  // two valid Unicode forms: NFC uses U+00E9 (one codepoint),
  // NFD decomposes to "e" + U+0301 (two codepoints).
  const baseNfc = "café-oracle".normalize("NFC")
  const baseNfd = baseNfc.normalize("NFD")
  if (baseNfc === baseNfd) {
    throw new Error("NFC and NFD forms should differ")
  }

  const make = (name: string): Manifest => ({
    type: "https://eips.ethereum.org/EIPS/eip-draft#tool-manifest-v1",
    name,
    description: "NFC/NFD divergence sample.",
    endpoint: "https://tools.example.com/cafe",
    inputs: {},
    outputs: {},
    creatorAddress: "0x0000000000000000000000000000000000000001",
  })

  const nfcBytes = jcsBytes(make(baseNfc))
  const nfdBytes = jcsBytes(make(baseNfd))

  console.log("\n### NFC vs NFD divergence\n")
  console.log("Two manifests that differ only in the Unicode form of `name`:")
  console.log()
  console.log(
    `- NFC form:  name = '${baseNfc}' (${[...baseNfc].length} codepoints, U+00E9)`,
  )
  console.log(`  - Canonical byte length: ${nfcBytes.length}`)
  console.log(`  - keccak256:             ${kh(nfcBytes)}`)
  console.log(
    `- NFD form:  name = '${baseNfd}' (${[...baseNfd].length} codepoints, 'e' + U+0301)`,
  )
  console.log(`  - Canonical byte length: ${nfdBytes.length}`)
  console.log(`  - keccak256:             ${kh(nfdBytes)}`)
  console.log()
  console.log("The ERC requires NFC; a consumer that fetches the NFD form MUST")
  console.log("reject it rather than silently re-normalizing, because silent")
  console.log("re-normalization would change the bytes fed to keccak256.")
}

function showBomDivergence(): void {
  const obj: Manifest = {
    type: "https://eips.ethereum.org/EIPS/eip-draft#tool-manifest-v1",
    name: "bom-sample",
    description: "Byte-order-mark divergence sample.",
    endpoint: "https://tools.example.com/bom",
    inputs: {},
    outputs: {},
    creatorAddress: "0x0000000000000000000000000000000000000002",
  }
  const clean = jcsBytes(obj)
  const withBom = new Uint8Array(3 + clean.length)
  withBom.set([0xef, 0xbb, 0xbf], 0)
  withBom.set(clean, 3)

  console.log("\n### BOM vs no-BOM divergence\n")
  console.log(
    "Same JCS canonical bytes, served with and without a UTF-8 BOM prefix:",
  )
  console.log()
  console.log(`- Without BOM: length ${clean.length}, keccak256 ${kh(clean)}`)
  console.log(
    `- With BOM:    length ${withBom.length} (= ${clean.length} + 3), keccak256 ${kh(withBom)}`,
  )
  console.log()
  console.log(
    "The ERC requires the manifest to be served without a BOM; a consumer",
  )
  console.log(
    "that receives an EF BB BF prefix MUST reject the response rather than",
  )
  console.log(
    "silently stripping the BOM, because silent stripping would change the",
  )
  console.log("bytes fed to keccak256.")
}

console.log("# Reference Test Vectors\n")
console.log("This output is generated by `scripts/generate-test-vectors.ts`.")
console.log("Re-run to reproduce after editing the spec's example manifests.")

const REGISTRY_CHAIN = "eip155:8453"
const REGISTRY_ADDR = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

showReference("Free-tool manifest", FREE_TOOL)
showMatchingToolConfig({
  label: "Free-tool manifest",
  obj: FREE_TOOL,
  toolId: 1,
  registryChain: REGISTRY_CHAIN,
  registryAddr: REGISTRY_ADDR,
  predicate: "0x0000000000000000000000000000000000000000",
})

showReference("Paid-tool manifest", PAID_TOOL)
showMatchingToolConfig({
  label: "Paid-tool manifest",
  obj: PAID_TOOL,
  toolId: 2,
  registryChain: REGISTRY_CHAIN,
  registryAddr: REGISTRY_ADDR,
  predicate: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
})

showNfcNfdDivergence()
showBomDivergence()
