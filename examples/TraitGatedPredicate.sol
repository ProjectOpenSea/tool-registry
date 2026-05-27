// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {IERC7496Trait} from "../src/interfaces/IRequirementTypes.sol";
import {IToolRegistry} from "../src/interfaces/IToolRegistry.sol";

/// @notice Minimal interface for ERC-7496 Dynamic Traits.
interface IERC7496 {
    function getTraitValue(uint256 tokenId, bytes32 traitKey) external view returns (bytes32);
}

/// @title TraitGatedPredicate
/// @notice IAccessPredicate that gates tool access on ERC-721 ownership plus
///         an ERC-7496 dynamic trait value. The traits contract may differ
///         from the NFT contract (e.g. a separate renderer).
/// @dev The caller must pass `abi.encode(uint256 tokenId)` as the `data`
///      argument to `hasAccess`.
contract TraitGatedPredicate is IAccessPredicate, ERC165 {
    uint256 public constant MAX_ALLOWED_VALUES = 32;

    struct ToolTraitConfig {
        address collection;
        address traitsContract;
        bytes32 traitKey;
        bytes32[] allowedValues;
    }

    IToolRegistry public immutable REGISTRY;

    mapping(uint256 => ToolTraitConfig) private _configs;

    event ToolTraitConfigured(
        uint256 indexed toolId,
        address indexed collection,
        address traitsContract,
        bytes32 traitKey,
        bytes32[] allowedValues
    );

    error CallerIsNotToolCreator(uint256 toolId, address caller);
    error ZeroCollection();
    error ZeroTraitsContract();
    error CollectionNoCode(address collection);
    error TraitsContractNoCode(address traitsContract);
    error EmptyAllowedValues();
    error TooManyAllowedValues(uint256 count, uint256 max);
    error ZeroValueInAllowedValues(uint256 index);

    constructor(address _registry) {
        require(_registry != address(0), "TraitGatedPredicate: zero registry");
        REGISTRY = IToolRegistry(_registry);
    }

    /// @notice Configure which collection, traits contract, trait key, and
    ///         allowed values gate a tool. Replaces any previous configuration.
    /// @dev Only the tool's creator (as recorded in the registry) may call this.
    /// @param toolId         The tool to configure.
    /// @param collection     The ERC-721 collection (for `ownerOf` checks).
    /// @param traitsContract The contract implementing ERC-7496 `getTraitValue`.
    ///                       May be the same as `collection` or a separate renderer.
    /// @param traitKey       The trait key to query (e.g. `bytes32("tier")`).
    /// @param allowedValues  The set of trait values that grant access.
    function configureToolTrait(
        uint256 toolId,
        address collection,
        address traitsContract,
        bytes32 traitKey,
        bytes32[] calldata allowedValues
    ) external {
        if (REGISTRY.getToolConfig(toolId).creator != msg.sender) {
            revert CallerIsNotToolCreator(toolId, msg.sender);
        }

        if (collection == address(0)) revert ZeroCollection();
        if (traitsContract == address(0)) revert ZeroTraitsContract();
        if (collection.code.length == 0) revert CollectionNoCode(collection);
        if (traitsContract.code.length == 0) revert TraitsContractNoCode(traitsContract);
        if (allowedValues.length == 0) revert EmptyAllowedValues();
        if (allowedValues.length > MAX_ALLOWED_VALUES) {
            revert TooManyAllowedValues(allowedValues.length, MAX_ALLOWED_VALUES);
        }
        for (uint256 i; i < allowedValues.length; ++i) {
            if (allowedValues[i] == bytes32(0)) revert ZeroValueInAllowedValues(i);
        }

        _configs[toolId] = ToolTraitConfig({
            collection: collection,
            traitsContract: traitsContract,
            traitKey: traitKey,
            allowedValues: allowedValues
        });
        emit ToolTraitConfigured(toolId, collection, traitsContract, traitKey, allowedValues);
    }

    function getToolTraitConfig(uint256 toolId) external view returns (ToolTraitConfig memory) {
        return _configs[toolId];
    }

    /// @param data Must be `abi.encode(uint256 tokenId)`.
    function hasAccess(uint256 toolId, address account, bytes calldata data) external view override returns (bool) {
        ToolTraitConfig storage config = _configs[toolId];
        if (config.collection == address(0)) return false;
        if (config.collection.code.length == 0) return false;
        if (data.length != 32) return false;

        uint256 tokenId = abi.decode(data, (uint256));

        try IERC721(config.collection).ownerOf(tokenId) returns (address owner) {
            if (owner != account) return false;
        } catch {
            return false;
        }

        address traits = config.traitsContract;
        if (traits.code.length == 0) return false;

        try IERC7496(traits).getTraitValue(tokenId, config.traitKey) returns (bytes32 value) {
            bytes32[] storage allowed = config.allowedValues;
            uint256 len = allowed.length;
            for (uint256 i; i < len; ++i) {
                if (value == allowed[i]) return true;
            }
            return false;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IAccessPredicate
    function getRequirements(uint256 toolId)
        external
        view
        override
        returns (AccessRequirement[] memory requirements, RequirementLogic logic)
    {
        ToolTraitConfig storage config = _configs[toolId];
        if (config.collection == address(0)) {
            requirements = new AccessRequirement[](0);
        } else {
            requirements = new AccessRequirement[](1);
            requirements[0] = AccessRequirement({
                kind: type(IERC7496Trait).interfaceId,
                data: abi.encode(config.collection, config.traitsContract, config.traitKey, config.allowedValues),
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
        return "TraitGatedPredicate";
    }

    function version() external pure returns (string memory) {
        return "0.1";
    }
}
