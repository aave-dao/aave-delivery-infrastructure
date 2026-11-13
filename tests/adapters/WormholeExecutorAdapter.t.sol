// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {WormholeExecutorAdapter} from '../../src/contracts/adapters/wormhole/WormholeExecutorAdapter.sol';
import {IWormholeExecutorAdapter} from '../../src/contracts/adapters/wormhole/IWormholeExecutorAdapter.sol';
import {ICoreBridge, CoreBridgeVM, GuardianSignature} from '../../src/contracts/adapters/wormhole/interfaces/ICoreBridge.sol';
import {IExecutorQuoterRouter} from '../../src/contracts/adapters/wormhole/interfaces/IExecutorQuoterRouter.sol';
import {IBaseAdapter} from '../../src/contracts/adapters/IBaseAdapter.sol';
import {ICrossChainReceiver} from '../../src/contracts/interfaces/ICrossChainReceiver.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../../src/contracts/libs/Errors.sol';
import {BaseAdapterTest} from './BaseAdapterTest.sol';

contract WormholeExecutorAdapterTest is BaseAdapterTest {
  // wormhole chain ids
  uint16 internal constant WH_ETHEREUM = 2;
  uint16 internal constant WH_MONAD = 48;

  WormholeExecutorAdapter internal adapter;

  address internal crossChainController = makeAddr('crossChainController');
  address internal wormholeCore = makeAddr('wormholeCore');
  address internal quoterRouter = makeAddr('quoterRouter');
  address internal quoter = makeAddr('quoter');
  address internal refundAddress = makeAddr('refundAddress');
  address internal originForwarder = makeAddr('originForwarder');
  uint256 internal constant BASE_GAS_LIMIT = 100_000;
  uint8 internal constant CONSISTENCY_LEVEL = 202;

  function setUp() public {
    // the source chain id is read from the Core bridge in the constructor
    vm.mockCall(
      wormholeCore,
      abi.encodeWithSelector(ICoreBridge.chainId.selector),
      abi.encode(WH_ETHEREUM)
    );
    adapter = _deployAdapter(crossChainController);
  }

  function _deployAdapter(address ccc) internal returns (WormholeExecutorAdapter) {
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](1);
    originConfigs[0] = IBaseAdapter.TrustedRemotesConfig({
      originForwarder: originForwarder,
      originChainId: ChainIds.ETHEREUM
    });
    return
      new WormholeExecutorAdapter(
        ccc,
        wormholeCore,
        quoterRouter,
        quoter,
        refundAddress,
        BASE_GAS_LIMIT,
        originConfigs
      );
  }

  // -------------------------------------------------------------------------
  // constructor
  // -------------------------------------------------------------------------

  function test_initialize() public view {
    assertEq(adapter.WORMHOLE_CORE(), wormholeCore);
    assertEq(adapter.EXECUTOR_QUOTER_ROUTER(), quoterRouter);
    assertEq(adapter.QUOTER(), quoter);
    assertEq(adapter.REFUND_ADDRESS(), refundAddress);
    assertEq(adapter.WORMHOLE_SOURCE_CHAIN_ID(), WH_ETHEREUM);
    assertEq(adapter.CONSISTENCY_LEVEL(), CONSISTENCY_LEVEL);
    assertEq(adapter.getTrustedRemoteByChainId(ChainIds.ETHEREUM), originForwarder);
  }

  function test_constructorRevertsWhenCoreIsZero() public {
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](0);
    vm.expectRevert(bytes(Errors.WORMHOLE_CORE_CANT_BE_ADDRESS_0));
    new WormholeExecutorAdapter(
      crossChainController,
      address(0),
      quoterRouter,
      quoter,
      refundAddress,
      BASE_GAS_LIMIT,
      originConfigs
    );
  }

  function test_constructorRevertsWhenQuoterRouterIsZero() public {
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](0);
    vm.expectRevert(bytes(Errors.WORMHOLE_QUOTER_ROUTER_CANT_BE_ADDRESS_0));
    new WormholeExecutorAdapter(
      crossChainController,
      wormholeCore,
      address(0),
      quoter,
      refundAddress,
      BASE_GAS_LIMIT,
      originConfigs
    );
  }

  function test_constructorRevertsWhenQuoterIsZero() public {
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](0);
    vm.expectRevert(bytes(Errors.WORMHOLE_QUOTER_CANT_BE_ADDRESS_0));
    new WormholeExecutorAdapter(
      crossChainController,
      wormholeCore,
      quoterRouter,
      address(0),
      refundAddress,
      BASE_GAS_LIMIT,
      originConfigs
    );
  }

  // -------------------------------------------------------------------------
  // chain id maps
  // -------------------------------------------------------------------------

  function test_nativeToInfraChainId() public view {
    assertEq(adapter.nativeToInfraChainId(WH_ETHEREUM), ChainIds.ETHEREUM);
    assertEq(adapter.nativeToInfraChainId(WH_MONAD), ChainIds.MONAD);
    assertEq(adapter.nativeToInfraChainId(4), ChainIds.BNB);
    assertEq(adapter.nativeToInfraChainId(30), ChainIds.BASE);
    assertEq(adapter.nativeToInfraChainId(34), ChainIds.SCROLL);
    assertEq(adapter.nativeToInfraChainId(37), ChainIds.XLAYER);
    assertEq(adapter.nativeToInfraChainId(46), ChainIds.INK);
    assertEq(adapter.nativeToInfraChainId(64), ChainIds.MEGAETH);
    assertEq(adapter.nativeToInfraChainId(99), 0);
  }

  function test_infraToNativeChainId() public view {
    assertEq(adapter.infraToNativeChainId(ChainIds.ETHEREUM), WH_ETHEREUM);
    assertEq(adapter.infraToNativeChainId(ChainIds.MONAD), WH_MONAD);
    assertEq(adapter.infraToNativeChainId(ChainIds.BNB), 4);
    assertEq(adapter.infraToNativeChainId(ChainIds.BASE), 30);
    assertEq(adapter.infraToNativeChainId(ChainIds.MANTLE), 35);
    assertEq(adapter.infraToNativeChainId(ChainIds.LINEA), 38);
    assertEq(adapter.infraToNativeChainId(ChainIds.SONIC), 52);
    assertEq(adapter.infraToNativeChainId(ChainIds.PLASMA), 58);
    // chains without a Wormhole core are intentionally unmapped
    assertEq(adapter.infraToNativeChainId(ChainIds.ZKSYNC), 0);
    assertEq(adapter.infraToNativeChainId(ChainIds.GNOSIS), 0);
    assertEq(adapter.infraToNativeChainId(99), 0);
  }

  // -------------------------------------------------------------------------
  // forwardMessage
  // -------------------------------------------------------------------------

  function test_forwardMessage() public {
    bytes memory message = abi.encode('test message');
    uint256 dstGasLimit = 300_000;
    address receiver = makeAddr('receiver');
    uint256 executorFee = 100;
    uint256 messageFee = 10;
    uint64 sequence = 42;

    _mockSend(executorFee, messageFee, sequence);

    // the raw a.DI envelope is published as-is (no wrapping), at the configured consistency level
    vm.expectCall(
      wormholeCore,
      messageFee,
      abi.encodeWithSelector(
        ICoreBridge.publishMessage.selector,
        uint32(0),
        message,
        CONSISTENCY_LEVEL
      )
    );

    vm.deal(address(this), 1 ether);
    (bool success, bytes memory returnData) = address(adapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        receiver,
        dstGasLimit,
        ChainIds.MONAD,
        message
      )
    );
    vm.clearMockedCalls();

    assertEq(success, true);
    assertEq(returnData, abi.encode(quoterRouter, uint256(sequence)));
  }

  function test_forwardMessageRevertsWhenChainNotSupported() public {
    // Gnosis has no Wormhole core, so it is intentionally unmapped (returns 0)
    vm.expectRevert(bytes(Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED));
    adapter.forwardMessage(makeAddr('receiver'), 300_000, ChainIds.GNOSIS, abi.encode('x'));
  }

  function test_forwardMessageRevertsWhenReceiverNotSet() public {
    vm.expectRevert(bytes(Errors.RECEIVER_NOT_SET));
    adapter.forwardMessage(address(0), 300_000, ChainIds.MONAD, abi.encode('x'));
  }

  function test_forwardMessageRevertsWhenNotEnoughBalance() public {
    bytes memory message = abi.encode('test message');
    _mockSend(100, 10, 42);

    // address(this) under delegatecall holds no balance to cover the fees
    vm.deal(address(this), 5);
    (bool success, bytes memory returnData) = address(adapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        makeAddr('receiver'),
        uint256(300_000),
        ChainIds.MONAD,
        message
      )
    );
    vm.clearMockedCalls();

    assertEq(success, false);
    assertEq(
      returnData,
      abi.encodeWithSignature('Error(string)', Errors.NOT_ENOUGH_VALUE_TO_PAY_BRIDGE_FEES)
    );
  }

  function _mockSend(uint256 executorFee, uint256 messageFee, uint64 sequence) internal {
    vm.mockCall(
      quoterRouter,
      abi.encodeWithSelector(IExecutorQuoterRouter.quoteExecution.selector),
      abi.encode(executorFee)
    );
    vm.mockCall(
      wormholeCore,
      abi.encodeWithSelector(ICoreBridge.messageFee.selector),
      abi.encode(messageFee)
    );
    vm.mockCall(
      wormholeCore,
      messageFee,
      abi.encodeWithSelector(ICoreBridge.publishMessage.selector),
      abi.encode(sequence)
    );
    vm.mockCall(
      quoterRouter,
      executorFee,
      abi.encodeWithSelector(IExecutorQuoterRouter.requestExecution.selector),
      abi.encode()
    );
  }

  // -------------------------------------------------------------------------
  // executeVAAv1 (receive)
  // -------------------------------------------------------------------------

  function test_executeVAAv1() public {
    bytes memory message = abi.encode('inbound message');
    bytes memory vaa = abi.encode('encoded-vaa');
    _mockParseAndVerify(vaa, WH_ETHEREUM, originForwarder, 7, message, true, '');

    vm.mockCall(
      crossChainController,
      abi.encodeWithSelector(ICrossChainReceiver.receiveCrossChainMessage.selector),
      abi.encode()
    );
    // the raw VAA payload is registered as-is (no unwrapping)
    vm.expectCall(
      crossChainController,
      0,
      abi.encodeWithSelector(
        ICrossChainReceiver.receiveCrossChainMessage.selector,
        message,
        ChainIds.ETHEREUM
      )
    );

    adapter.executeVAAv1(vaa);
  }

  function test_executeVAAv1RevertsWhenInvalidVAA() public {
    bytes memory vaa = abi.encode('encoded-vaa');
    _mockParseAndVerify(
      vaa,
      WH_ETHEREUM,
      originForwarder,
      7,
      abi.encode('m'),
      false,
      'bad signatures'
    );
    vm.expectRevert(bytes('bad signatures'));
    adapter.executeVAAv1(vaa);
  }

  function test_executeVAAv1RevertsWhenRemoteNotTrusted() public {
    bytes memory vaa = abi.encode('encoded-vaa');
    _mockParseAndVerify(vaa, WH_ETHEREUM, makeAddr('attacker'), 7, abi.encode('m'), true, '');
    vm.expectRevert(bytes(Errors.REMOTE_NOT_TRUSTED));
    adapter.executeVAAv1(vaa);
  }

  function _mockParseAndVerify(
    bytes memory vaa,
    uint16 emitterChainId,
    address emitter,
    uint64 sequence,
    bytes memory payload,
    bool valid,
    string memory reason
  ) internal {
    CoreBridgeVM memory parsed;
    parsed.version = 1;
    parsed.emitterChainId = emitterChainId;
    parsed.emitterAddress = bytes32(uint256(uint160(emitter)));
    parsed.sequence = sequence;
    parsed.consistencyLevel = 1;
    parsed.payload = payload;
    parsed.signatures = new GuardianSignature[](0);

    vm.mockCall(
      wormholeCore,
      abi.encodeWithSelector(ICoreBridge.parseAndVerifyVM.selector, vaa),
      abi.encode(parsed, valid, reason)
    );
  }
}
