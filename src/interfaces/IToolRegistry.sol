// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Onchain configuration for a registered tool.
struct ToolConfig {
    address creator; // Address that registered the tool (immutable after registration)
    string metadataURI; // Resolves to Tool Manifest JSON
    bytes32 manifestHash; // keccak256 of the canonical manifest bytes at metadataURI
    address accessPredicate; // address(0) = open access; otherwise, gating contract
}

/// @title IToolRegistry
/// @notice Minimal onchain registry for AI agent tools.
/// @dev ERC-165 interface ID: 0xf1dc8075
interface IToolRegistry {
    /* is IERC165 */
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a new tool is registered.
    /// @dev The event carries `metadataURI` (non-indexed) alongside
    ///      `manifestHash` so indexers can resolve a new tool without a
    ///      follow-up `getToolConfig` call. `string` cannot participate
    ///      in the topic set, so filter by `toolId`, `creator`, or
    ///      `accessPredicate` at the topic layer and parse `metadataURI`
    ///      from the log data.
    event ToolRegistered(
        uint256 indexed toolId,
        address indexed creator,
        address indexed accessPredicate,
        string metadataURI,
        bytes32 manifestHash
    );

    /// @notice Emitted when a tool's metadata URI and/or manifest hash is updated.
    event ToolMetadataUpdated(uint256 indexed toolId, string newURI, bytes32 newHash);

    /// @notice Emitted when a tool's access predicate is updated.
    event AccessPredicateUpdated(uint256 indexed toolId, address indexed newPredicate);

    /// @notice Emitted when a tool is permanently deregistered by its creator.
    event ToolDeregistered(uint256 indexed toolId);

    // ──────────────────── Errors ────────────────────

    /// @notice The specified tool ID does not exist.
    error ToolNotFound(uint256 toolId);

    /// @notice Caller is not the tool's creator.
    error NotToolCreator(uint256 toolId, address caller);

    /// @notice The provided metadata URI is invalid.
    /// @dev Implementations MUST revert with this error when `metadataURI` is
    ///      the empty string or longer than 2,048 bytes (see
    ///      [Metadata URI Length Cap](#metadata-uri-length-cap)).
    ///      Implementations MAY additionally reject URIs that fail
    ///      implementation-specific validation beyond these checks.
    error InvalidMetadataURI();

    /// @notice The provided manifest hash is `bytes32(0)`.
    /// @dev `keccak256` of any real content cannot produce `bytes32(0)`, so
    ///      a zero hash is semantically meaningless as a commitment.
    error InvalidManifestHash();

    /// @notice The provided access predicate claims ERC-165 support but does
    ///         not advertise `IAccessPredicate`.
    /// @dev Implementations MUST revert with this error from `registerTool`
    ///      and `setAccessPredicate` when the candidate predicate returns
    ///      `true` for `type(IERC165).interfaceId` but then returns `false`
    ///      (or reverts) when queried for `type(IAccessPredicate).interfaceId`.
    ///      A predicate address with no deployed code, or one that does not
    ///      claim ERC-165 support, is accepted as best-effort (see
    ///      [Zero-Code Access Predicates](#zero-code-access-predicates) and
    ///      [Predicate Validation at Registration](#predicate-validation-at-registration)).
    ///      The error is not required to reach the ERC-165 interface ID
    ///      check (it does not participate in any function selector);
    ///      implementations MAY substitute an equivalent error provided the
    ///      validation behavior matches.
    error InvalidAccessPredicate(address predicate);

    /// @notice The tool has been permanently deregistered by its creator.
    /// @dev Implementations MUST revert with this error when any operation
    ///      targets a tool ID that was previously deregistered via
    ///      `deregisterTool`. This allows consumers to distinguish a tool
    ///      that was explicitly removed from one that never existed.
    error ToolIsDeregistered(uint256 toolId);

    // ──────────────────── Registration ────────────────────

