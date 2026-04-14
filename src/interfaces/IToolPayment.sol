// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Payment configuration for a tool.
struct PaymentConfig {
    address token;
    uint256 maxPrice;
    address recipient;
    uint256 platformFeeBps;
}

/// @title IToolPayment
/// @notice Per-invocation payment interface.
/// @dev ERC-165 interface ID computed from type(IToolPayment).interfaceId
interface IToolPayment {
    event PaymentConfigSet(
        uint256 indexed toolId, address token, uint256 maxPrice, address recipient, uint256 platformFeeBps
    );
    event Withdrawal(uint256 indexed toolId, address indexed recipient, uint256 amount);
    event PaymentSettled(uint256 indexed toolId, bytes32 indexed invocationId, address indexed user, uint256 amount);

    error NoBalance(uint256 toolId);
    error NoPlatformBalance(uint256 toolId);
    error InvalidPaymentConfig();
    error TransferFailed();
    error NotToolCreator(uint256 toolId, address caller);
    error ToolNotFound(uint256 toolId);
    error ChargeExceedsMaxPrice(uint256 toolId, uint256 maxPrice, uint256 chargeAmount);
    error InvocationAlreadySettled(bytes32 invocationId);
    error NotPlatformFeeRecipient();
    error UnexpectedETH();
    error OutstandingBalance(uint256 toolId);
    error ToolInactive(uint256 toolId);
    error NotAuthorized(uint256 toolId, address caller);

    function setPaymentConfig(
        uint256 toolId,
        address token,
        uint256 maxPrice,
        address recipient,
        uint256 platformFeeBps
    ) external;
    function settlePayment(uint256 toolId, bytes32 invocationId, address user, uint256 chargeAmount) external payable;
    function getPaymentConfig(uint256 toolId) external view returns (PaymentConfig memory);
    function getBalance(uint256 toolId) external view returns (uint256);
    function withdraw(uint256 toolId) external;
    function getPlatformBalance(uint256 toolId) external view returns (uint256);
    function withdrawPlatformFees(uint256 toolId) external;
}
