// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {OwnableWithGuardian} from '../src/contracts/old-oz/OwnableWithGuardian.sol';
import {ILayerZeroEndpointV2} from '../src/contracts/adapters/layerZero/interfaces/ILayerZeroEndpointV2.sol';
import {IWithGuardian} from '../src/contracts/old-oz/interfaces/IWithGuardian.sol';

import {CrossChainForwarder, ICrossChainForwarder} from '../src/contracts/CrossChainForwarder.sol';
import {IBaseAdapter} from '../src/contracts/adapters/IBaseAdapter.sol';
import {LayerZeroAdapter, ILayerZeroAdapter, MessagingFee, MessagingReceipt} from '../src/contracts/adapters/layerZero/LayerZeroAdapter.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../src/contracts/libs/Errors.sol';
import {Transaction, EncodedTransaction, Envelope} from '../src/contracts/libs/EncodingUtils.sol';
import {BaseTest} from './BaseTest.sol';

contract CrossChainForwarderTest is BaseTest {
  address public constant OWNER = address(65536 + 123);
  address public constant GUARDIAN = address(65536 + 12);
  // mock addresses
  address public constant DESTINATION_BRIDGE_ADAPTER = address(65536 + 12345);
  address public constant SENDER = address(123456);

  uint256 public constant ORIGIN_LZ_CHAIN_ID = ChainIds.ETHEREUM;
  address public constant ORIGIN_SENDER = address(1234567);
  address public constant LZ_ENDPOINT = address(12345678);

  LayerZeroAdapter.TrustedRemotesConfig originConfig =
    IBaseAdapter.TrustedRemotesConfig({
      originForwarder: ORIGIN_SENDER,
      originChainId: ORIGIN_LZ_CHAIN_ID
    });

  ICrossChainForwarder public crossChainForwarder;
  LayerZeroAdapter public lzAdapter;

  ICrossChainForwarder.ForwarderBridgeAdapterConfigInput bridgeAdapterConfig;

  // events
  event SenderUpdated(address indexed sender, bool indexed isApproved);

  event BridgeAdapterUpdated(
    uint256 indexed destinationChainId,
    address indexed bridgeAdapter,
    address destinationBridgeAdapter,
    bool indexed allowed
  );
  event OptimalBandwidthUpdated(uint256 indexed chainId, uint256 optimalBandwidth);
  event EnvelopeRegistered(bytes32 indexed envelopeId, Envelope envelope);

  function setUp() public {
    address[] memory sendersToApprove = new address[](1);
    sendersToApprove[0] = SENDER;

    crossChainForwarder = new CrossChainForwarder(
      new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
      sendersToApprove,
      new ICrossChainForwarder.OptimalBandwidthByChain[](0)
    );

    Ownable(address(crossChainForwarder)).transferOwnership(OWNER);
    OwnableWithGuardian(address(crossChainForwarder)).updateGuardian(GUARDIAN);

    // lz bridge adapter configuration
    LayerZeroAdapter.TrustedRemotesConfig[]
      memory originConfigs = new LayerZeroAdapter.TrustedRemotesConfig[](1);
    originConfigs[0] = originConfig;

    lzAdapter = new LayerZeroAdapter(LZ_ENDPOINT, address(crossChainForwarder), 0, originConfigs);

    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory bridgeAdaptersToAllow = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        1
      );
    bridgeAdapterConfig = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(lzAdapter),
      destinationBridgeAdapter: DESTINATION_BRIDGE_ADAPTER,
      destinationChainId: ChainIds.POLYGON
    });
    bridgeAdaptersToAllow[0] = bridgeAdapterConfig;

    hoax(OWNER);
    crossChainForwarder.enableBridgeAdapters(bridgeAdaptersToAllow);

    ICrossChainForwarder.OptimalBandwidthByChain[]
      memory optimalBandwidthByChain = new ICrossChainForwarder.OptimalBandwidthByChain[](1);
    optimalBandwidthByChain[0].chainId = ChainIds.POLYGON;
    optimalBandwidthByChain[0].optimalBandwidth = 1;

    hoax(OWNER);
    crossChainForwarder.updateOptimalBandwidthByChain(optimalBandwidthByChain);
  }

  function testSetUp() public {
    assertEq(crossChainForwarder.getCurrentEnvelopeNonce(), 0);
    assertEq(Ownable(address(crossChainForwarder)).owner(), OWNER);
  }

  // TEST GETTERS
  function testIsForwarderAllowed() public {
    assertEq(crossChainForwarder.isSenderApproved(SENDER), true);
    assertEq(crossChainForwarder.isSenderApproved(OWNER), false);
  }

  function testGetBridgeAdapterByChain() public {
    ICrossChainForwarder.ChainIdBridgeConfig[] memory configs = crossChainForwarder
      .getForwarderBridgeAdaptersByChain(ChainIds.POLYGON);
    assertEq(configs.length, 1);
    assertEq(configs[0].destinationBridgeAdapter, DESTINATION_BRIDGE_ADAPTER);
    assertEq(configs[0].currentChainBridgeAdapter, address(lzAdapter));
  }

  function testGetBridgeAdapterByChainWhenConfigNotSet() public {
    ICrossChainForwarder.ChainIdBridgeConfig[] memory configs = crossChainForwarder
      .getForwarderBridgeAdaptersByChain(ChainIds.AVALANCHE);

    assertEq(configs.length, 0);
  }

  // TEST SETTERS
  function testUpdateOptimalBandwidthByChain(uint256 optimalBandwidth, uint256 chainId) public {
    ICrossChainForwarder.OptimalBandwidthByChain[]
      memory optimalBandwidthByChain = new ICrossChainForwarder.OptimalBandwidthByChain[](1);
    optimalBandwidthByChain[0].chainId = chainId;
    optimalBandwidthByChain[0].optimalBandwidth = optimalBandwidth;

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit OptimalBandwidthUpdated(chainId, optimalBandwidth);
    crossChainForwarder.updateOptimalBandwidthByChain(optimalBandwidthByChain);

    assertEq(crossChainForwarder.getOptimalBandwidthByChain(chainId), optimalBandwidth);
  }

  function testUpdateOptimalBandwidthByChainWhenNotOwner(
    uint256 optimalBandwidth,
    uint256 chainId
  ) public {
    ICrossChainForwarder.OptimalBandwidthByChain[]
      memory optimalBandwidthByChain = new ICrossChainForwarder.OptimalBandwidthByChain[](1);
    optimalBandwidthByChain[0].chainId = chainId;
    optimalBandwidthByChain[0].optimalBandwidth = optimalBandwidth;

    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );

    crossChainForwarder.updateOptimalBandwidthByChain(optimalBandwidthByChain);
  }

  function testApproveSenders() public {
    address[] memory newSenders = new address[](2);
    address newSender1 = address(101);
    address newSender2 = address(102);
    newSenders[0] = newSender1;
    newSenders[1] = newSender2;

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit SenderUpdated(newSender1, true);
    emit SenderUpdated(newSender2, true);
    crossChainForwarder.approveSenders(newSenders);

    assertEq(crossChainForwarder.isSenderApproved(SENDER), true);
    assertEq(crossChainForwarder.isSenderApproved(newSender1), true);
    assertEq(crossChainForwarder.isSenderApproved(newSender2), true);
  }

  function testApproveSendersWhenAddress0() public {
    address[] memory newSenders = new address[](2);
    address newSender1 = address(101);
    address newSender2 = address(0);
    newSenders[0] = newSender1;
    newSenders[1] = newSender2;

    hoax(OWNER);
    vm.expectRevert(bytes(Errors.INVALID_SENDER));
    crossChainForwarder.approveSenders(newSenders);
  }

  function testApproveSendersWhenNotOwner() public {
    address[] memory newSenders = new address[](1);
    address newSender = address(101);
    newSenders[0] = newSender;
    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );

    crossChainForwarder.approveSenders(newSenders);
  }

  function testRemoveSenders() public {
    address[] memory newSenders = new address[](1);
    newSenders[0] = SENDER;

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit SenderUpdated(SENDER, false);
    crossChainForwarder.removeSenders(newSenders);

    assertEq(crossChainForwarder.isSenderApproved(SENDER), false);
  }

  function testRemoveSendersWhenNotOwner() public {
    address[] memory newSenders = new address[](1);
    newSenders[0] = SENDER;
    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );

    crossChainForwarder.removeSenders(newSenders);

    assertEq(crossChainForwarder.isSenderApproved(SENDER), true);
  }

  function testAllowBridgeAdaptersWhenNotOwner() public {
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory newBridgeAdaptersToEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        0
      );
    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );

    crossChainForwarder.enableBridgeAdapters(newBridgeAdaptersToEnable);
  }

  function testAllowBridgeAdapters() public {
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory newBridgeAdaptersToEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        3
      );

    address NEW_BRIDGE_ADAPTER_1 = address(65536 + 201);
    address NEW_BRIDGE_ADAPTER_2 = address(65536 + 202);
    address NEW_DESTINATION_BRIDGE_ADAPTER_A = address(65536 + 203);

    // this one overwrites
    newBridgeAdaptersToEnable[0] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(lzAdapter),
      destinationBridgeAdapter: DESTINATION_BRIDGE_ADAPTER,
      destinationChainId: ChainIds.POLYGON
    });
    // new one on same network
    newBridgeAdaptersToEnable[1] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: NEW_BRIDGE_ADAPTER_1,
      destinationBridgeAdapter: DESTINATION_BRIDGE_ADAPTER,
      destinationChainId: ChainIds.POLYGON
    });
    // new one on different network but same bridge adapter
    newBridgeAdaptersToEnable[2] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: NEW_BRIDGE_ADAPTER_2,
      destinationBridgeAdapter: NEW_DESTINATION_BRIDGE_ADAPTER_A,
      destinationChainId: ChainIds.AVALANCHE
    });

    hoax(OWNER);
    vm.expectEmit(true, true, true, true);
    emit BridgeAdapterUpdated(
      ChainIds.POLYGON,
      NEW_BRIDGE_ADAPTER_1,
      DESTINATION_BRIDGE_ADAPTER,
      true
    );
    emit BridgeAdapterUpdated(
      ChainIds.AVALANCHE,
      NEW_BRIDGE_ADAPTER_2,
      NEW_DESTINATION_BRIDGE_ADAPTER_A,
      true
    );
    vm.mockCall(
      NEW_BRIDGE_ADAPTER_1,
      abi.encodeWithSelector(IBaseAdapter.setupPayments.selector),
      abi.encode()
    );
    vm.mockCall(
      NEW_BRIDGE_ADAPTER_2,
      abi.encodeWithSelector(IBaseAdapter.setupPayments.selector),
      abi.encode()
    );
    crossChainForwarder.enableBridgeAdapters(newBridgeAdaptersToEnable);

    ICrossChainForwarder.ChainIdBridgeConfig[] memory configsPolygon = crossChainForwarder
      .getForwarderBridgeAdaptersByChain(ChainIds.POLYGON);
    assertEq(configsPolygon.length, 2);
    assertEq(configsPolygon[0].destinationBridgeAdapter, DESTINATION_BRIDGE_ADAPTER);
    assertEq(configsPolygon[0].currentChainBridgeAdapter, address(lzAdapter));

    assertEq(configsPolygon[1].destinationBridgeAdapter, DESTINATION_BRIDGE_ADAPTER);
    assertEq(configsPolygon[1].currentChainBridgeAdapter, NEW_BRIDGE_ADAPTER_1);

    ICrossChainForwarder.ChainIdBridgeConfig[] memory configsAvalanche = crossChainForwarder
      .getForwarderBridgeAdaptersByChain(ChainIds.AVALANCHE);
    assertEq(configsAvalanche.length, 1);
    assertEq(configsAvalanche[0].destinationBridgeAdapter, NEW_DESTINATION_BRIDGE_ADAPTER_A);
    assertEq(configsAvalanche[0].currentChainBridgeAdapter, NEW_BRIDGE_ADAPTER_2);
  }

  function testAllowBridgeAdaptersWhenNoCurrentBridgeAdapter() public {
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory newBridgeAdaptersToEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        3
      );

    // this one overwrites
    newBridgeAdaptersToEnable[0] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(0),
      destinationBridgeAdapter: DESTINATION_BRIDGE_ADAPTER,
      destinationChainId: ChainIds.POLYGON
    });

    hoax(OWNER);
    vm.expectRevert(bytes(Errors.CURRENT_OR_DESTINATION_CHAIN_ADAPTER_NOT_SET));

    crossChainForwarder.enableBridgeAdapters(newBridgeAdaptersToEnable);
  }

  function testAllowBridgeAdaptersWhenNoDestinationBridgeAdapter() public {
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory newBridgeAdaptersToEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        3
      );

    // this one overwrites
    newBridgeAdaptersToEnable[0] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(lzAdapter),
      destinationBridgeAdapter: address(0),
      destinationChainId: ChainIds.POLYGON
    });

    hoax(OWNER);
    vm.expectRevert(bytes(Errors.CURRENT_OR_DESTINATION_CHAIN_ADAPTER_NOT_SET));

    crossChainForwarder.enableBridgeAdapters(newBridgeAdaptersToEnable);
  }

  function testAllowBridgeAdaptersOverwrite() public {
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory newBridgeAdaptersToEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        1
      );

    address NEW_DESTINATION_BRIDGE_ADAPTER_A = address(203);

    // this one overwrites
    newBridgeAdaptersToEnable[0] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(lzAdapter),
      destinationBridgeAdapter: NEW_DESTINATION_BRIDGE_ADAPTER_A,
      destinationChainId: ChainIds.POLYGON
    });

    hoax(OWNER);
    vm.expectEmit(true, true, true, true);
    emit BridgeAdapterUpdated(
      ChainIds.POLYGON,
      address(lzAdapter),
      NEW_DESTINATION_BRIDGE_ADAPTER_A,
      true
    );
    crossChainForwarder.enableBridgeAdapters(newBridgeAdaptersToEnable);

    ICrossChainForwarder.ChainIdBridgeConfig[] memory configsPolygon = crossChainForwarder
      .getForwarderBridgeAdaptersByChain(ChainIds.POLYGON);
    assertEq(configsPolygon.length, 1);
    assertEq(configsPolygon[0].destinationBridgeAdapter, NEW_DESTINATION_BRIDGE_ADAPTER_A);
    assertEq(configsPolygon[0].currentChainBridgeAdapter, address(lzAdapter));
  }

  function testDisallowBridgeAdapters() public {
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory newBridgeAdaptersToEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        2
      );

    address NEW_BRIDGE_ADAPTER_1 = address(65536 + 201);
    address NEW_DESTINATION_BRIDGE_ADAPTER_A = address(65536 + 203);

    // new one on same network
    newBridgeAdaptersToEnable[0] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: NEW_BRIDGE_ADAPTER_1,
      destinationBridgeAdapter: DESTINATION_BRIDGE_ADAPTER,
      destinationChainId: ChainIds.POLYGON
    });
    // new one on different network but same bridge adapter
    newBridgeAdaptersToEnable[1] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(lzAdapter),
      destinationBridgeAdapter: NEW_DESTINATION_BRIDGE_ADAPTER_A,
      destinationChainId: ChainIds.AVALANCHE
    });

    vm.mockCall(
      NEW_BRIDGE_ADAPTER_1,
      abi.encodeWithSelector(IBaseAdapter.setupPayments.selector),
      abi.encode()
    );
    hoax(OWNER);
    crossChainForwarder.enableBridgeAdapters(newBridgeAdaptersToEnable);

    ICrossChainForwarder.BridgeAdapterToDisable[]
      memory bridgeAdaptersToDisable = new ICrossChainForwarder.BridgeAdapterToDisable[](1);

    uint256[] memory chainIdsAdapter = new uint256[](2);
    chainIdsAdapter[0] = ChainIds.POLYGON;
    chainIdsAdapter[1] = ChainIds.AVALANCHE;

    bridgeAdaptersToDisable[0] = ICrossChainForwarder.BridgeAdapterToDisable({
      bridgeAdapter: address(lzAdapter),
      chainIds: chainIdsAdapter
    });

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit BridgeAdapterUpdated(
      ChainIds.POLYGON,
      address(lzAdapter),
      DESTINATION_BRIDGE_ADAPTER,
      false
    );
    emit BridgeAdapterUpdated(
      ChainIds.AVALANCHE,
      address(lzAdapter),
      NEW_DESTINATION_BRIDGE_ADAPTER_A,
      false
    );
    crossChainForwarder.disableBridgeAdapters(bridgeAdaptersToDisable);

    ICrossChainForwarder.ChainIdBridgeConfig[] memory configsPolygon = crossChainForwarder
      .getForwarderBridgeAdaptersByChain(ChainIds.POLYGON);
    assertEq(configsPolygon.length, 1);
    assertEq(configsPolygon[0].destinationBridgeAdapter, DESTINATION_BRIDGE_ADAPTER);
    assertEq(configsPolygon[0].currentChainBridgeAdapter, NEW_BRIDGE_ADAPTER_1);

    ICrossChainForwarder.ChainIdBridgeConfig[] memory configsAvalanche = crossChainForwarder
      .getForwarderBridgeAdaptersByChain(ChainIds.AVALANCHE);
    assertEq(configsAvalanche.length, 0);
  }

  function testDisallowBridgeAdaptersWhenNotOwner() public {
    ICrossChainForwarder.BridgeAdapterToDisable[]
      memory bridgeAdaptersToDisable = new ICrossChainForwarder.BridgeAdapterToDisable[](0);
    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );

    crossChainForwarder.disableBridgeAdapters(bridgeAdaptersToDisable);
  }

  // TEST FORWARDING MESSAGES
  function testForwardMessage(address destination) public {
    ExtendedTransaction memory extendedTx = _generateExtendedTransaction(
      TestParams({
        origin: SENDER,
        destination: destination,
        originChainId: block.chainid,
        destinationChainId: ChainIds.POLYGON,
        envelopeNonce: crossChainForwarder.getCurrentEnvelopeNonce(),
        transactionNonce: crossChainForwarder.getCurrentTransactionNonce()
      })
    );

    hoax(extendedTx.envelope.origin);
    deal(address(crossChainForwarder), 10 ether);
    vm.mockCall(
      LZ_ENDPOINT,
      abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
      abi.encode(MessagingFee({nativeFee: 10, lzTokenFee: 0}))
    );
    vm.mockCall(
      LZ_ENDPOINT,
      10,
      abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector),
      abi.encode(
        MessagingReceipt({
          guid: bytes32(0),
          nonce: 2,
          fee: MessagingFee({nativeFee: 10, lzTokenFee: 0})
        })
      )
    );
    vm.expectEmit(true, true, false, true);
    emit EnvelopeRegistered(extendedTx.envelopeId, extendedTx.envelope);
    (bytes32 returnedEnvelopeId, bytes32 returnedTransactionId) = crossChainForwarder
      .forwardMessage(
        extendedTx.envelope.destinationChainId,
        extendedTx.envelope.destination,
        0,
        extendedTx.envelope.message
      );

    assertEq(returnedEnvelopeId, extendedTx.envelopeId);
    assertEq(returnedTransactionId, extendedTx.transactionId);

    assertEq(crossChainForwarder.isEnvelopeRegistered(extendedTx.envelopeId), true);
    assertEq(crossChainForwarder.getCurrentEnvelopeNonce(), extendedTx.envelope.nonce + 1);
    assertEq(crossChainForwarder.getCurrentTransactionNonce(), extendedTx.transaction.nonce + 1);
  }

  function testForwardMessageWhenAllBridgesFail(address destination) public {
    ExtendedTransaction memory extendedTx = _generateExtendedTransaction(
      TestParams({
        origin: SENDER,
        destination: destination,
        originChainId: block.chainid,
        destinationChainId: ChainIds.POLYGON,
        envelopeNonce: crossChainForwarder.getCurrentEnvelopeNonce(),
        transactionNonce: crossChainForwarder.getCurrentTransactionNonce()
      })
    );

    hoax(extendedTx.envelope.origin);
    vm.expectEmit(true, true, false, true);
    emit EnvelopeRegistered(extendedTx.envelopeId, extendedTx.envelope);
    (bytes32 returnedEnvelopeId, bytes32 returnedTransactionId) = crossChainForwarder
      .forwardMessage(
        extendedTx.envelope.destinationChainId,
        extendedTx.envelope.destination,
        0,
        extendedTx.envelope.message
      );

    assertEq(returnedEnvelopeId, extendedTx.envelopeId);
    assertEq(returnedTransactionId, extendedTx.transactionId);

    assertTrue(
      crossChainForwarder.isEnvelopeRegistered(extendedTx.envelope),
      'envelope not registered'
    );
    assertTrue(
      crossChainForwarder.isTransactionForwarded(extendedTx.transaction),
      'transaction not registered'
    );

    assertEq(
      crossChainForwarder.getCurrentEnvelopeNonce(),
      extendedTx.envelope.nonce + 1,
      'wrong envelopeNonce'
    );
    assertEq(
      crossChainForwarder.getCurrentTransactionNonce(),
      extendedTx.transaction.nonce + 1,
      'wrong transactionNonce'
    );
  }

  function testForwardMessageWhenNotApprovedSender(address destination) public {
    bytes memory message = abi.encode(0);
    vm.expectRevert(bytes(Errors.CALLER_IS_NOT_APPROVED_SENDER));
    crossChainForwarder.forwardMessage(ChainIds.POLYGON, destination, 0, message);
  }

  function testForwardMessageWithoutAdapters(address destination) public {
    hoax(SENDER);
    vm.expectRevert(bytes(Errors.NO_BRIDGE_ADAPTERS_FOR_SPECIFIED_CHAIN));
    crossChainForwarder.forwardMessage(ChainIds.AVALANCHE, destination, 0, bytes('msg'));
  }

  function testRetryEnvelopWhenGuardian(address destination) public {
    ExtendedTransaction memory extendedTx = _generateExtendedTransaction(
      TestParams({
        origin: SENDER,
        destination: destination,
        originChainId: block.chainid,
        destinationChainId: ChainIds.POLYGON,
        envelopeNonce: crossChainForwarder.getCurrentEnvelopeNonce(),
        transactionNonce: crossChainForwarder.getCurrentTransactionNonce()
      })
    );

    deal(address(crossChainForwarder), 100 ether);

    hoax(SENDER);
    vm.mockCall(
      LZ_ENDPOINT,
      abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
      abi.encode(MessagingFee({nativeFee: 10, lzTokenFee: 0}))
    );
    vm.mockCall(
      LZ_ENDPOINT,
      10,
      abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector),
      abi.encode(
        MessagingReceipt({
          guid: bytes32(0),
          nonce: 2,
          fee: MessagingFee({nativeFee: 10, lzTokenFee: 0})
        })
      )
    );

    vm.expectEmit(true, true, false, true);
    emit EnvelopeRegistered(extendedTx.envelopeId, extendedTx.envelope);
    (bytes32 returnedEnvelopeId, bytes32 returnedTransactionId) = crossChainForwarder
      .forwardMessage(
        extendedTx.envelope.destinationChainId,
        extendedTx.envelope.destination,
        0,
        extendedTx.envelope.message
      );

    assertEq(returnedEnvelopeId, extendedTx.envelopeId);
    assertEq(returnedTransactionId, extendedTx.transactionId);

    assertTrue(crossChainForwarder.isEnvelopeRegistered(extendedTx.envelope));
    assertTrue(crossChainForwarder.isTransactionForwarded(extendedTx.transaction));

    ExtendedTransaction memory extendedTxOnRetry = _generateExtendedTransaction(
      TestParams({
        origin: extendedTx.envelope.origin,
        destination: extendedTx.envelope.destination,
        originChainId: extendedTx.envelope.originChainId,
        destinationChainId: extendedTx.envelope.destinationChainId,
        envelopeNonce: extendedTx.envelope.nonce,
        transactionNonce: extendedTx.transaction.nonce + 1
      })
    );

    hoax(GUARDIAN);
    crossChainForwarder.retryEnvelope(extendedTx.envelope, 0);

    assertTrue(crossChainForwarder.isTransactionForwarded(extendedTxOnRetry.transaction));
    assertEq(crossChainForwarder.getCurrentEnvelopeNonce(), extendedTx.envelope.nonce + 1);
    assertEq(crossChainForwarder.getCurrentTransactionNonce(), extendedTx.transaction.nonce + 2);
  }

  function testReForwardMessageWhenOwner(address destination) public {
    ExtendedTransaction memory extendedTx = _generateExtendedTransaction(
      TestParams({
        origin: SENDER,
        destination: destination,
        originChainId: block.chainid,
        destinationChainId: ChainIds.POLYGON,
        envelopeNonce: crossChainForwarder.getCurrentEnvelopeNonce(),
        transactionNonce: crossChainForwarder.getCurrentTransactionNonce()
      })
    );

    deal(address(crossChainForwarder), 100 ether);

    hoax(extendedTx.envelope.origin);
    vm.mockCall(
      LZ_ENDPOINT,
      abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
      abi.encode(MessagingFee({nativeFee: 10, lzTokenFee: 0}))
    );
    vm.mockCall(
      LZ_ENDPOINT,
      10,
      abi.encodeWithSelector(ILayerZeroEndpointV2.send.selector),
      abi.encode(
        MessagingReceipt({
          guid: bytes32(0),
          nonce: 2,
          fee: MessagingFee({nativeFee: 10, lzTokenFee: 0})
        })
      )
    );
    vm.expectEmit(true, true, false, true);
    emit EnvelopeRegistered(extendedTx.envelopeId, extendedTx.envelope);
    (bytes32 returnedEnvelopeId, bytes32 returnedTransactionId) = crossChainForwarder
      .forwardMessage(
        extendedTx.envelope.destinationChainId,
        extendedTx.envelope.destination,
        0,
        extendedTx.envelope.message
      );
    assertEq(returnedEnvelopeId, extendedTx.envelopeId);
    assertEq(returnedTransactionId, extendedTx.transactionId);

    EncodedTransaction memory transactionOnRetry = (
      Transaction({
        nonce: extendedTx.transaction.nonce + 1,
        encodedEnvelope: extendedTx.envelopeEncoded
      })
    ).encode();

    hoax(GUARDIAN);
    crossChainForwarder.retryEnvelope(extendedTx.envelope, 0);

    assertTrue(crossChainForwarder.isEnvelopeRegistered(extendedTx.envelope));
    assertTrue(crossChainForwarder.isTransactionForwarded(extendedTx.transaction));
    assertTrue(crossChainForwarder.isTransactionForwarded(transactionOnRetry.id));
    assertEq(crossChainForwarder.getCurrentEnvelopeNonce(), extendedTx.envelope.nonce + 1);
    assertEq(crossChainForwarder.getCurrentTransactionNonce(), extendedTx.transaction.nonce + 2);
  }

  function testRetryNotRegisteredEnvelope() public {
    Envelope memory envelope;

    hoax(GUARDIAN);
    vm.expectRevert(bytes(Errors.ENVELOPE_NOT_PREVIOUSLY_REGISTERED));
    crossChainForwarder.retryEnvelope(envelope, 0);
  }

  function testRetryEnvelopWhenNotGuardianOrOwner() public {
    Envelope memory envelope;

    vm.expectRevert(bytes('ONLY_BY_OWNER_OR_GUARDIAN'));
    crossChainForwarder.retryEnvelope(envelope, 0);
  }

  function testRetryNotRegisteredTransaction() public {
    hoax(GUARDIAN);
    vm.expectRevert(bytes(Errors.TRANSACTION_NOT_PREVIOUSLY_FORWARDED));
    crossChainForwarder.retryTransaction(bytes(''), 0, new address[](0));
  }

  function testRetryTransactionWhenNotGuardianOrOwner() public {
    vm.expectRevert(bytes('ONLY_BY_OWNER_OR_GUARDIAN'));
    crossChainForwarder.retryTransaction(bytes(''), 0, new address[](0));
  }
}
