// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {IERC20Balance} from "../src/interfaces/IRequirementTypes.sol";
import {IToolRegistry} from "../src/interfaces/IToolRegistry.sol";

/// @title ERC20BalancePredicate
/// @notice IAccessPredicate that gates tool access on holding a configurable
///         minimum balance of an ERC-20 token. The tool creator specifies:
///         - `token` — the ERC-20 contract address
///         - `minBalance` — the minimum `balanceOf` required for access
/// @dev Multi-tenant: one deployment per chain, configured per `toolId`.
///      The `data` argument to `hasAccess` is unused.
contract ERC20BalancePredicate is IAccessPredicate, ERC165 {
    struct ToolERC20Config {
        address token;
        uint256 minBalance;
    }

    IToolRegistry public immutable REGISTRY;

    mapping(uint256 => ToolERC20Config) private _configs;

    event ToolERC20Configured(uint256 indexed toolId, address indexed token, uint256 minBalance);

    error CallerIsNotToolCreator(uint256 toolId, address caller);
    error ZeroToken();
    error TokenNoCode(address token);
    error ZeroMinBalance();

    constructor(address _registry) {
        require(_registry != address(0), "ERC20BalancePredicate: zero registry");
        REGISTRY = IToolRegistry(_registry);
    }

    /// @notice Configure which ERC-20 token and minimum balance gate a tool.
    ///         Replaces any previous configuration.
    /// @dev Only the tool's creator (as recorded in the registry) may call this.
    /// @param toolId     The tool to configure.
    /// @param token      The ERC-20 token contract address.
    /// @param minBalance The minimum `balanceOf` required for access. Must be > 0.
    function configureToolERC20(uint256 toolId, address token, uint256 minBalance) external {
        if (REGISTRY.getToolConfig(toolId).creator != msg.sender) {
            revert CallerIsNotToolCreator(toolId, msg.sender);
        }

        if (token == address(0)) revert ZeroToken();
        if (token.code.length == 0) revert TokenNoCode(token);
        if (minBalance == 0) revert ZeroMinBalance();

        _configs[toolId] = ToolERC20Config({token: token, minBalance: minBalance});
        emit ToolERC20Configured(toolId, token, minBalance);
    }

    function getToolERC20Config(uint256 toolId) external view returns (ToolERC20Config memory) {
        return _configs[toolId];
    }

    /// @notice Returns true if `account` holds >= `minBalance` of the configured token.
    function hasAccess(uint256 toolId, address account, bytes calldata) external view override returns (bool) {
        ToolERC20Config storage config = _configs[toolId];
        if (config.token == address(0)) return false;
        // Needed: staticcall to no-code address reverts before try/catch can catch it.
        if (config.token.code.length == 0) return false;

        try IERC20(config.token).balanceOf(account) returns (uint256 balance) {
            return balance >= config.minBalance;
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
        ToolERC20Config storage config = _configs[toolId];
        if (config.token == address(0)) {
            requirements = new AccessRequirement[](0);
        } else {
            requirements = new AccessRequirement[](1);
            requirements[0] = AccessRequirement({
                kind: type(IERC20Balance).interfaceId, data: abi.encode(config.token, config.minBalance), label: ""
            });
        }
        logic = RequirementLogic.AND;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAccessPredicate).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IAccessPredicate
    function name() external pure returns (string memory) {
        return "ERC20BalancePredicate";
    }

    function version() external pure returns (string memory) {
        return "0.1";
    }
}