    /// @notice Register a new tool. The caller becomes the tool's creator.
    /// @dev The tool's `creator` is set to `msg.sender` and cannot be changed.
    ///      `manifestHash` is `keccak256` over the canonical manifest bytes
    ///      served at `metadataURI`. Consumers SHOULD reject manifests whose
    ///      `keccak256` does not match the onchain hash.
    ///      Implementations MUST revert with `InvalidManifestHash` if
    ///      `manifestHash` is `bytes32(0)`.
    ///      Implementations MUST revert with `InvalidMetadataURI` if
    ///      `metadataURI` is the empty string or longer than 2,048 bytes
    ///      (see [Metadata URI Length Cap](#metadata-uri-length-cap)).
    ///      Implementations MUST validate `accessPredicate` per the rules in
    ///      [Predicate Validation at Registration](#predicate-validation-at-registration).
    ///      If `accessPredicate` is `address(0)`, the tool is open to all callers.
    /// @param metadataURI     URI resolving to the Tool Manifest JSON.
    /// @param manifestHash    keccak256 of the canonical manifest bytes at metadataURI.
    /// @param accessPredicate Address of the access-gating contract, or address(0) for open access.
    /// @return toolId The sequential ID assigned to the tool.
    function registerTool(string calldata metadataURI, bytes32 manifestHash, address accessPredicate)
        external
        returns (uint256 toolId);

    // ──────────────────── Deregistration ────────────────────

    /// @notice Permanently deregister a tool. Creator only.
    /// @dev Removes the tool's `ToolConfig` from storage and marks the tool ID
    ///      as deregistered. After this call, all operations on `toolId`
    ///      (`getToolConfig`, `hasAccess`, `tryHasAccess`, `updateToolMetadata`,
    ///      `setAccessPredicate`, and `deregisterTool` itself) MUST revert with
    ///      `ToolIsDeregistered`. The tool ID is never reused; `toolCount()`
    ///      continues to return the high-water mark.
    ///      MUST emit `ToolDeregistered`.
    ///      Creators who want to temporarily disable a tool SHOULD use
    ///      `setAccessPredicate` with an always-deny predicate instead;
    ///      `deregisterTool` is irreversible.
    /// @param toolId The tool to deregister.
    function deregisterTool(uint256 toolId) external;

    // ──────────────────── Metadata ────────────────────

    /// @notice Update a tool's metadata URI and manifest hash atomically. Creator only.
    /// @dev Implementations MUST revert with `InvalidManifestHash` if `newHash`
    ///      is `bytes32(0)`, and with `InvalidMetadataURI` if `newURI` is the
    ///      empty string or longer than 2,048 bytes (see
    ///      [Metadata URI Length Cap](#metadata-uri-length-cap)).
    ///      MUST revert with `ToolNotFound` if `toolId` has not been registered
    ///      and with `ToolIsDeregistered` if `toolId` was previously
    ///      deregistered.
    ///      MUST emit `ToolMetadataUpdated` when either `newURI` or `newHash`
    ///      differs from the stored values. Implementations MAY skip emission
    ///      when the call is idempotent (both values match what is already
    ///      stored), to avoid polluting event streams.
    /// @param toolId  The tool to update.
    /// @param newURI  The new metadata URI.
    /// @param newHash keccak256 of the canonical manifest bytes served at `newURI`.
    function updateToolMetadata(uint256 toolId, string calldata newURI, bytes32 newHash) external;

    // ──────────────────── Access Predicate ────────────────────

    /// @notice Update a tool's access predicate. Creator only.
    /// @dev Setting `newPredicate` to `address(0)` makes the tool open-access.
    ///      Creators who want to temporarily disable a tool SHOULD point
    ///      `newPredicate` at an always-deny predicate; this re-uses the
    ///      predicate mechanism already required for any gated tool and is
    ///      reversible (unlike `deregisterTool`).
    ///      MUST revert with `ToolNotFound` if `toolId` has not been registered
    ///      and with `ToolIsDeregistered` if `toolId` was previously
    ///      deregistered.
    ///      Implementations MUST validate `newPredicate` per the rules in
    ///      [Predicate Validation at Registration](#predicate-validation-at-registration)
    ///      whenever the call would change the stored predicate; the same
    ///      checks apply at update time as at registration time. An idempotent
    ///      call (`newPredicate` equals the currently stored predicate) is a
    ///      no-op: implementations MAY skip both validation and emission of
    ///      `AccessPredicateUpdated`, since no state transition occurs. When
    ///      the stored predicate changes, implementations MUST emit
    ///      `AccessPredicateUpdated`.
    /// @param toolId       The tool to update.
    /// @param newPredicate The new access predicate address, or address(0) for open access.
    function setAccessPredicate(uint256 toolId, address newPredicate) external;

    // ──────────────────── Views ────────────────────

