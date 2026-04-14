// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IToolPayment, PaymentConfig} from "./interfaces/IToolPayment.sol";
import {IToolRegistry, ToolConfig} from "./interfaces/IToolRegistry.sol";

/// @dev No receive() or fallback() — direct ETH sends intentionally revert.
/// ETH is only accepted via settlePayment().
contract ToolPayment is IToolPayment, ERC165 {
    using SafeERC20 for IERC20;

    IToolRegistry public immutable toolRegistry;
    address public immutable platformFeeRecipient;

    mapping(uint256 => PaymentConfig) private _configs;
    mapping(uint256 => uint256) private _balances;
    mapping(uint256 => uint256) private _platformBalances;
    mapping(uint256 => mapping(bytes32 => bool)) private _settledInvocations;

    constructor(address _toolRegistry, address _platformFeeRecipient) {
        toolRegistry = IToolRegistry(_toolRegistry);
        platformFeeRecipient = _platformFeeRecipient;
    }

    /// @notice Configure payment for a tool. The creator sets platformFeeBps
    ///         to opt into a platform fee tier at registration time.
    function setPaymentConfig(
        uint256 toolId,
        address token,
        uint256 maxPrice,
        address recipient,
        uint256 platformFeeBps
    ) external {
        _getToolConfigAndRequireCreator(toolId);
        if (recipient == address(0)) revert InvalidPaymentConfig();
        if (platformFeeBps > 10000) revert InvalidPaymentConfig();

        // Prevent token change while balances are outstanding to avoid
        // mixed-denomination accounting that permanently locks funds.
        PaymentConfig storage existing = _configs[toolId];
        if (existing.recipient != address(0) && existing.token != token) {
            if (_balances[toolId] > 0 || _platformBalances[toolId] > 0) revert OutstandingBalance(toolId);
        }

        _configs[toolId] =
            PaymentConfig({token: token, maxPrice: maxPrice, recipient: recipient, platformFeeBps: platformFeeBps});

        emit PaymentConfigSet(toolId, token, maxPrice, recipient, platformFeeBps);
    }

    /// @notice Settle payment for a tool invocation. Restricted to the tool
    ///         creator (the trusted gateway operator) to prevent griefing via
    ///         zero-charge settlements that burn invocation IDs.
    /// @dev The creator must be able to receive ETH if settling native ETH
    ///      tools with overpayment, as excess is refunded via low-level call.
    function settlePayment(uint256 toolId, bytes32 invocationId, address user, uint256 chargeAmount) external payable {
        ToolConfig memory toolConfig = _getToolConfigAndRequireCreator(toolId);
        if (!toolConfig.active) revert ToolInactive(toolId);
        if (_settledInvocations[toolId][invocationId]) revert InvocationAlreadySettled(invocationId);

        PaymentConfig storage config = _configs[toolId];
        if (config.recipient == address(0)) revert InvalidPaymentConfig();
        if (chargeAmount > config.maxPrice) revert ChargeExceedsMaxPrice(toolId, config.maxPrice, chargeAmount);
        if (config.token == address(0) && msg.value < chargeAmount) revert TransferFailed();
        if (config.token != address(0) && msg.value > 0) revert UnexpectedETH();

        // Effects
        _settledInvocations[toolId][invocationId] = true;
        uint256 platformFee;
        if (config.platformFeeBps > 0) {
            platformFee = (chargeAmount * config.platformFeeBps) / 10000;
        }
        _balances[toolId] += chargeAmount - platformFee;
        _platformBalances[toolId] += platformFee;

        emit PaymentSettled(toolId, invocationId, user, chargeAmount);

        // Interactions — ETH and ERC20 paths are mutually exclusive,
        // so each path individually follows CEI.
        if (config.token == address(0)) {
            if (msg.value > chargeAmount) {
                (bool ok,) = msg.sender.call{value: msg.value - chargeAmount}("");
                if (!ok) revert TransferFailed();
            }
        } else if (chargeAmount > 0) {
            IERC20(config.token).safeTransferFrom(msg.sender, address(this), chargeAmount);
        }
    }

    function getPaymentConfig(uint256 toolId) external view returns (PaymentConfig memory) {
        return _configs[toolId];
    }

    function getBalance(uint256 toolId) external view returns (uint256) {
        return _balances[toolId];
    }

    /// @notice Withdraw tool balance. Callable by the tool creator or the
    ///         configured recipient.
    function withdraw(uint256 toolId) external {
        uint256 balance = _balances[toolId];
        if (balance == 0) revert NoBalance(toolId);

        ToolConfig memory toolConfig = toolRegistry.getToolConfig(toolId);
        PaymentConfig storage config = _configs[toolId];
        if (msg.sender != toolConfig.creator && msg.sender != config.recipient) {
            revert NotAuthorized(toolId, msg.sender);
        }

        _balances[toolId] = 0;

        emit Withdrawal(toolId, config.recipient, balance);

        if (config.token == address(0)) {
            (bool success,) = config.recipient.call{value: balance}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(config.token).safeTransfer(config.recipient, balance);
        }
    }

    function getPlatformBalance(uint256 toolId) external view returns (uint256) {
        return _platformBalances[toolId];
    }

    function withdrawPlatformFees(uint256 toolId) external {
        if (msg.sender != platformFeeRecipient) revert NotPlatformFeeRecipient();
        toolRegistry.getToolConfig(toolId); // reverts ToolNotFound if unregistered

        uint256 balance = _platformBalances[toolId];
        if (balance == 0) revert NoPlatformBalance(toolId);

        PaymentConfig storage config = _configs[toolId];
        _platformBalances[toolId] = 0;

        emit Withdrawal(toolId, platformFeeRecipient, balance);

        if (config.token == address(0)) {
            (bool success,) = platformFeeRecipient.call{value: balance}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(config.token).safeTransfer(platformFeeRecipient, balance);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IToolPayment).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Single external call replaces the old _requireToolExists + _requireToolCreator pair.
    function _getToolConfigAndRequireCreator(uint256 toolId) internal view returns (ToolConfig memory config) {
        config = toolRegistry.getToolConfig(toolId);
        if (config.creator != msg.sender) revert NotToolCreator(toolId, msg.sender);
    }
}
