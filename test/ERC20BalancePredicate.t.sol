// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC20BalancePredicate} from "../examples/ERC20BalancePredicate.sol";
import {AccessRequirement, IAccessPredicate, RequirementLogic} from "../src/interfaces/IAccessPredicate.sol";
import {IERC20Balance} from "../src/interfaces/IRequirementTypes.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";

/// @dev Minimal mock ERC-20 with configurable balances.
contract MockERC20 {
    mapping(address => uint256) private _balances;
    uint8 private _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function setBalance(address account, uint256 amount) external {
        _balances[account] = amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

/// @dev Contract that does not implement balanceOf.
contract NotAnERC20 {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract ERC20BalancePredicateTest is Test {
    ToolRegistry public registry;
    ERC20BalancePredicate public predicate;
    MockERC20 public token;

    address creator = makeAddr("creator");
    address holder = makeAddr("holder");
    address poorHolder = makeAddr("poorHolder");
    address nonHolder = makeAddr("nonHolder");
    address stranger = makeAddr("stranger");

    string constant META_URI = "https://api.opensea.io/.well-known/ai-tool/erc20-tool.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    uint256 constant MIN_BALANCE = 1000e18;
    uint256 toolId;

    function setUp() public {
        registry = new ToolRegistry();
        predicate = new ERC20BalancePredicate(address(registry));
        token = new MockERC20(18);

        token.setBalance(holder, 5000e18);
        token.setBalance(poorHolder, 500e18);

        vm.prank(creator);
        toolId = registry.registerTool(META_URI, MANIFEST_HASH, address(predicate));
    }

    // ── constructor ─────────────────────────────────────────────────────

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert("ERC20BalancePredicate: zero registry");
        new ERC20BalancePredicate(address(0));
    }

    function test_constructor_setsRegistry() public view {
        assertEq(address(predicate.REGISTRY()), address(registry));
    }

    // ── configureToolERC20 ──────────────────────────────────────────────

    function test_configureToolERC20_success() public {
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);

        ERC20BalancePredicate.ToolERC20Config memory config = predicate.getToolERC20Config(toolId);
        assertEq(config.token, address(token));
        assertEq(config.minBalance, MIN_BALANCE);
    }

    function test_configureToolERC20_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit ERC20BalancePredicate.ToolERC20Configured(toolId, address(token), MIN_BALANCE);

        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);
    }

    function test_configureToolERC20_replacesExisting() public {
        MockERC20 token2 = new MockERC20(6);
        uint256 newMin = 500e6;

        vm.startPrank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);
        predicate.configureToolERC20(toolId, address(token2), newMin);
        vm.stopPrank();

        ERC20BalancePredicate.ToolERC20Config memory config = predicate.getToolERC20Config(toolId);
        assertEq(config.token, address(token2));
        assertEq(config.minBalance, newMin);
    }

    function test_configureToolERC20_revertsIfNotCreator() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20BalancePredicate.CallerIsNotToolCreator.selector, toolId, stranger));
        vm.prank(stranger);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);
    }

    function test_configureToolERC20_revertsOnZeroToken() public {
        vm.expectRevert(ERC20BalancePredicate.ZeroToken.selector);
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(0), MIN_BALANCE);
    }

    function test_configureToolERC20_revertsOnEOAToken() public {
        address eoa = makeAddr("eoa");
        vm.expectRevert(abi.encodeWithSelector(ERC20BalancePredicate.TokenNoCode.selector, eoa));
        vm.prank(creator);
        predicate.configureToolERC20(toolId, eoa, MIN_BALANCE);
    }

    function test_configureToolERC20_revertsOnZeroMinBalance() public {
        vm.expectRevert(ERC20BalancePredicate.ZeroMinBalance.selector);
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), 0);
    }

    // ── hasAccess ────────────────────────────────────────────────────────

    function test_hasAccess_grantsWhenBalanceSufficient() public {
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_grantsWhenBalanceExact() public {
        token.setBalance(holder, MIN_BALANCE);

        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_deniesWhenBalanceInsufficient() public {
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);

        assertFalse(predicate.hasAccess(toolId, poorHolder, ""));
    }

    function test_hasAccess_deniesWhenBalanceZero() public {
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);

        assertFalse(predicate.hasAccess(toolId, nonHolder, ""));
    }

    function test_hasAccess_deniesWhenNotConfigured() public view {
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_deniesWhenTokenSelfDestructed() public {
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);

        vm.etch(address(token), "");
        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_deniesWhenTokenDoesNotImplementBalanceOf() public {
        NotAnERC20 notToken = new NotAnERC20();

        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(notToken), MIN_BALANCE);

        assertFalse(predicate.hasAccess(toolId, holder, ""));
    }

    function test_hasAccess_worksWithDifferentDecimals() public {
        MockERC20 usdc = new MockERC20(6);
        uint256 usdcMin = 100e6; // 100 USDC
        usdc.setBalance(holder, 200e6);
        usdc.setBalance(poorHolder, 50e6);

        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(usdc), usdcMin);

        assertTrue(predicate.hasAccess(toolId, holder, ""));
        assertFalse(predicate.hasAccess(toolId, poorHolder, ""));
    }

    function test_hasAccess_dataArgumentIsIgnored() public {
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);

        assertTrue(predicate.hasAccess(toolId, holder, hex"deadbeef"));
        assertTrue(predicate.hasAccess(toolId, holder, abi.encode(uint256(42))));
    }

    // ── getRequirements ─────────────────────────────────────────────────

    function test_getRequirements_returnsEmptyWhenNotConfigured() public view {
        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 0);
        assertEq(uint8(logic), uint8(RequirementLogic.AND));
    }

    function test_getRequirements_returnsConfigured() public {
        vm.prank(creator);
        predicate.configureToolERC20(toolId, address(token), MIN_BALANCE);

        (AccessRequirement[] memory reqs, RequirementLogic logic) = predicate.getRequirements(toolId);
        assertEq(reqs.length, 1);
        assertEq(reqs[0].kind, type(IERC20Balance).interfaceId);
        (address decodedToken, uint256 decodedMinBalance) = abi.decode(reqs[0].data, (address, uint256));
        assertEq(decodedToken, address(token));
        assertEq(decodedMinBalance, MIN_BALANCE);
        assertEq(uint8(logic), uint8(RequirementLogic.AND));
    }

    // ── ERC-165 ─────────────────────────────────────────────────────────

    function test_supportsInterface_IAccessPredicate() public view {
        assertTrue(predicate.supportsInterface(type(IAccessPredicate).interfaceId));
    }

    function test_supportsInterface_ERC165() public view {
        assertTrue(predicate.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_random_returnsFalse() public view {
        assertFalse(predicate.supportsInterface(0xdeadbeef));
    }

    // ── name / version ──────────────────────────────────────────────────

    function test_name() public view {
        assertEq(predicate.name(), "ERC20BalancePredicate");
    }

    function test_version() public view {
        assertEq(predicate.version(), "0.1");
    }

    // ── IERC20Balance interface ID pin ───────────────────────────────────

    function test_interfaceId_IERC20Balance_pinned() public pure {
        assertEq(type(IERC20Balance).interfaceId, bytes4(keccak256("erc20Balance()")));
    }
}
