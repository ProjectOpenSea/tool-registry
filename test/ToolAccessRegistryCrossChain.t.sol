// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ToolRegistry} from "../src/ToolRegistry.sol";
import {ToolAccessRegistry} from "../src/ToolAccessRegistry.sol";
import {GatewayKeyRegistry} from "../src/GatewayKeyRegistry.sol";
import {TokenStandard} from "../src/interfaces/IToolAccessRegistry.sol";
import {AccessMode, IToolRegistry} from "../src/interfaces/IToolRegistry.sol";
import {
    IToolAccessRegistryCrossChain,
    CrossChainBinding,
    CrossChainProof
} from "../src/interfaces/IToolAccessRegistryCrossChain.sol";
import {IToolAccessRegistry} from "../src/interfaces/IToolAccessRegistry.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ToolAccessRegistryCrossChainTest is Test {
    ToolRegistry public registry;
    ToolAccessRegistry public accessRegistry;
    GatewayKeyRegistry public keyRegistry;

    address creator = makeAddr("creator");
    address user = makeAddr("user");
    address other = makeAddr("other");

    uint256 gatewayPrivateKey = 0xA11CE;
    address gatewayAddress;

    uint256 REMOTE_CHAIN_ID = 1;
    address REMOTE_COLLECTION = address(0xBEEF);
    uint256 REMOTE_TOKEN_ID = 42;

    string constant META_URI = "https://example.com/tool.json";
    bytes32 constant MANIFEST_HASH = keccak256("manifest-v1");

    bytes32 constant CROSS_CHAIN_PROOF_TYPEHASH = keccak256(
        "CrossChainProof(uint256 toolId,address account,uint256 chainId,address collection,uint256 tokenId,uint256 checkedAt)"
    );

    function setUp() public {
        registry = new ToolRegistry();
        keyRegistry = new GatewayKeyRegistry(address(this));
        accessRegistry = new ToolAccessRegistry(address(registry), address(keyRegistry));
        registry.initialize(address(accessRegistry));

        gatewayAddress = vm.addr(gatewayPrivateKey);
        keyRegistry.addGatewayKey(gatewayAddress);
    }

    function _registerTool(AccessMode mode) internal returns (uint256) {
        vm.prank(creator);
        return registry.registerTool(META_URI, MANIFEST_HASH, mode);
    }

    function _bindCrossChain(uint256 toolId) internal {
        vm.prank(creator);
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ToolRegistryCrossChain")),
                keccak256(bytes("1")),
                block.chainid,
                address(accessRegistry)
            )
        );
    }

    function _signProof(uint256 privateKey, CrossChainProof memory proof) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                CROSS_CHAIN_PROOF_TYPEHASH,
                proof.toolId,
                proof.account,
                proof.chainId,
                proof.collection,
                proof.tokenId,
                proof.checkedAt
            )
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(_domainSeparator(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _makeProof(uint256 toolId, address account) internal view returns (CrossChainProof memory) {
        CrossChainProof memory proof = CrossChainProof({
            toolId: toolId,
            account: account,
            chainId: REMOTE_CHAIN_ID,
            collection: REMOTE_COLLECTION,
            tokenId: REMOTE_TOKEN_ID,
            checkedAt: block.timestamp,
            gatewaySignature: ""
        });
        proof.gatewaySignature = _signProof(gatewayPrivateKey, proof);
        return proof;
    }

    // --- Happy path ---

    function test_hasAccessWithRemoteProof_nftGated_valid() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = _makeProof(toolId, user);
        assertTrue(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_open_returnsTrueWithoutBindingOrProof() public {
        uint256 toolId = _registerTool(AccessMode.OPEN);

        CrossChainProof memory proof; // all zero
        assertTrue(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    // --- Signature failures ---

    function test_hasAccessWithRemoteProof_unregisteredSigner_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        uint256 intruderKey = 0xB0B;
        CrossChainProof memory proof = _makeProof(toolId, user);
        // Re-sign with an unregistered key
        proof.gatewaySignature = _signProof(intruderKey, proof);

        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_revokedSigner_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = _makeProof(toolId, user);
        assertTrue(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));

        keyRegistry.removeGatewayKey(gatewayAddress);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_malformedSignature_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = _makeProof(toolId, user);
        proof.gatewaySignature = hex"dead";

        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    // --- Binding failures ---

    function test_hasAccessWithRemoteProof_noBinding_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        // no _bindCrossChain

        CrossChainProof memory proof = _makeProof(toolId, user);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_wrongChainId_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = CrossChainProof({
            toolId: toolId,
            account: user,
            chainId: 137, // different chain
            collection: REMOTE_COLLECTION,
            tokenId: REMOTE_TOKEN_ID,
            checkedAt: block.timestamp,
            gatewaySignature: ""
        });
        proof.gatewaySignature = _signProof(gatewayPrivateKey, proof);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_wrongCollection_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = CrossChainProof({
            toolId: toolId,
            account: user,
            chainId: REMOTE_CHAIN_ID,
            collection: address(0xDEAD),
            tokenId: REMOTE_TOKEN_ID,
            checkedAt: block.timestamp,
            gatewaySignature: ""
        });
        proof.gatewaySignature = _signProof(gatewayPrivateKey, proof);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_removedBinding_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = _makeProof(toolId, user);
        assertTrue(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));

        vm.prank(creator);
        accessRegistry.removeCrossChainCollection(toolId, 0, REMOTE_CHAIN_ID, REMOTE_COLLECTION);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    // --- ERC-1155 binding requires matching tokenId ---

    function test_hasAccessWithRemoteProof_erc1155_matchingTokenId() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCrossChainCollection(
            toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC1155, REMOTE_TOKEN_ID
        );

        CrossChainProof memory proof = _makeProof(toolId, user);
        assertTrue(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_erc1155_wrongTokenId_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        vm.prank(creator);
        accessRegistry.addCrossChainCollection(
            toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC1155, REMOTE_TOKEN_ID
        );

        CrossChainProof memory proof = CrossChainProof({
            toolId: toolId,
            account: user,
            chainId: REMOTE_CHAIN_ID,
            collection: REMOTE_COLLECTION,
            tokenId: 999, // different from bound tokenId
            checkedAt: block.timestamp,
            gatewaySignature: ""
        });
        proof.gatewaySignature = _signProof(gatewayPrivateKey, proof);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    // --- Account / tool mismatches ---

    function test_hasAccessWithRemoteProof_accountMismatch_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = _makeProof(toolId, user);
        // Caller claims different account than the proof names
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, other, proof));
    }

    function test_hasAccessWithRemoteProof_toolIdMismatch_returnsFalse() public {
        uint256 toolIdA = _registerTool(AccessMode.NFT_GATED);
        uint256 toolIdB = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolIdA);
        _bindCrossChain(toolIdB);

        CrossChainProof memory proofForA = _makeProof(toolIdA, user);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolIdB, user, proofForA));
    }

    // --- Staleness ---

    function test_hasAccessWithRemoteProof_staleProof_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = _makeProof(toolId, user);
        vm.warp(block.timestamp + 301); // outside 300s window
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_exactlyAtWindowEdge_returnsTrue() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = _makeProof(toolId, user);
        vm.warp(block.timestamp + 300);
        assertTrue(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    function test_hasAccessWithRemoteProof_futureCheckedAt_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = CrossChainProof({
            toolId: toolId,
            account: user,
            chainId: REMOTE_CHAIN_ID,
            collection: REMOTE_COLLECTION,
            tokenId: REMOTE_TOKEN_ID,
            checkedAt: block.timestamp + 1, // future
            gatewaySignature: ""
        });
        proof.gatewaySignature = _signProof(gatewayPrivateKey, proof);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    // --- SUBSCRIPTION is out of scope for cross-chain ---

    function test_hasAccessWithRemoteProof_subscription_returnsFalse() public {
        // A SUBSCRIPTION tool cannot have cross-chain bindings (see
        // test_addCrossChainCollection_revertsOnSubscription). Even if a
        // caller somehow synthesizes a well-formed proof, the function
        // rejects SUBSCRIPTION tools unconditionally.
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        CrossChainProof memory proof = _makeProof(toolId, user);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    // --- Deactivated tool ---

    function test_hasAccessWithRemoteProof_deactivatedTool_returnsFalse() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        CrossChainProof memory proof = _makeProof(toolId, user);
        assertTrue(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));

        vm.prank(creator);
        registry.deactivateTool(toolId);
        assertFalse(accessRegistry.hasAccessWithRemoteProof(toolId, user, proof));
    }

    // --- addCrossChainCollection ---

    function test_addCrossChainCollection_emitsEvent() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectEmit(true, false, true, true);
        emit IToolAccessRegistryCrossChain.CrossChainBindingAdded(
            toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721
        );
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
    }

    function test_addCrossChainCollection_revertsIfNotCreator() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.NotToolCreator.selector, toolId, other));
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
    }

    function test_addCrossChainCollection_revertsOnZeroCollection() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.InvalidCollection.selector, address(0)));
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, address(0), TokenStandard.ERC721, 0);
    }

    function test_addCrossChainCollection_revertsOnZeroChainId() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistryCrossChain.InvalidChainId.selector, uint256(0)));
        accessRegistry.addCrossChainCollection(toolId, 0, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
    }

    function test_addCrossChainCollection_revertsOnErc721NonZeroTokenId() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.InvalidCollection.selector, REMOTE_COLLECTION));
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 42);
    }

    function test_addCrossChainCollection_revertsOnSubscription_erc721() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(IToolAccessRegistryCrossChain.SubscriptionCrossChainUnsupported.selector, toolId)
        );
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
    }

    function test_addCrossChainCollection_revertsOnSubscription_erc1155() public {
        uint256 toolId = _registerTool(AccessMode.SUBSCRIPTION);

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(IToolAccessRegistryCrossChain.SubscriptionCrossChainUnsupported.selector, toolId)
        );
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC1155, 42);
    }

    /// @dev Documents that the ToolNotFound guard is inherited from ToolRegistry
    ///      via getToolConfig, not duplicated here.
    function test_addCrossChainCollection_revertsOnUnknownTool() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IToolRegistry.ToolNotFound.selector, uint256(999)));
        accessRegistry.addCrossChainCollection(999, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
    }

    function test_addCrossChainCollection_revertsAtMax() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.startPrank(creator);
        for (uint256 i = 0; i < 20; i++) {
            accessRegistry.addCrossChainCollection(
                toolId, REMOTE_CHAIN_ID, address(uint160(0x1000 + i)), TokenStandard.ERC721, 0
            );
        }
        vm.expectRevert(
            abi.encodeWithSelector(IToolAccessRegistryCrossChain.MaxCrossChainCollectionsReached.selector, toolId)
        );
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, address(0x2000), TokenStandard.ERC721, 0);
        vm.stopPrank();
    }

    function test_addCrossChainCollection_independentFromSameChainCap() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        // Same-chain and cross-chain caps are independent: hitting one doesn't
        // affect the other.
        vm.startPrank(creator);
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
        accessRegistry.addCollection(toolId, address(0xC0DE), TokenStandard.ERC721, 0);
        vm.stopPrank();

        assertEq(accessRegistry.getCrossChainCollections(toolId).length, 1);
        assertEq(accessRegistry.getCollections(toolId).length, 1);
    }

    // --- removeCrossChainCollection ---

    function test_removeCrossChainCollection_swapAndPop() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        address second = address(0xCAFE);

        vm.startPrank(creator);
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, second, TokenStandard.ERC721, 0);

        vm.expectEmit(true, false, true, true);
        emit IToolAccessRegistryCrossChain.CrossChainBindingRemoved(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION);
        accessRegistry.removeCrossChainCollection(toolId, 0, REMOTE_CHAIN_ID, REMOTE_COLLECTION);
        vm.stopPrank();

        CrossChainBinding[] memory bindings = accessRegistry.getCrossChainCollections(toolId);
        assertEq(bindings.length, 1);
        // The last element was swapped into the removed slot.
        assertEq(bindings[0].collection, second);
        assertEq(bindings[0].chainId, REMOTE_CHAIN_ID);
    }

    function test_removeCrossChainCollection_revertsOnInvalidIndex() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(IToolAccessRegistryCrossChain.CrossChainBindingNotFound.selector, toolId, 0)
        );
        accessRegistry.removeCrossChainCollection(toolId, 0, REMOTE_CHAIN_ID, REMOTE_COLLECTION);
    }

    function test_removeCrossChainCollection_revertsIfNotCreator() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IToolAccessRegistry.NotToolCreator.selector, toolId, other));
        accessRegistry.removeCrossChainCollection(toolId, 0, REMOTE_CHAIN_ID, REMOTE_COLLECTION);
    }

    function test_removeCrossChainCollection_revertsOnMismatchedExpectedCollection() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        address wrong = address(0xDEAD);
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IToolAccessRegistryCrossChain.CrossChainBindingMismatch.selector,
                toolId,
                0,
                REMOTE_CHAIN_ID,
                wrong,
                REMOTE_CHAIN_ID,
                REMOTE_COLLECTION
            )
        );
        accessRegistry.removeCrossChainCollection(toolId, 0, REMOTE_CHAIN_ID, wrong);
    }

    function test_removeCrossChainCollection_revertsOnMismatchedExpectedChainId() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        _bindCrossChain(toolId);

        uint256 wrongChain = REMOTE_CHAIN_ID + 1;
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IToolAccessRegistryCrossChain.CrossChainBindingMismatch.selector,
                toolId,
                0,
                wrongChain,
                REMOTE_COLLECTION,
                REMOTE_CHAIN_ID,
                REMOTE_COLLECTION
            )
        );
        accessRegistry.removeCrossChainCollection(toolId, 0, wrongChain, REMOTE_COLLECTION);
    }

    /// @dev Same collection address deployed on two chains (e.g. deterministic
    ///      CREATE2): the CAS must discriminate by (chainId, collection), not
    ///      by collection alone, so a race cannot remove the wrong binding.
    function test_removeCrossChainCollection_distinguishesSameAddressAcrossChains() public {
        uint256 toolId = _registerTool(AccessMode.NFT_GATED);
        uint256 otherChain = REMOTE_CHAIN_ID + 1;

        vm.startPrank(creator);
        accessRegistry.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);
        accessRegistry.addCrossChainCollection(toolId, otherChain, REMOTE_COLLECTION, TokenStandard.ERC721, 0);

        // Removing index 0 with the wrong chain's expected id (collection alone
        // would match) must revert loudly.
        vm.expectRevert(
            abi.encodeWithSelector(
                IToolAccessRegistryCrossChain.CrossChainBindingMismatch.selector,
                toolId,
                0,
                otherChain,
                REMOTE_COLLECTION,
                REMOTE_CHAIN_ID,
                REMOTE_COLLECTION
            )
        );
        accessRegistry.removeCrossChainCollection(toolId, 0, otherChain, REMOTE_COLLECTION);

        // Correct (chainId, collection) pair succeeds.
        accessRegistry.removeCrossChainCollection(toolId, 0, REMOTE_CHAIN_ID, REMOTE_COLLECTION);
        vm.stopPrank();

        CrossChainBinding[] memory bindings = accessRegistry.getCrossChainCollections(toolId);
        assertEq(bindings.length, 1);
        assertEq(bindings[0].chainId, otherChain);
    }

    // --- ERC-165 + constants ---

    function test_supportsInterface_IToolAccessRegistryCrossChain() public view {
        assertTrue(accessRegistry.supportsInterface(type(IToolAccessRegistryCrossChain).interfaceId));
    }

    /// @dev Locks the hardcoded interface ID declared in the ERC spec.
    function test_interfaceId_IToolAccessRegistryCrossChain_matchesSpec() public pure {
        assertEq(type(IToolAccessRegistryCrossChain).interfaceId, bytes4(0xb82fff81));
    }

    function test_maxCrossChainCollectionsValue() public view {
        assertEq(accessRegistry.MAX_CROSS_CHAIN_COLLECTIONS(), 20);
    }

    function test_stalenessWindowValue() public view {
        assertEq(accessRegistry.STALENESS_WINDOW(), 300);
    }

    // --- Deployment without GatewayKeyRegistry ---

    function test_hasAccessWithRemoteProof_zeroKeyRegistry_returnsFalse() public {
        // Set up a fresh ToolAccessRegistry with no key registry wired in.
        ToolRegistry freshRegistry = new ToolRegistry();
        ToolAccessRegistry freshAccess = new ToolAccessRegistry(address(freshRegistry), address(0));
        freshRegistry.initialize(address(freshAccess));

        vm.prank(creator);
        uint256 toolId = freshRegistry.registerTool(META_URI, MANIFEST_HASH, AccessMode.NFT_GATED);
        vm.prank(creator);
        freshAccess.addCrossChainCollection(toolId, REMOTE_CHAIN_ID, REMOTE_COLLECTION, TokenStandard.ERC721, 0);

        // Same proof construction but against freshAccess's domain.
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ToolRegistryCrossChain")),
                keccak256(bytes("1")),
                block.chainid,
                address(freshAccess)
            )
        );
        CrossChainProof memory proof = CrossChainProof({
            toolId: toolId,
            account: user,
            chainId: REMOTE_CHAIN_ID,
            collection: REMOTE_COLLECTION,
            tokenId: REMOTE_TOKEN_ID,
            checkedAt: block.timestamp,
            gatewaySignature: ""
        });
        bytes32 structHash = keccak256(
            abi.encode(
                CROSS_CHAIN_PROOF_TYPEHASH,
                proof.toolId,
                proof.account,
                proof.chainId,
                proof.collection,
                proof.tokenId,
                proof.checkedAt
            )
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(gatewayPrivateKey, digest);
        proof.gatewaySignature = abi.encodePacked(r, s, v);

        assertFalse(freshAccess.hasAccessWithRemoteProof(toolId, user, proof));
    }
}
