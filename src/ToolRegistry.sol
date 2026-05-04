// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IToolRegistry, ToolConfig} from "./interfaces/IToolRegistry.sol";
import {IAccessPredicate} from "./interfaces/IAccessPredicate.sol";

/// @title ToolRegistry
/// @notice Reference implementation of IToolRegistry.
/// @dev Designed for direct deployment. `_nextToolId` is initialized via a
///      state-variable initializer that runs in this contract's constructor.
///      Deploying behind a proxy without re-running that constructor against
///      the proxy's storage would leave `_nextToolId` at zero, causing the
///      first registration to receive `toolId == 0` and corrupting the
///      existence sentinel in `_requireExists`. See the ERC's "Registry
///      Deployment" security consideration for the recommended configuration.
contract ToolRegistry is IToolRegistry, ERC165 {
    /// @dev Upper bound on a `metadataURI` accepted by this reference
    ///      implementation. Caps unbounded storage / gas growth from absurdly
    ///      long URIs. The ERC does not mandate a specific cap, but consumers
    ///      and indexers SHOULD treat >2 KiB URIs as suspicious. A well-known
    ///      path (`<origin>/.well-known/ai-tool/<slug>.json`, slug length <= 64)
    ///      is comfortably under 400 bytes for any reasonable origin.
    uint256 private constant _MAX_METADATA_URI_LEN = 2048;

    /// @dev Gas forwarded to a predicate's `hasAccess` staticcall. See the
    ///      ERC's "Predicate Gas Consumption" security consideration.
    uint256 private constant _PREDICATE_GAS_LIMIT = 200_000;

    /// @dev Gas forwarded to each `supportsInterface` probe during
    ///      registration-time ERC-165 validation. Bounds the gas a
    ///      misbehaving predicate can extract from the registrant. Chosen
    ///      to match the ERC-165 ceiling: the standard requires
    ///      `supportsInterface` to use less than 30,000 gas, so a
    ///      conformant probe completes within this cap and a probe that
    ///      does not is non-conformant by construction.
    uint256 private constant _ERC165_VALIDATION_GAS_LIMIT = 30_000;

    /// @dev Starts at 1 so tool ID 0 is reserved as the "not registered" slot.
    ///      `_requireExists` uses `_tools[toolId].creator == address(0)` as the
    ///      existence sentinel, which is sound only because no registration
    ///      ever writes to `_tools[0]`.
    uint256 private _nextToolId = 1;
    mapping(uint256 => ToolConfig) private _tools;
    mapping(uint256 => bool) private _deregistered;

    function registerTool(string calldata metadataURI, bytes32 manifestHash, address accessPredicate)
        external
        returns (uint256 toolId)
    {
        uint256 uriLen = bytes(metadataURI).length;
        if (uriLen == 0 || uriLen > _MAX_METADATA_URI_LEN) revert InvalidMetadataURI();
        if (manifestHash == bytes32(0)) revert InvalidManifestHash();
        _validatePredicate(accessPredicate);

        toolId = _nextToolId++;
        _tools[toolId] = ToolConfig({
            creator: msg.sender, metadataURI: metadataURI, manifestHash: manifestHash, accessPredicate: accessPredicate
        });

        emit ToolRegistered(toolId, msg.sender, accessPredicate, metadataURI, manifestHash);
    }

    function deregisterTool(uint256 toolId) external {
        _requireExists(toolId);
        _requireCreator(toolId);

        delete _tools[toolId];
        _deregistered[toolId] = true;

        emit ToolDeregistered(toolId);
    }

    function updateToolMetadata(uint256 toolId, string calldata newURI, bytes32 newHash) external {
        _requireExists(toolId);
        _requireCreator(toolId);
        uint256 uriLen = bytes(newURI).length;
        if (uriLen == 0 || uriLen > _MAX_METADATA_URI_LEN) revert InvalidMetadataURI();
        if (newHash == bytes32(0)) revert InvalidManifestHash();

        ToolConfig storage tool = _tools[toolId];
        // The cheap length comparison short-circuits before reading and
        // hashing the stored URI. Short URIs (<=31 bytes) live in a single
        // slot, but the length cap permits strings that span many
        // keccak-derived storage slots; skipping the hash read when the
        // length already differs is the cheap path.
        bool uriChanged =
            bytes(tool.metadataURI).length != uriLen || keccak256(bytes(tool.metadataURI)) != keccak256(bytes(newURI));
        if (uriChanged || tool.manifestHash != newHash) {
            tool.metadataURI = newURI;
            tool.manifestHash = newHash;
            emit ToolMetadataUpdated(toolId, newURI, newHash);
        }
    }

    function setAccessPredicate(uint256 toolId, address newPredicate) external {
        _requireExists(toolId);
        _requireCreator(toolId);

        if (_tools[toolId].accessPredicate != newPredicate) {
            _validatePredicate(newPredicate);
            _tools[toolId].accessPredicate = newPredicate;
            emit AccessPredicateUpdated(toolId, newPredicate);
        }
    }

    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory) {
        _requireExists(toolId);
        return _tools[toolId];
    }

    function toolCount() external view returns (uint256) {
        return _nextToolId - 1;
    }

    /// @inheritdoc IToolRegistry
    function name() external pure returns (string memory) {
        return "ToolRegistry";
    }

    /// @inheritdoc IToolRegistry
    function version() external pure returns (string memory) {
        return "0.1";
    }

    function hasAccess(uint256 toolId, address account, bytes calldata data) external view returns (bool) {
        (bool ok, bool granted) = _tryHasAccess(toolId, account, data);
        return ok && granted;
    }

    function tryHasAccess(uint256 toolId, address account, bytes calldata data)
        external
        view
        returns (bool ok, bool granted)
    {
        return _tryHasAccess(toolId, account, data);
    }

    function _tryHasAccess(uint256 toolId, address account, bytes calldata data)
        internal
        view
        returns (bool ok, bool granted)
    {
        _requireExists(toolId);

        address predicate = _tools[toolId].accessPredicate;
        if (predicate == address(0)) return (true, true);

        bytes memory payload = abi.encodeCall(IAccessPredicate.hasAccess, (toolId, account, data));

        // Cap the returndata copy at 32 bytes via assembly. A hostile
        // predicate could otherwise force the caller to pay for an
        // unbounded memory expansion + returndatacopy even though only the
        // first word is inspected. The output buffer lives in scratch
        // space (0x00..0x20), which is memory-safe to write.
        uint256 gasBudget = _PREDICATE_GAS_LIMIT;
        bool callOk;
        uint256 retSize;
        bytes32 word;
        assembly ("memory-safe") {
            callOk := staticcall(gasBudget, predicate, add(payload, 0x20), mload(payload), 0x00, 0x20)
            retSize := returndatasize()
            word := mload(0x00)
        }
        // Strict ABI-bool decode: the return MUST be exactly 32 bytes and
        // the word MUST be 0 or 1. Every other shape is a malfunction and
        // fails closed.
        if (!callOk || retSize != 32) return (false, false);
        if (word == bytes32(uint256(1))) return (true, true);
        if (word == bytes32(0)) return (true, false);
        return (false, false);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IToolRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _requireExists(uint256 toolId) internal view {
        if (_deregistered[toolId]) revert ToolIsDeregistered(toolId);
        if (_tools[toolId].creator == address(0)) revert ToolNotFound(toolId);
    }

    function _requireCreator(uint256 toolId) internal view {
        if (_tools[toolId].creator != msg.sender) revert NotToolCreator(toolId, msg.sender);
    }

    /// @dev Best-effort ERC-165 check: reverts when the target contract claims
    ///      ERC-165 support but does not report IAccessPredicate, including the
    ///      case where the second supportsInterface query itself reverts (a
    ///      self-declared ERC-165 contract is required to answer without
    ///      reverting, per the standard). Each probe is gas-capped so that a
    ///      misbehaving predicate cannot drain unbounded gas from the
    ///      registrant at registration or update time.
    function _validatePredicate(address predicate) internal view {
        if (predicate == address(0)) return;
        if (predicate.code.length == 0) return;

        try IERC165(predicate).supportsInterface{gas: _ERC165_VALIDATION_GAS_LIMIT}(type(IERC165).interfaceId) returns (
            bool erc165Supported
        ) {
            if (!erc165Supported) return;
        } catch {
            return;
        }

        try IERC165(predicate).supportsInterface{gas: _ERC165_VALIDATION_GAS_LIMIT}(
            type(IAccessPredicate).interfaceId
        ) returns (
            bool supported
        ) {
            if (!supported) revert InvalidAccessPredicate(predicate);
        } catch {
            revert InvalidAccessPredicate(predicate);
        }
    }
}
