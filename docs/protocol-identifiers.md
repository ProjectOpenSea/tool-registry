# Well-Known Payment Protocol Identifiers

Non-normative registry of payment protocol identifiers referenced by the `pricing.protocols` array in an ERC-XXXX Tool Manifest. Protocol identifiers are opaque strings; interoperability requires only that a gateway and a manifest agree on a shared string. This list is informative and MAY be extended by implementers without any change to the core standard.

## Registered Identifiers

| Identifier | Protocol | Description |
| --- | --- | --- |
| `x402` | [x402](https://github.com/coinbase/x402) | HTTP 402-based micropayments with `upto` (variable-cost) support. |
| `mpp` | [MPP](https://mpp.dev/) | Machine Payments Protocol for machine-to-machine payments. |
| `erc20-transfer` | Direct ERC-20 | Direct onchain token transfer from caller to the tool's payment recipient before invocation. |

## Adding a New Identifier

To propose a new well-known identifier:

1. Pick a short, lowercase, hyphen-separated string that does not collide with an existing entry.
2. Open a pull request against this file that adds a new row to the table above with:
   - a canonical link to the protocol specification or reference implementation,
   - a one-sentence description of the payment semantics,
   - whether the protocol supports fixed (`amount`) pricing, variable (`maxAmount`) pricing, or both.
3. Reference an existing tool that uses the identifier in production if possible.

Gateway implementations SHOULD support at least one of the identifiers listed here so that the common set of tools is reachable out-of-the-box.
