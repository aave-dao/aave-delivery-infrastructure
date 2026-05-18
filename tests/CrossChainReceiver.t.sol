// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {OwnableWithGuardian} from '../src/contracts/old-oz/OwnableWithGuardian.sol';
import {IWithGuardian} from '../src/contracts/old-oz/interfaces/IWithGuardian.sol';

import {CrossChainReceiver, ICrossChainReceiver} from '../src/contracts/CrossChainReceiver.sol';
import {IBaseReceiverPortal} from '../src/contracts/interfaces/IBaseReceiverPortal.sol';
import {Errors} from '../src/contracts/libs/Errors.sol';
import {BaseTest} from './BaseTest.sol';
import {Transaction, Envelope} from '../src/contracts/libs/EncodingUtils.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';

contract CrossChainReceiverTest is BaseTest {
  address public constant GUARDIAN = address(65536 + 12);
  address public constant OWNER = address(65536 + 123);
  address public constant BRIDGE_ADAPTER = address(65536 + 1234);
  address public constant BRIDGE_ADAPTER_2 = address(65536 + 1234567);

  address public constant GOVERNANCE_CORE = address(65536 + 12345);
  address public constant VOTING_MACHINE = address(65536 + 123456);
  uint256 public constant DEFAULT_ORIGIN_CHAIN_ID = 1;

  ICrossChainReceiver public crossChainReceiver;

  // events
  event ConfirmationsUpdated(uint8 newConfirmations, uint256 indexed chainId);

  event ReceiverBridgeAdaptersUpdated(
    address indexed brigeAdapter,
    bool indexed allowed,
    uint256 indexed chainId
  );

  event TransactionReceived(
    bytes32 transactionId,
    bytes32 indexed envelopeId,
    uint256 indexed originChainId,
    Transaction transaction,
    address indexed bridgeAdapter,
    uint8 confirmations
  );

  event EnvelopeDeliveryAttempted(bytes32 envelopeId, Envelope envelope, bool isDelivered);

  event NewInvalidation(uint256 invalidTimestamp, uint256 indexed chainId);

  function setUp() public {
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = 1;
    chainIds[1] = 137;

    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](2);
    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: BRIDGE_ADAPTER,
      chainIds: chainIds
    });
    bridgeAdaptersToAllow[1] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: BRIDGE_ADAPTER_2,
      chainIds: chainIds
    });

    ICrossChainReceiver.ConfirmationInput memory confirmation1 = ICrossChainReceiver
      .ConfirmationInput({chainId: 1, requiredConfirmations: 1});
    ICrossChainReceiver.ConfirmationInput memory confirmation2 = ICrossChainReceiver
      .ConfirmationInput({chainId: 137, requiredConfirmations: 1});
    ICrossChainReceiver.ConfirmationInput[]
      memory initialRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](2);
    initialRequiredConfirmations[0] = confirmation1;
    initialRequiredConfirmations[1] = confirmation2;

    crossChainReceiver = new CrossChainReceiver(
      initialRequiredConfirmations,
      bridgeAdaptersToAllow
    );

    Ownable(address(crossChainReceiver)).transferOwnership(OWNER);
    OwnableWithGuardian(address(crossChainReceiver)).updateGuardian(GUARDIAN);
  }

  function testSetUp() public {
    ICrossChainReceiver.ReceiverConfiguration memory configChain1 = crossChainReceiver
      .getConfigurationByChain(1);
    ICrossChainReceiver.ReceiverConfiguration memory configChain2 = crossChainReceiver
      .getConfigurationByChain(137);

    assertEq(configChain1.validityTimestamp, 0);
    assertEq(configChain1.requiredConfirmation, 1);
    assertEq(crossChainReceiver.getReceiverBridgeAdaptersByChain(1).length, 2);
    assertEq(configChain2.validityTimestamp, 0);
    assertEq(configChain2.requiredConfirmation, 1);
    assertEq(crossChainReceiver.getReceiverBridgeAdaptersByChain(137).length, 2);
    assertEq(Ownable(address(crossChainReceiver)).owner(), OWNER);
    assertEq(OwnableWithGuardian(address(crossChainReceiver)).guardian(), GUARDIAN);

    uint256[] memory supportedChains = crossChainReceiver.getSupportedChains();
    assertEq(supportedChains.length, 2);
    assertEq(supportedChains[0], 1);
    assertEq(supportedChains[1], 137);

    address[] memory allowedBridges = crossChainReceiver.getReceiverBridgeAdaptersByChain(1);
    assertEq(allowedBridges.length, 2);
    assertEq(allowedBridges[0], BRIDGE_ADAPTER);
    assertEq(allowedBridges[1], BRIDGE_ADAPTER_2);
    address[] memory allowedBridges137 = crossChainReceiver.getReceiverBridgeAdaptersByChain(137);
    assertEq(allowedBridges137.length, 2);
    assertEq(allowedBridges137[0], BRIDGE_ADAPTER);
    assertEq(allowedBridges137[1], BRIDGE_ADAPTER_2);
  }

  function testSetUpWhenConfirmations0() public {
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = 1;

    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: BRIDGE_ADAPTER,
      chainIds: chainIds
    });

    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: 1, requiredConfirmations: 0});
    ICrossChainReceiver.ConfirmationInput[]
      memory initialRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    initialRequiredConfirmations[0] = confirmation;

    vm.expectRevert(bytes(Errors.INVALID_REQUIRED_CONFIRMATIONS));
    new CrossChainReceiver(initialRequiredConfirmations, bridgeAdaptersToAllow);
  }

  function testSetUpWhenConfirmationsNotReachable() public {
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = 1;

    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: BRIDGE_ADAPTER,
      chainIds: chainIds
    });

    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: 1, requiredConfirmations: 3});
    ICrossChainReceiver.ConfirmationInput[]
      memory initialRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    initialRequiredConfirmations[0] = confirmation;

    vm.expectRevert(bytes(Errors.INVALID_REQUIRED_CONFIRMATIONS));
    new CrossChainReceiver(initialRequiredConfirmations, bridgeAdaptersToAllow);
  }

  // TEST GETTERS
  function testIsReceiverBridgeAdapterAllowed() public {
    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, 1), true);
    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, 137), true);
  }

  // TEST SETTERS
  function testUpdateConfirmations() public {
    // add new bridge so we can increase confirmations for the test
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = 1;

    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: address(12310123),
      chainIds: chainIds
    });
    hoax(OWNER);
    crossChainReceiver.allowReceiverBridgeAdapters(bridgeAdaptersToAllow);

    // set new confirmations
    uint8 newConfirmations = 2;
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: 1, requiredConfirmations: newConfirmations});
    ICrossChainReceiver.ConfirmationInput[]
      memory newRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    newRequiredConfirmations[0] = confirmation;

    hoax(OWNER);
    vm.expectEmit(false, true, false, true);
    emit ConfirmationsUpdated(newConfirmations, 1);
    crossChainReceiver.updateConfirmations(newRequiredConfirmations);

    assertEq(crossChainReceiver.getConfigurationByChain(1).requiredConfirmation, newConfirmations);
  }

  function testUpdateConfirmationsWhen0() public {
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: 1, requiredConfirmations: 0});
    ICrossChainReceiver.ConfirmationInput[]
      memory newRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    newRequiredConfirmations[0] = confirmation;

    uint8 beforeConfirmations = crossChainReceiver.getConfigurationByChain(1).requiredConfirmation;

    hoax(OWNER);
    vm.expectRevert(bytes(Errors.INVALID_REQUIRED_CONFIRMATIONS));
    crossChainReceiver.updateConfirmations(newRequiredConfirmations);

    assertEq(
      crossChainReceiver.getConfigurationByChain(1).requiredConfirmation,
      beforeConfirmations
    );
  }

  function testUpdateConfirmationsWhenMoreThanAdapters() public {
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: 1, requiredConfirmations: 10});
    ICrossChainReceiver.ConfirmationInput[]
      memory newRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    newRequiredConfirmations[0] = confirmation;

    uint256 beforeConfirmations = crossChainReceiver
      .getConfigurationByChain(1)
      .requiredConfirmation;

    hoax(OWNER);
    vm.expectRevert(bytes(Errors.INVALID_REQUIRED_CONFIRMATIONS));
    crossChainReceiver.updateConfirmations(newRequiredConfirmations);

    assertEq(
      crossChainReceiver.getConfigurationByChain(1).requiredConfirmation,
      beforeConfirmations
    );
  }

  function testUpdateConfirmationsWhenNotOwner() public {
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: 1, requiredConfirmations: 10});
    ICrossChainReceiver.ConfirmationInput[]
      memory newRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    newRequiredConfirmations[0] = confirmation;

    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );
    crossChainReceiver.updateConfirmations(newRequiredConfirmations);
  }

  function testAllowReceiverBridgeAdapters() public {
    address newBridgeAdapter = address(101);
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = 1;

    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: newBridgeAdapter,
      chainIds: chainIds
    });

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit ReceiverBridgeAdaptersUpdated(newBridgeAdapter, true, 1);
    crossChainReceiver.allowReceiverBridgeAdapters(bridgeAdaptersToAllow);

    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(newBridgeAdapter, 1), true);
    assertEq(crossChainReceiver.getReceiverBridgeAdaptersByChain(1).length, 3);

    address[] memory allowedBridges = crossChainReceiver.getReceiverBridgeAdaptersByChain(1);
    assertEq(allowedBridges.length, 3);
    assertEq(allowedBridges[0], BRIDGE_ADAPTER);
    assertEq(allowedBridges[1], BRIDGE_ADAPTER_2);
    assertEq(allowedBridges[2], newBridgeAdapter);
  }

  function testAllowReceiverBridgeAdaptersWhenInvalidBridgeAdapter() public {
    address newBridgeAdapter = address(0);
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = 1;

    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: newBridgeAdapter,
      chainIds: chainIds
    });

    hoax(OWNER);
    vm.expectRevert(bytes(Errors.INVALID_BRIDGE_ADAPTER));
    crossChainReceiver.allowReceiverBridgeAdapters(bridgeAdaptersToAllow);
  }

  function testAllowReceiverBridgeAdaptersWhenNotOwner() public {
    address newBridgeAdapter = address(101);
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = 1;

    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: newBridgeAdapter,
      chainIds: chainIds
    });

    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );
    crossChainReceiver.allowReceiverBridgeAdapters(bridgeAdaptersToAllow);

    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(newBridgeAdapter, 1), false);
  }

  function testDisallowReceiverBridgeAdapters() public {
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory disallowBridges = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](2);
    disallowBridges[0].bridgeAdapter = BRIDGE_ADAPTER;
    disallowBridges[0].chainIds = new uint256[](2);
    disallowBridges[0].chainIds[0] = 1;
    disallowBridges[0].chainIds[1] = 137;
    disallowBridges[1].bridgeAdapter = BRIDGE_ADAPTER_2;
    disallowBridges[1].chainIds = new uint256[](1);
    disallowBridges[1].chainIds[0] = 1;

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit ReceiverBridgeAdaptersUpdated(BRIDGE_ADAPTER, false, 1);
    emit ReceiverBridgeAdaptersUpdated(BRIDGE_ADAPTER, false, 137);
    crossChainReceiver.disallowReceiverBridgeAdapters(disallowBridges);

    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, 1), false);
    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, 137), false);
    assertEq(crossChainReceiver.getReceiverBridgeAdaptersByChain(1).length, 0);
    assertEq(crossChainReceiver.getReceiverBridgeAdaptersByChain(137).length, 1);

    uint256[] memory supportedChains = crossChainReceiver.getSupportedChains();
    assertEq(supportedChains.length, 1);
  }

  function testDisallowAllReceiverBridgeAdapters() public {
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory disallowBridges = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](2);
    disallowBridges[0].bridgeAdapter = BRIDGE_ADAPTER;
    disallowBridges[0].chainIds = new uint256[](2);
    disallowBridges[0].chainIds[0] = 1;
    disallowBridges[0].chainIds[1] = 137;
    disallowBridges[1].bridgeAdapter = BRIDGE_ADAPTER_2;
    disallowBridges[1].chainIds = new uint256[](2);
    disallowBridges[1].chainIds[0] = 1;
    disallowBridges[1].chainIds[1] = 137;

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit ReceiverBridgeAdaptersUpdated(BRIDGE_ADAPTER, false, 1);
    emit ReceiverBridgeAdaptersUpdated(BRIDGE_ADAPTER, false, 137);
    crossChainReceiver.disallowReceiverBridgeAdapters(disallowBridges);

    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, 1), false);
    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, 137), false);
    assertEq(crossChainReceiver.getReceiverBridgeAdaptersByChain(1).length, 0);
    assertEq(crossChainReceiver.getReceiverBridgeAdaptersByChain(137).length, 0);

    uint256[] memory supportedChains = crossChainReceiver.getSupportedChains();
    assertEq(supportedChains.length, 0);
  }

  function testDisallowReceiverBridgeAdaptersWhenNotOwner() public {
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory disallowBridges = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    disallowBridges[0].bridgeAdapter = BRIDGE_ADAPTER;

    disallowBridges[0].chainIds = new uint256[](2);
    disallowBridges[0].chainIds[0] = 1;
    disallowBridges[0].chainIds[1] = 137;

    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );
    crossChainReceiver.disallowReceiverBridgeAdapters(disallowBridges);

    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, 1), true);
    assertEq(crossChainReceiver.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, 137), true);
  }

  // TEST RECEIVE MESSAGES
  function testReceiveCrossChainMessage(uint256 txNonce, uint256 envelopeNonce) public {
    ExtendedTransaction memory txExtended = _generateExtendedTransaction(
      TestParams({
        origin: GOVERNANCE_CORE,
        destination: VOTING_MACHINE,
        originChainId: DEFAULT_ORIGIN_CHAIN_ID,
        destinationChainId: block.chainid,
        envelopeNonce: envelopeNonce,
        transactionNonce: txNonce
      })
    );

    hoax(BRIDGE_ADAPTER);
    vm.mockCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(IBaseReceiverPortal.receiveCrossChainMessage.selector),
      abi.encode()
    );
    vm.expectCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(
        IBaseReceiverPortal.receiveCrossChainMessage.selector,
        txExtended.envelope.origin,
        txExtended.envelope.originChainId,
        txExtended.envelope.message
      )
    );
    vm.expectEmit(true, true, true, true);
    emit TransactionReceived(
      txExtended.transactionId,
      txExtended.envelopeId,
      txExtended.envelope.originChainId,
      txExtended.transaction,
      BRIDGE_ADAPTER,
      1
    );
    vm.expectEmit(true, true, true, true);
    emit EnvelopeDeliveryAttempted(txExtended.envelopeId, txExtended.envelope, true);
    crossChainReceiver.receiveCrossChainMessage(
      txExtended.transactionEncoded,
      txExtended.envelope.originChainId
    );

    // check internal transaction
    assertEq(
      crossChainReceiver.isTransactionReceivedByAdapter(txExtended.transactionId, BRIDGE_ADAPTER),
      true
    );
    ICrossChainReceiver.TransactionStateWithoutAdapters
      memory internalTransactionState = crossChainReceiver.getTransactionState(
        txExtended.transactionId
      );
    ICrossChainReceiver.EnvelopeState internalEnvelopeState = crossChainReceiver.getEnvelopeState(
      txExtended.envelopeId
    );

    assertEq(internalTransactionState.confirmations, 1);
    assertEq(internalTransactionState.firstBridgedAt, block.timestamp);
    assertTrue(internalEnvelopeState == ICrossChainReceiver.EnvelopeState.Delivered);
  }

  function testReceiveCrossChainMessageAfterConfirmation(
    uint256 txNonce,
    uint256 envelopeNonce
  ) public {
    ExtendedTransaction memory txExtended = _generateExtendedTransaction(
      TestParams({
        origin: GOVERNANCE_CORE,
        destination: VOTING_MACHINE,
        originChainId: DEFAULT_ORIGIN_CHAIN_ID,
        destinationChainId: block.chainid,
        envelopeNonce: envelopeNonce,
        transactionNonce: txNonce
      })
    );

    hoax(BRIDGE_ADAPTER);
    vm.mockCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(IBaseReceiverPortal.receiveCrossChainMessage.selector),
      abi.encode()
    );
    vm.expectCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(
        IBaseReceiverPortal.receiveCrossChainMessage.selector,
        txExtended.envelope.origin,
        txExtended.envelope.originChainId,
        txExtended.envelope.message
      )
    );
    vm.expectEmit(true, true, true, true);
    emit TransactionReceived(
      txExtended.transactionId,
      txExtended.envelopeId,
      txExtended.envelope.originChainId,
      txExtended.transaction,
      BRIDGE_ADAPTER,
      1
    );
    vm.expectEmit(true, true, true, true);
    emit EnvelopeDeliveryAttempted(txExtended.envelopeId, txExtended.envelope, true);
    crossChainReceiver.receiveCrossChainMessage(
      txExtended.transactionEncoded,
      txExtended.envelope.originChainId
    );

    // check internal transaction
    assertEq(
      crossChainReceiver.isTransactionReceivedByAdapter(txExtended.transactionId, BRIDGE_ADAPTER),
      true
    );
    ICrossChainReceiver.TransactionStateWithoutAdapters
      memory internalTransactionState = crossChainReceiver.getTransactionState(
        txExtended.transactionId
      );
    ICrossChainReceiver.EnvelopeState internalEnvelopeState = crossChainReceiver.getEnvelopeState(
      txExtended.envelopeId
    );

    assertEq(internalTransactionState.confirmations, 1);
    assertEq(internalTransactionState.firstBridgedAt, block.timestamp);
    assertTrue(internalEnvelopeState == ICrossChainReceiver.EnvelopeState.Delivered);

    // receive 2nd cross chain message after its already confirmed
    hoax(BRIDGE_ADAPTER_2);
    vm.expectEmit(true, true, true, true);
    emit TransactionReceived(
      txExtended.transactionId,
      txExtended.envelopeId,
      txExtended.envelope.originChainId,
      txExtended.transaction,
      BRIDGE_ADAPTER_2,
      2
    );
    crossChainReceiver.receiveCrossChainMessage(
      txExtended.transactionEncoded,
      txExtended.envelope.originChainId
    );

    // check internal transaction
    assertEq(
      crossChainReceiver.isTransactionReceivedByAdapter(txExtended.transactionId, BRIDGE_ADAPTER_2),
      true
    );
    internalTransactionState = crossChainReceiver.getTransactionState(txExtended.transactionId);
    internalEnvelopeState = crossChainReceiver.getEnvelopeState(txExtended.envelopeId);

    assertEq(internalTransactionState.confirmations, 2);
    assertEq(internalTransactionState.firstBridgedAt, block.timestamp);
    assertTrue(internalEnvelopeState == ICrossChainReceiver.EnvelopeState.Delivered);
  }

  function testReceiveCrossChainMessageAfterConfirmationsLowered() public {
    // set initial needed confirmation to 2
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: 1, requiredConfirmations: 2});
    ICrossChainReceiver.ConfirmationInput[]
      memory requiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    requiredConfirmations[0] = confirmation;

    vm.prank(OWNER);
    crossChainReceiver.updateConfirmations(requiredConfirmations);

    ExtendedTransaction memory txExtended = _generateExtendedTransaction(
      TestParams({
        origin: GOVERNANCE_CORE,
        destination: VOTING_MACHINE,
        originChainId: DEFAULT_ORIGIN_CHAIN_ID,
        destinationChainId: block.chainid,
        envelopeNonce: 0,
        transactionNonce: 0
      })
    );

    // receive first confirmation message
    hoax(BRIDGE_ADAPTER);
    vm.mockCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(IBaseReceiverPortal.receiveCrossChainMessage.selector),
      abi.encode()
    );
    vm.expectEmit(true, true, true, true);
    emit TransactionReceived(
      txExtended.transactionId,
      txExtended.envelopeId,
      txExtended.envelope.originChainId,
      txExtended.transaction,
      BRIDGE_ADAPTER,
      1
    );
    crossChainReceiver.receiveCrossChainMessage(
      txExtended.transactionEncoded,
      txExtended.envelope.originChainId
    );

    // lower required confirmations to 1
    requiredConfirmations[0] = ICrossChainReceiver.ConfirmationInput({
      chainId: txExtended.envelope.originChainId,
      requiredConfirmations: 1
    });

    vm.prank(OWNER);
    crossChainReceiver.updateConfirmations(requiredConfirmations);

    // receive second confirmation message
    hoax(BRIDGE_ADAPTER_2);
    vm.mockCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(IBaseReceiverPortal.receiveCrossChainMessage.selector),
      abi.encode()
    );
    vm.expectCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(
        IBaseReceiverPortal.receiveCrossChainMessage.selector,
        txExtended.envelope.origin,
        txExtended.envelope.originChainId,
        txExtended.envelope.message
      )
    );
    vm.expectEmit(true, true, true, true);
    emit TransactionReceived(
      txExtended.transactionId,
      txExtended.envelopeId,
      txExtended.envelope.originChainId,
      txExtended.transaction,
      BRIDGE_ADAPTER_2,
      2
    );

    vm.expectEmit(true, true, false, true);
    emit EnvelopeDeliveryAttempted(txExtended.envelopeId, txExtended.envelope, true);
    crossChainReceiver.receiveCrossChainMessage(
      txExtended.transactionEncoded,
      txExtended.envelope.originChainId
    );

    // check internal message
    assertEq(
      crossChainReceiver.isTransactionReceivedByAdapter(txExtended.transactionId, BRIDGE_ADAPTER),
      true
    );
    assertEq(
      crossChainReceiver.isTransactionReceivedByAdapter(txExtended.transactionId, BRIDGE_ADAPTER_2),
      true
    );
    ICrossChainReceiver.TransactionStateWithoutAdapters
      memory internalTransactionState = crossChainReceiver.getTransactionState(
        txExtended.transactionId
      );
    ICrossChainReceiver.EnvelopeState internalEnvelopeState = crossChainReceiver.getEnvelopeState(
      txExtended.envelopeId
    );

    // Confirmation of the message is GREATER compared to the required confirmations
    assertGt(
      internalTransactionState.confirmations,
      crossChainReceiver.getConfigurationByChain(DEFAULT_ORIGIN_CHAIN_ID).requiredConfirmation
    );
    assertEq(internalTransactionState.confirmations, 2);
    assertEq(internalTransactionState.firstBridgedAt, block.timestamp);
    assertTrue(internalEnvelopeState == ICrossChainReceiver.EnvelopeState.Delivered);
  }

  function testReceiveCrossChainMessageWhenCallerNotBridge() public {
    ExtendedTransaction memory txExtended = _generateExtendedTransaction(
      TestParams({
        origin: GOVERNANCE_CORE,
        destination: VOTING_MACHINE,
        originChainId: DEFAULT_ORIGIN_CHAIN_ID,
        destinationChainId: block.chainid,
        envelopeNonce: 0,
        transactionNonce: 0
      })
    );

    vm.expectRevert(bytes(Errors.CALLER_NOT_APPROVED_BRIDGE));
    crossChainReceiver.receiveCrossChainMessage(
      txExtended.transactionEncoded,
      txExtended.envelope.originChainId
    );
  }

  function testReceiveMessageButNotConfirmation() public {
    // set new adapter
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = DEFAULT_ORIGIN_CHAIN_ID;

    ICrossChainReceiver.ConfirmationInput[]
      memory requiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);

    // set initial needed confirmation to 2
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: DEFAULT_ORIGIN_CHAIN_ID, requiredConfirmations: 2});
    requiredConfirmations[0] = confirmation;

    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    address newAdapter = address(101);

    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: newAdapter,
      chainIds: chainIds
    });

    vm.startPrank(OWNER);
    crossChainReceiver.allowReceiverBridgeAdapters(bridgeAdaptersToAllow);
    crossChainReceiver.updateConfirmations(requiredConfirmations);
    vm.stopPrank();

    ExtendedTransaction memory txExtended = _generateExtendedTransaction(
      TestParams({
        origin: GOVERNANCE_CORE,
        destination: VOTING_MACHINE,
        originChainId: DEFAULT_ORIGIN_CHAIN_ID,
        destinationChainId: block.chainid,
        envelopeNonce: 0,
        transactionNonce: 0
      })
    );

    hoax(BRIDGE_ADAPTER);
    vm.expectEmit(true, true, true, true);
    emit TransactionReceived(
      txExtended.transactionId,
      txExtended.envelopeId,
      txExtended.envelope.originChainId,
      txExtended.transaction,
      BRIDGE_ADAPTER,
      1
    );
    crossChainReceiver.receiveCrossChainMessage(
      txExtended.transactionEncoded,
      txExtended.envelope.originChainId
    );

    // check internal message
    assertEq(
      crossChainReceiver.isTransactionReceivedByAdapter(txExtended.transactionId, BRIDGE_ADAPTER),
      true
    );
    ICrossChainReceiver.TransactionStateWithoutAdapters
      memory internalTransactionState = crossChainReceiver.getTransactionState(
        txExtended.transactionId
      );
    ICrossChainReceiver.EnvelopeState internalEnvelopeState = crossChainReceiver.getEnvelopeState(
      txExtended.envelopeId
    );

    assertEq(internalTransactionState.confirmations, 1);
    assertEq(internalTransactionState.firstBridgedAt, block.timestamp);
    assertTrue(internalEnvelopeState == ICrossChainReceiver.EnvelopeState.None);

    hoax(newAdapter);
    vm.mockCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(IBaseReceiverPortal.receiveCrossChainMessage.selector),
      abi.encode()
    );
    vm.expectCall(
      txExtended.envelope.destination,
      abi.encodeWithSelector(
        IBaseReceiverPortal.receiveCrossChainMessage.selector,
        txExtended.envelope.origin,
        txExtended.envelope.originChainId,
        txExtended.envelope.message
      )
    );
    vm.expectEmit(true, true, true, true);
    emit TransactionReceived(
      txExtended.transactionId,
      txExtended.envelopeId,
      txExtended.envelope.originChainId,
      txExtended.transaction,
      newAdapter,
      2
    );
    vm.expectEmit(true, true, true, true);
    emit EnvelopeDeliveryAttempted(txExtended.envelopeId, txExtended.envelope, true);
    crossChainReceiver.receiveCrossChainMessage(
      txExtended.transactionEncoded,
      txExtended.envelope.originChainId
    );

    //     check internal message
    assertEq(
      crossChainReceiver.isTransactionReceivedByAdapter(txExtended.transactionId, newAdapter),
      true
    );
    ICrossChainReceiver.TransactionStateWithoutAdapters
      memory internalTransactionState2 = crossChainReceiver.getTransactionState(
        txExtended.transactionId
      );
    ICrossChainReceiver.EnvelopeState internalEnvelopeState2 = crossChainReceiver.getEnvelopeState(
      txExtended.envelopeId
    );

    assertEq(internalTransactionState2.confirmations, 2);
    assertEq(internalTransactionState2.firstBridgedAt, block.timestamp);
    assertTrue(internalEnvelopeState2 == ICrossChainReceiver.EnvelopeState.Delivered);
  }

  // TEST INVALIDATIONS
  function testInvalidatePreviousMessages() public {
    uint120 timestamp = uint120(block.timestamp);
    ICrossChainReceiver.ValidityTimestampInput[]
      memory newValidityTimestamps = new ICrossChainReceiver.ValidityTimestampInput[](1);
    newValidityTimestamps[0] = ICrossChainReceiver.ValidityTimestampInput({
      chainId: 1,
      validityTimestamp: timestamp
    });

    hoax(OWNER);
    vm.expectEmit(false, false, false, true);
    emit NewInvalidation(timestamp, 1);
    crossChainReceiver.updateMessagesValidityTimestamp(newValidityTimestamps);

    assertEq(crossChainReceiver.getConfigurationByChain(1).validityTimestamp, timestamp);
  }

  function testInvalidatePreviousMessagesWhenNotOwner() public {
    uint120 timestamp = uint120(block.timestamp);
    ICrossChainReceiver.ValidityTimestampInput[]
      memory newValidityTimestamps = new ICrossChainReceiver.ValidityTimestampInput[](1);
    newValidityTimestamps[0] = ICrossChainReceiver.ValidityTimestampInput({
      chainId: 1,
      validityTimestamp: timestamp
    });

    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );
    crossChainReceiver.updateMessagesValidityTimestamp(newValidityTimestamps);

    assertEq(crossChainReceiver.getConfigurationByChain(1).validityTimestamp, uint120(0));
  }

  function testInvalidatePreviousMessagesWhenFutureTimestamp() public {
    uint120 timestamp = uint120(block.timestamp + 10);
    ICrossChainReceiver.ValidityTimestampInput[]
      memory newValidityTimestamps = new ICrossChainReceiver.ValidityTimestampInput[](1);
    newValidityTimestamps[0] = ICrossChainReceiver.ValidityTimestampInput({
      chainId: 1,
      validityTimestamp: timestamp
    });

    hoax(OWNER);
    vm.expectRevert(bytes(Errors.INVALID_VALIDITY_TIMESTAMP));
    crossChainReceiver.updateMessagesValidityTimestamp(newValidityTimestamps);

    assertEq(crossChainReceiver.getConfigurationByChain(1).validityTimestamp, 0);
  }

  function testInvalidatePreviousMessagesWhenPastTimestamp() public {
    uint120 timestamp = uint120(block.timestamp);
    ICrossChainReceiver.ValidityTimestampInput[]
      memory newValidityTimestamps = new ICrossChainReceiver.ValidityTimestampInput[](1);
    newValidityTimestamps[0] = ICrossChainReceiver.ValidityTimestampInput({
      chainId: 1,
      validityTimestamp: timestamp
    });
    hoax(OWNER);
    vm.expectEmit(false, false, false, true);
    emit NewInvalidation(timestamp, 1);
    crossChainReceiver.updateMessagesValidityTimestamp(newValidityTimestamps);

    assertEq(crossChainReceiver.getConfigurationByChain(1).validityTimestamp, timestamp);

    newValidityTimestamps[0] = ICrossChainReceiver.ValidityTimestampInput({
      chainId: 1,
      validityTimestamp: uint120(timestamp - 1)
    });
    hoax(OWNER);
    vm.expectRevert(bytes(Errors.INVALID_VALIDITY_TIMESTAMP));
    crossChainReceiver.updateMessagesValidityTimestamp(newValidityTimestamps);

    assertEq(crossChainReceiver.getConfigurationByChain(1).validityTimestamp, timestamp);
  }

  function testInvalidation() public {
    // set new adapter
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = DEFAULT_ORIGIN_CHAIN_ID;
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1);
    address newAdapter = address(101);
    bridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: newAdapter,
      chainIds: chainIds
    });

    // set initial needed confirmation to 2
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: DEFAULT_ORIGIN_CHAIN_ID, requiredConfirmations: 2});
    ICrossChainReceiver.ConfirmationInput[]
      memory requiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    requiredConfirmations[0] = confirmation;

    vm.startPrank(OWNER);
    crossChainReceiver.allowReceiverBridgeAdapters(bridgeAdaptersToAllow);
    crossChainReceiver.updateConfirmations(requiredConfirmations);
    vm.stopPrank();

    ExtendedTransaction memory extendedTx = _generateExtendedTransaction(
      TestParams({
        origin: GOVERNANCE_CORE,
        destination: VOTING_MACHINE,
        originChainId: DEFAULT_ORIGIN_CHAIN_ID,
        destinationChainId: block.chainid,
        envelopeNonce: 0,
        transactionNonce: 0
      })
    );

    // send message
    hoax(BRIDGE_ADAPTER);
    crossChainReceiver.receiveCrossChainMessage(
      extendedTx.transactionEncoded,
      extendedTx.envelope.originChainId
    );
    skip(10);
    // check transaction
    assertEq(
      crossChainReceiver.isTransactionReceivedByAdapter(extendedTx.transactionId, BRIDGE_ADAPTER),
      true
    );
    ICrossChainReceiver.TransactionStateWithoutAdapters memory transactionState = crossChainReceiver
      .getTransactionState(extendedTx.transactionId);
    assertEq(transactionState.confirmations, 1);

    // invalidate
    ICrossChainReceiver.ValidityTimestampInput[]
      memory newValidityTimestamps = new ICrossChainReceiver.ValidityTimestampInput[](1);
    newValidityTimestamps[0] = ICrossChainReceiver.ValidityTimestampInput({
      chainId: extendedTx.envelope.originChainId,
      validityTimestamp: uint120(transactionState.firstBridgedAt + 1)
    });

    hoax(OWNER);
    crossChainReceiver.updateMessagesValidityTimestamp(newValidityTimestamps);

    skip(10);

    // send message with same nonce from other adapter
    hoax(newAdapter);
    crossChainReceiver.receiveCrossChainMessage(
      extendedTx.transactionEncoded,
      extendedTx.envelope.originChainId
    );
    ICrossChainReceiver.TransactionStateWithoutAdapters
      memory internalTransactionStateAfter = crossChainReceiver.getTransactionState(
        extendedTx.transactionId
      );
    assertEq(internalTransactionStateAfter.confirmations, 1);

    // send message with new nonce
    ExtendedTransaction memory extendedTxWithNewNonce = _generateExtendedTransaction(
      TestParams({
        destination: extendedTx.envelope.destination,
        origin: extendedTx.envelope.origin,
        originChainId: extendedTx.envelope.originChainId,
        destinationChainId: extendedTx.envelope.destinationChainId,
        envelopeNonce: extendedTx.envelope.nonce,
        transactionNonce: extendedTx.transaction.nonce + 1
      })
    );

    hoax(BRIDGE_ADAPTER);
    crossChainReceiver.receiveCrossChainMessage(
      extendedTxWithNewNonce.transactionEncoded,
      extendedTxWithNewNonce.envelope.originChainId
    );
    ICrossChainReceiver.TransactionStateWithoutAdapters
      memory internalTransactionStateNewNonce = crossChainReceiver.getTransactionState(
        extendedTxWithNewNonce.transactionId
      );

    assertEq(internalTransactionStateNewNonce.confirmations, 1);
  }
}
