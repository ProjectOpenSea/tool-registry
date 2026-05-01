// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {ISubscription} from "../src/interfaces/IRequirementTypes.sol";
import {IToolRegistry, ToolConfig} from "../src/interfaces/IToolRegistry.sol";

/// @notice Minimal interface for ERC-5643 subscription queries.
interface IERC5643 {
    /// @notice Returns the expiration timestamp of a subscription token.
    function expiresAt(uint256 tokenId) external view returns (uint64);
}

/// @notice Minimal interface for subscription NFTs that support per-owner
///         lookups and optional tier levels.
interface ISubscriptionNFT is IERC5643 {
    /// @notice Returns the token ID owned by `owner`, or 0 if none exists.
    /// @dev Collections MUST enforce one token per owner (soulbound / account-bound),
    ///      return 0 for non-holders, and MUST NOT mint token ID 0 (reserved sentinel).
    function tokenOfOwner(address owner) external view returns (uint256);

    /// @notice Returns the tier level of a subscription token (1-based).
    ///         Tokens without tier support SHOULD return 1 for any minted token.
    function tierOf(uint256 tokenId) external view returns (uint8);
}

/// @title SubscriptionPredicate
/// @notice Shared IAccessPredicate that gates tool access via ERC-5643
///         subscription NFTs. A single deployment serves many tools: each
///         tool creator configures which subscription NFT collection (and
///         minimum tier) gates their tool.
/// @dev The predicate verifies caller identity against the ToolRegistry so
///      that only a tool's creator can configure its gating. Multiple tools
///      MAY share the same subscription NFT collection with different minimum
///      tier requirements, enabling tiered access (Basic / Pro / Enterprise)
///      from a single token.
contract SubscriptionPredicate is IAccessPredicate, ERC165 {
    /// @notice Per-tool gating configuration.
    struct ToolGatingConfig {
        address collection;
        uint8 minTier;
    }

    /// @notice The ToolRegistry used to verify tool creator identity.
    IToolRegistry public immutable registry;

    /// @notice Gating configuration for each tool.
    mapping(uint256 => ToolGatingConfig) private _toolConfigs;

    event ToolGatingConfigured(uint256 indexed toolId, address indexed collection, uint8 minTier);

    error NotToolCreator(uint256 toolId, address caller);
    error ToolDoesNotUseThisPredicate(uint256 toolId);
    error ZeroCollection();
    error CollectionNotAContract(address collection);
    error CollectionNotSubscriptionNFT(address collection);

    constructor(address _registry) {
        require(_registry != address(0), "SubscriptionPredicate: zero registry");
        registry = IToolRegistry(_registry);
    }

    /// @notice Configure which subscription NFT collection gates a tool.
    /// @dev Only callable by the tool's creator (verified via ToolRegistry).
    ///      The tool MUST already have its accessPredicate set to this
    ///      contract's address before calling.
    /// @param toolId     The tool to configure.
    /// @param collection The subscription NFT collection address.
    /// @param minTier    Minimum tier required. 0 means any active (non-expired)
    ///                   subscription grants access.
    function configureToolGating(uint256 toolId, address collection, uint8 minTier) external {
        if (collection == address(0)) revert ZeroCollection();
        if (collection.code.length == 0) revert CollectionNotAContract(collection);

        // Probe with address(1) to avoid false-rejecting collections that guard against address(0)
        try ISubscriptionNFT(collection).tokenOfOwner(address(1)) {} catch {
            revert CollectionNotSubscriptionNFT(collection);
        }

        ToolConfig memory tool = registry.getToolConfig(toolId);
        if (tool.creator != msg.sender) revert NotToolCreator(toolId, msg.sender);
        if (tool.accessPredicate != address(this)) revert ToolDoesNotUseThisPredicate(toolId);

        _toolConfigs[toolId] = ToolGatingConfig({collection: collection, minTier: minTier});
        emit ToolGatingConfigured(toolId, collection, minTier);
    }

    /// @inheritdoc IAccessPredicate
    function hasAccess(uint256 toolId, address account, bytes calldata) external view override returns (bool) {
        ToolGatingConfig memory config = _toolConfigs[toolId];
        if (config.collection == address(0)) return false;

        ISubscriptionNFT nft = ISubscriptionNFT(config.collection);

        uint256 tokenId = nft.tokenOfOwner(account);
        if (tokenId == 0) return false;

        if (nft.expiresAt(tokenId) <= block.timestamp) return false;

        if (config.minTier > 0 && nft.tierOf(tokenId) < config.minTier) return false;

        return true;
    }

    /// @notice Read the gating configuration for a tool.
    function getToolGatingConfig(uint256 toolId) external view returns (ToolGatingConfig memory) {
        return _toolConfigs[toolId];
    }

    /// @notice Rich status view for UIs and agent frameworks.
    /// @return hasNft       Whether the account owns a subscription NFT.
    /// @return tier         The account's current tier (0 if no NFT).
    /// @return requiredTier The minimum tier required by this tool.
    /// @return expiration   The subscription expiration timestamp (0 if no NFT).
    /// @return active       Whether the account currently has access.
    function getSubscriptionStatus(uint256 toolId, address account)
        external
        view
        returns (bool hasNft, uint8 tier, uint8 requiredTier, uint64 expiration, bool active)
    {
        ToolGatingConfig memory config = _toolConfigs[toolId];
        requiredTier = config.minTier;

        if (config.collection == address(0)) return (false, 0, requiredTier, 0, false);

        ISubscriptionNFT nft = ISubscriptionNFT(config.collection);
        uint256 tokenId = nft.tokenOfOwner(account);

        if (tokenId == 0) return (false, 0, requiredTier, 0, false);

        hasNft = true;
        tier = nft.tierOf(tokenId);
        expiration = nft.expiresAt(tokenId);
        active = expiration > block.timestamp && (config.minTier == 0 || tier >= config.minTier);
    }

    /// @inheritdoc IAccessPredicate
    function getRequirements(uint256 toolId)
        external
        view
        override
        returns (AccessRequirement[] memory requirements, RequirementLogic logic)
    {
        ToolGatingConfig memory config = _toolConfigs[toolId];
        if (config.collection == address(0)) {
            requirements = new AccessRequirement[](0);
        } else {
            requirements = new AccessRequirement[](1);
            requirements[0] = AccessRequirement({
                kind: type(ISubscription).interfaceId,
                data: abi.encode(config.collection, config.minTier),
                label: ""
            });
        }
        logic = RequirementLogic.AND;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAccessPredicate).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IAccessPredicate
    function name() external pure returns (string memory) {
        return "SubscriptionPredicate";
    }

    /// @notice Implementation version; same `MAJOR.MINOR` scheme as `ToolRegistry`.
    function version() external pure returns (string memory) {
        return "0.1";
    }
}
