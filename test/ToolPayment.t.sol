// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";
import {ToolAccessRegistry} from "../src/ToolAccessRegistry.sol";
import {ToolPayment} from "../src/ToolPayment.sol";
import {IToolPayment, PaymentConfig} from "../src/interfaces/IToolPayment.sol";
import {AccessMode} from "../src/interfaces/IToolRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract ToolPaymentTest is Test {
    ToolRegistry public registry;
    ToolAccessRegistry public accessRegistry;
    ToolPayment public payment;
    MockERC20 public token;

    address creator = makeAddr("creator");
    address recipient = makeAddr("recipient");
    address platformRecipient = makeAddr("platformRecipient");
    address other = makeAddr("other");
    address user = makeAddr("user");
    string constant META_URI = "https://example.com/tool.json";

    function setUp() public {
        registry = new ToolRegistry();
        accessRegistry = new ToolAccessRegistry(address(registry));
        registry.initialize(address(accessRegistry));

        payment = new ToolPayment(address(registry), platformRecipient);
        token = new MockERC20();
    }

    function _registerTool() internal returns (uint256) {
        vm.prank(creator);
        return registry.registerTool(META_URI, AccessMode.OPEN);
    }

    function test_setPaymentConfig() public {
        uint256 toolId = _registerTool();

        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit IToolPayment.PaymentConfigSet(toolId, address(token), 1000, recipient, 250);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 250);

        PaymentConfig memory config = payment.getPaymentConfig(toolId);
        assertEq(config.token, address(token));
        assertEq(config.maxPrice, 1000);
        assertEq(config.recipient, recipient);
        assertEq(config.platformFeeBps, 250);
    }

    function test_setPaymentConfig_nativeETH() public {
        uint256 toolId = _registerTool();

        vm.prank(creator);
        payment.setPaymentConfig(toolId, address(0), 0.01 ether, recipient, 100);

        PaymentConfig memory config = payment.getPaymentConfig(toolId);
        assertEq(config.token, address(0));
        assertEq(config.maxPrice, 0.01 ether);
    }

    function test_setPaymentConfig_revertsIfNotCreator() public {
        uint256 toolId = _registerTool();

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolPayment.NotToolCreator.selector, toolId, other));
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 250);
    }

    function test_setPaymentConfig_revertsOnZeroRecipient() public {
        uint256 toolId = _registerTool();

        vm.prank(creator);
        vm.expectRevert(IToolPayment.InvalidPaymentConfig.selector);
        payment.setPaymentConfig(toolId, address(token), 1000, address(0), 250);
    }

    function test_setPaymentConfig_revertsOnExcessiveBps() public {
        uint256 toolId = _registerTool();

        vm.prank(creator);
        vm.expectRevert(IToolPayment.InvalidPaymentConfig.selector);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 10001);
    }

    function test_setPaymentConfig_revertsOnTokenChangeWithBalance() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);
        token.approve(address(payment), 10000);
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 500);

        vm.expectRevert(abi.encodeWithSelector(IToolPayment.OutstandingBalance.selector, toolId));
        payment.setPaymentConfig(toolId, address(0), 0.01 ether, recipient, 0);
        vm.stopPrank();
    }

    function test_setPaymentConfig_allowsTokenChangeAfterWithdraw() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);
        token.approve(address(payment), 10000);
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 500);
        payment.withdraw(toolId);

        payment.setPaymentConfig(toolId, address(0), 0.01 ether, recipient, 0);
        vm.stopPrank();

        PaymentConfig memory config = payment.getPaymentConfig(toolId);
        assertEq(config.token, address(0));
    }

    function test_settlePayment_erc20() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 250);
        token.approve(address(payment), 10000);

        bytes32 invocationId = bytes32(uint256(1));
        vm.expectEmit(true, true, true, true);
        emit IToolPayment.PaymentSettled(toolId, invocationId, user, 1000);
        payment.settlePayment(toolId, invocationId, user, 1000);
        vm.stopPrank();

        // 250 bps = 2.5% of 1000 = 25 platform fee
        assertEq(payment.getBalance(toolId), 975);
        assertEq(token.balanceOf(address(payment)), 1000);
    }

    function test_settlePayment_nativeETH() public {
        uint256 toolId = _registerTool();

        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(0), 0.01 ether, recipient, 100);
        payment.settlePayment{value: 0.01 ether}(toolId, bytes32(uint256(1)), user, 0.01 ether);
        vm.stopPrank();

        // 100 bps = 1% of 0.01 ether = 0.0001 ether platform fee
        assertEq(payment.getBalance(toolId), 0.01 ether - 0.0001 ether);
    }

    function test_settlePayment_nativeETH_insufficientValue() public {
        uint256 toolId = _registerTool();

        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(0), 0.01 ether, recipient, 100);

        vm.expectRevert(IToolPayment.TransferFailed.selector);
        payment.settlePayment{value: 0.005 ether}(toolId, bytes32(uint256(1)), user, 0.01 ether);
        vm.stopPrank();
    }

    function test_withdraw_erc20() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 250);
        token.approve(address(payment), 10000);
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 1000);

        // 250 bps = 2.5% of 1000 = 25 platform fee, 975 to creator
        assertEq(payment.getBalance(toolId), 975);

        vm.expectEmit(true, true, false, true);
        emit IToolPayment.Withdrawal(toolId, recipient, 975);
        payment.withdraw(toolId);
        vm.stopPrank();

        assertEq(payment.getBalance(toolId), 0);
        assertEq(token.balanceOf(recipient), 975);
    }

    function test_withdraw_nativeETH() public {
        uint256 toolId = _registerTool();

        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(0), 0.01 ether, recipient, 100);
        payment.settlePayment{value: 0.01 ether}(toolId, bytes32(uint256(1)), user, 0.01 ether);

        uint256 expectedCreatorAmount = 0.01 ether - 0.0001 ether;
        uint256 recipientBalBefore = recipient.balance;

        payment.withdraw(toolId);
        vm.stopPrank();

        assertEq(payment.getBalance(toolId), 0);
        assertEq(recipient.balance, recipientBalBefore + expectedCreatorAmount);
    }

    function test_withdraw_revertsIfNoBalance() public {
        uint256 toolId = _registerTool();
        vm.prank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolPayment.NoBalance.selector, toolId));
        payment.withdraw(toolId);
    }

    function test_withdraw_revertsIfNotAuthorized() public {
        uint256 toolId = _registerTool();

        // Fund the tool so the balance check passes and auth check is reached
        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);
        token.approve(address(payment), 10000);
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 1000);
        vm.stopPrank();

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolPayment.NotAuthorized.selector, toolId, other));
        payment.withdraw(toolId);
    }

    function test_getBalance_initiallyZero() public {
        uint256 toolId = _registerTool();
        assertEq(payment.getBalance(toolId), 0);
    }

    function test_settlePayment_nativeETH_excessRefunded() public {
        uint256 toolId = _registerTool();

        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(0), 0.01 ether, recipient, 0);
        uint256 creatorBalBefore = creator.balance;
        payment.settlePayment{value: 0.02 ether}(toolId, bytes32(uint256(1)), user, 0.01 ether);
        vm.stopPrank();

        assertEq(payment.getBalance(toolId), 0.01 ether);
        assertEq(creator.balance, creatorBalBefore - 0.01 ether);
    }

    function test_platformFee_erc20() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 500);
        token.approve(address(payment), 10000);
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 1000);
        vm.stopPrank();

        assertEq(payment.getBalance(toolId), 950);
        assertEq(payment.getPlatformBalance(toolId), 50);

        vm.prank(platformRecipient);
        payment.withdrawPlatformFees(toolId);
        assertEq(token.balanceOf(platformRecipient), 50);
        assertEq(payment.getPlatformBalance(toolId), 0);
    }

    function test_withdrawPlatformFees_revertsIfNotRecipient() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 500);
        token.approve(address(payment), 10000);
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 1000);
        vm.stopPrank();

        vm.prank(other);
        vm.expectRevert(IToolPayment.NotPlatformFeeRecipient.selector);
        payment.withdrawPlatformFees(toolId);
    }

    function test_settlePayment_revertsIfChargeExceedsMaxPrice() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);
        token.approve(address(payment), 10000);

        vm.expectRevert(abi.encodeWithSelector(IToolPayment.ChargeExceedsMaxPrice.selector, toolId, 1000, 1500));
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 1500);
        vm.stopPrank();
    }

    function test_settlePayment_allowsChargeBelowMaxPrice() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);
        token.approve(address(payment), 10000);

        payment.settlePayment(toolId, bytes32(uint256(1)), user, 500);
        vm.stopPrank();

        assertEq(payment.getBalance(toolId), 500);
    }

    function test_settlePayment_allowsZeroCharge() public {
        uint256 toolId = _registerTool();
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);

        payment.settlePayment(toolId, bytes32(uint256(1)), user, 0);
        vm.stopPrank();

        assertEq(payment.getBalance(toolId), 0);
    }

    function test_settlePayment_revertsOnDuplicateInvocation() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);
        token.approve(address(payment), 10000);

        bytes32 invocationId = bytes32(uint256(42));
        payment.settlePayment(toolId, invocationId, user, 1000);

        vm.expectRevert(abi.encodeWithSelector(IToolPayment.InvocationAlreadySettled.selector, invocationId));
        payment.settlePayment(toolId, invocationId, user, 1000);
        vm.stopPrank();
    }

    // --- settlePayment access control (S1+S2) ---

    function test_settlePayment_revertsIfNotCreator() public {
        uint256 toolId = _registerTool();
        vm.prank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolPayment.NotToolCreator.selector, toolId, other));
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 0);
    }

    // --- UnexpectedETH on ERC20 path (S3) ---

    function test_settlePayment_revertsOnETHWithERC20Config() public {
        uint256 toolId = _registerTool();
        vm.prank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);

        vm.deal(creator, 1 ether);
        vm.prank(creator);
        vm.expectRevert(IToolPayment.UnexpectedETH.selector);
        payment.settlePayment{value: 0.1 ether}(toolId, bytes32(uint256(1)), user, 500);
    }

    // --- platform fees native ETH ---

    function test_platformFee_nativeETH() public {
        uint256 toolId = _registerTool();

        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(0), 0.01 ether, recipient, 500);
        payment.settlePayment{value: 0.01 ether}(toolId, bytes32(uint256(1)), user, 0.01 ether);
        vm.stopPrank();

        uint256 expectedPlatformFee = 0.0005 ether;
        assertEq(payment.getPlatformBalance(toolId), expectedPlatformFee);

        uint256 recipientBalBefore = platformRecipient.balance;
        vm.prank(platformRecipient);
        payment.withdrawPlatformFees(toolId);
        assertEq(platformRecipient.balance, recipientBalBefore + expectedPlatformFee);
        assertEq(payment.getPlatformBalance(toolId), 0);
    }

    function test_withdrawPlatformFees_revertsIfZeroBalance() public {
        uint256 toolId = _registerTool();
        vm.prank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);

        vm.prank(platformRecipient);
        vm.expectRevert(abi.encodeWithSelector(IToolPayment.NoPlatformBalance.selector, toolId));
        payment.withdrawPlatformFees(toolId);
    }

    // --- fuzz ---

    function testFuzz_settlePayment(uint256 chargeAmount, uint256 maxPrice) public {
        vm.assume(maxPrice > 0 && maxPrice < type(uint128).max);
        vm.assume(chargeAmount <= maxPrice);

        uint256 toolId = _registerTool();

        token.mint(creator, chargeAmount);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), maxPrice, recipient, 250);
        token.approve(address(payment), chargeAmount);
        payment.settlePayment(toolId, bytes32(uint256(1)), user, chargeAmount);
        vm.stopPrank();

        uint256 expectedPlatformFee = (chargeAmount * 250) / 10000;
        assertEq(payment.getBalance(toolId), chargeAmount - expectedPlatformFee);
        assertEq(payment.getPlatformBalance(toolId), expectedPlatformFee);
    }

    // --- H2: cross-tool invocationId reuse ---

    function test_settlePayment_allowsCrossToolInvocationIdReuse() public {
        uint256 toolId1 = _registerTool();
        uint256 toolId2 = _registerTool();

        token.mint(creator, 20000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId1, address(token), 1000, recipient, 0);
        payment.setPaymentConfig(toolId2, address(token), 1000, recipient, 0);
        token.approve(address(payment), 20000);

        bytes32 invocationId = bytes32(uint256(99));
        payment.settlePayment(toolId1, invocationId, user, 500);
        // Same invocationId on different tool should succeed
        payment.settlePayment(toolId2, invocationId, user, 500);
        vm.stopPrank();

        assertEq(payment.getBalance(toolId1), 500);
        assertEq(payment.getBalance(toolId2), 500);
    }

    // --- M3: recipient can withdraw ---

    function test_withdraw_recipientCanCall() public {
        uint256 toolId = _registerTool();

        token.mint(creator, 10000);
        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);
        token.approve(address(payment), 10000);
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 1000);
        vm.stopPrank();

        vm.prank(recipient);
        payment.withdraw(toolId);

        assertEq(payment.getBalance(toolId), 0);
        assertEq(token.balanceOf(recipient), 1000);
    }

    // --- M4: deactivated tool settlement ---

    function test_settlePayment_revertsIfToolDeactivated() public {
        uint256 toolId = _registerTool();

        vm.startPrank(creator);
        payment.setPaymentConfig(toolId, address(token), 1000, recipient, 0);
        registry.deactivateTool(toolId);

        vm.expectRevert(abi.encodeWithSelector(IToolPayment.ToolInactive.selector, toolId));
        payment.settlePayment(toolId, bytes32(uint256(1)), user, 0);
        vm.stopPrank();
    }

    // --- supportsInterface ---

    function test_supportsInterface_IToolPayment() public view {
        assertTrue(payment.supportsInterface(type(IToolPayment).interfaceId));
    }

    /// @dev Locks the hardcoded interface ID declared in the ERC spec.
    function test_interfaceId_IToolPayment_matchesSpec() public pure {
        assertEq(type(IToolPayment).interfaceId, bytes4(0xe1fc6949));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(payment.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_invalid() public view {
        assertFalse(payment.supportsInterface(0xdeadbeef));
    }
}