    /// @notice Get the full configuration for a tool.
    /// @dev MUST revert with `ToolNotFound` if `toolId` has not been registered
    ///      and with `ToolIsDeregistered` if `toolId` was previously
    ///      deregistered. Consumers MUST be able to distinguish "never
    ///      registered" from "removed by the creator".
    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory);

    /// @notice Check whether an account has access to a tool.
    /// @dev Convenience wrapper over `tryHasAccess`: returns `true` if and
    ///      only if the predicate call succeeds AND returns a canonical
    ///      "granted" answer. Any malfunction (revert, out-of-gas,
    ///      non-canonical return word, zero-code predicate) returns `false`,
    ///      identical to a clean denial. Callers that need to distinguish
    ///      "denied" from "predicate malfunctioned" MUST use `tryHasAccess`
    ///      instead.
    ///      MUST revert with `ToolNotFound` if `toolId` has not been
    ///      registered and with `ToolIsDeregistered` if `toolId` was
    ///      previously deregistered (consistent with `getToolConfig`); a
    ///      non-existent tool, a deregistered tool, and an inaccessible tool
    ///      are three different states and consumers MUST be able to
    ///      distinguish them.
    ///      Same predicate-call contract as `tryHasAccess`: `staticcall`,
    ///      strict ABI-bool decode (any non-canonical shape is treated as
    ///      "access denied"), and `address(0)` short-circuits to `true`
    ///      without calling. Callers for open-access or data-less predicates
    ///      SHOULD pass empty bytes (`""`) for `data`.
    /// @param toolId  The tool to check.
    /// @param account The account requesting access.
    /// @param data    Opaque context bytes forwarded to the predicate
    ///                (e.g., a tokenId, a Merkle proof, a signature).
    function hasAccess(uint256 toolId, address account, bytes calldata data) external view returns (bool);

    /// @notice Check whether an account has access to a tool and report
    ///         whether the predicate call itself succeeded.
    /// @dev Returns `(ok, granted)`:
    ///      - `(true, true)`: open-access, or the predicate returned a
    ///        canonical ABI-encoded `true`.
    ///      - `(true, false)`: the predicate returned a canonical ABI-encoded
    ///        `false`; this is a clean denial.
    ///      - `(false, false)`: the predicate call failed in a way that the
    ///        registry cannot interpret. This covers revert, out-of-gas,
    ///        wrong return length, non-canonical return word (any 32-byte
    ///        value that is neither `0` nor `1`), and zero-code predicates.
    ///        Consumers SHOULD surface this case separately from a clean
    ///        denial (e.g., "predicate is misconfigured" vs "you do not
    ///        qualify"). Implementations MUST NOT return `(false, true)`.
    ///      MUST revert with `ToolNotFound` if `toolId` has not been
    ///      registered and with `ToolIsDeregistered` if `toolId` was
    ///      previously deregistered, identically to `hasAccess` and
    ///      `getToolConfig`. An unregistered or deregistered tool MUST NOT
    ///      be coerced into the `(false, false)` malfunction outcome, since
    ///      that would conflate "no such tool" or "removed by creator" with
    ///      "predicate is broken."
    ///      Same delegation contract as `hasAccess`: MUST invoke the
    ///      predicate via `staticcall`. If `accessPredicate` is `address(0)`,
    ///      MUST return `(true, true)` without calling anything, ignoring
    ///      `data`.
    /// @return ok       Whether the predicate answered canonically.
    /// @return granted  Whether access is granted. Only meaningful when `ok`.
    function tryHasAccess(uint256 toolId, address account, bytes calldata data)
        external
        view
        returns (bool ok, bool granted);

    /// @notice Total number of registered tools.
    /// @dev Tool IDs are assigned sequentially starting from 1 and are never
    ///      reused, so `toolCount()` equals the highest assigned tool ID.
    ///      Callers MAY treat `toolId == 0` as "never registered" since no
    ///      registration can produce that ID; implementations rely on this
    ///      to use `toolId == 0` as an existence sentinel in internal state.
    function toolCount() external view returns (uint256);

    /// @notice Returns a human-readable identifier for the registry implementation.
    /// @dev MUST return a non-empty string. Format is implementation-defined;
    ///      the reference implementation returns `"ToolRegistry"`. Consumers
    ///      SHOULD treat the value as opaque except for equality comparison.
    function name() external view returns (string memory);

    /// @notice Returns the implementation's version string.
    /// @dev MUST return a non-empty string. Format is implementation-defined;
    ///      the reference implementation uses `MAJOR.MINOR` (e.g. `"0.1"`,
    ///      `"1.0"`, `"1.1"`, `"2.0"`). Consumers SHOULD treat the value as
    ///      opaque except for equality comparison; ordering semantics are
    ///      implementation-defined.
    function version() external view returns (string memory);
}
