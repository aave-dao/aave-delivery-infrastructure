// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/console.sol';
import {ICrossChainReceiver} from '../../src/contracts/interfaces/ICrossChainReceiver.sol';
import {Transaction, Envelope, EncodedEnvelope, EncodedTransaction, TransactionUtils, EnvelopeUtils} from '../../src/contracts/libs/EncodingUtils.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../../src/contracts/libs/Errors.sol';
import {ZkSyncAdapter, IZkSyncAdapter, IBridgehub, IBaseAdapter, AddressAliasHelper} from '../../src/contracts/adapters/zkSync/ZkSyncAdapter.sol';
import {BaseAdapterTest} from './BaseAdapterTest.sol';

contract ZkSyncAdapterTest is BaseAdapterTest {
  ZkSyncAdapter internal zkSyncAdapter;

  event SetTrustedRemote(uint256 indexed originChainId, address indexed originForwarder);

  modifier setZkSyncAdapter(
    address crossChainController,
    address originForwarder,
    address mailBox,
    address refundAddress,
    uint256 baseGasLimit,
    uint256 originChainId
  ) {
    vm.assume(crossChainController != tx.origin); // zkVM doesn't support mocking tx.origin
    vm.assume(baseGasLimit < 1 ether);
    _assumeSafeAddress(crossChainController);
    _assumeSafeAddress(mailBox);
    _assumeSafeAddress(refundAddress);
    vm.assume(originForwarder != address(0));
    vm.assume(originChainId > 0);

    IBaseAdapter.TrustedRemotesConfig memory originConfig = IBaseAdapter.TrustedRemotesConfig({
      originForwarder: originForwarder,
      originChainId: originChainId
    });
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](1);
    originConfigs[0] = originConfig;

    zkSyncAdapter = new ZkSyncAdapter(
      crossChainController,
      mailBox,
      refundAddress,
      baseGasLimit,
      originConfigs
    );
    _;
  }

  function setUp() public {}

  function testUndoAlias() public {
    address aliased = 0x91Bbb474eE7E3a04A4eE77bE874bcCEaA01b342a;
    address unaliased = AddressAliasHelper.undoL1ToL2Alias(aliased);
    console.log('unaliased', unaliased);
  }

  function testWrongZkSyncMailbox(
    address crossChainController,
    uint256 baseGasLimit,
    address originForwarder,
    address refundAddress,
    uint256 originChainId
  ) public {
    vm.assume(crossChainController != address(0));
    vm.assume(originForwarder != address(0));
    vm.assume(originChainId > 0);

    IBaseAdapter.TrustedRemotesConfig memory originConfig = IBaseAdapter.TrustedRemotesConfig({
      originForwarder: originForwarder,
      originChainId: originChainId
    });
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](1);
    originConfigs[0] = originConfig;
    vm.expectRevert(bytes(Errors.ZK_SYNC_BRIDGE_HUB_CANT_BE_ADDRESS_0));
    new ZkSyncAdapter(crossChainController, address(0), refundAddress, baseGasLimit, originConfigs);
  }

  function testInitialize(
    address crossChainController,
    address mailbox,
    address originForwarder,
    address refundAddress,
    uint256 baseGasLimit,
    uint256 originChainId
  )
    public
    setZkSyncAdapter(
      crossChainController,
      originForwarder,
      mailbox,
      refundAddress,
      baseGasLimit,
      originChainId
    )
  {
    assertEq(zkSyncAdapter.getTrustedRemoteByChainId(originChainId), originForwarder);
  }

  struct Params {
    address mailbox;
    address receiver;
    uint256 dstGasLimit;
    address caller;
  }

  function testForwardMessage(
    address crossChainController,
    address mailbox,
    address originForwarder,
    address refundAddress
  )
    public
    setZkSyncAdapter(
      crossChainController,
      originForwarder,
      mailbox,
      refundAddress,
      0,
      ChainIds.ETHEREUM
    )
  {
    _testForwardMessage(
      Params({mailbox: mailbox, receiver: address(135961), dstGasLimit: 12, caller: address(12354)})
    );
  }

  function testForwardMessageWhenNoValue(
    address crossChainController,
    address mailbox,
    address originForwarder,
    address refundAddress,
    uint256 dstGasLimit,
    address receiver
  )
    public
    setZkSyncAdapter(
      crossChainController,
      originForwarder,
      mailbox,
      refundAddress,
      0,
      ChainIds.ETHEREUM
    )
  {
    vm.assume(dstGasLimit < 1 ether);
    vm.assume(receiver != address(0));
    _testForwardMessageWhenNoValue(mailbox, receiver, dstGasLimit);
  }

  function testForwardMessageWhenChainNotSupported(
    address crossChainController,
    address mailbox,
    address originForwarder,
    address refundAddress,
    uint256 baseGasLimit,
    uint256 dstGasLimit,
    address receiver,
    bytes memory message
  )
    public
    setZkSyncAdapter(
      crossChainController,
      originForwarder,
      mailbox,
      refundAddress,
      baseGasLimit,
      ChainIds.ETHEREUM
    )
  {
    vm.assume(dstGasLimit > 200000 && dstGasLimit < 1 ether);
    vm.assume(receiver != address(0));

    vm.expectRevert(bytes(Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED));
    zkSyncAdapter.forwardMessage(receiver, dstGasLimit, 11, message);
  }

  function testForwardMessageWhenWrongReceiver(
    address crossChainController,
    address mailbox,
    address originForwarder,
    address refundAddress,
    uint256 baseGasLimit,
    uint256 dstGasLimit,
    bytes memory message
  )
    public
    setZkSyncAdapter(
      crossChainController,
      originForwarder,
      mailbox,
      refundAddress,
      baseGasLimit,
      ChainIds.ETHEREUM
    )
  {
    vm.assume(dstGasLimit > 200000 && dstGasLimit < 1 ether);

    vm.expectRevert(bytes(Errors.RECEIVER_NOT_SET));
    zkSyncAdapter.forwardMessage(address(0), dstGasLimit, ChainIds.ZKSYNC, message);
  }

  function testReceive(
    address crossChainController,
    address mailbox,
    address originForwarder,
    bytes memory message
  )
    public
    setZkSyncAdapter(
      crossChainController,
      originForwarder,
      mailbox,
      address(125),
      0,
      ChainIds.ETHEREUM
    )
  {
    address aliased = AddressAliasHelper.applyL1ToL2Alias(originForwarder);
    hoax(aliased);
    vm.mockCall(
      crossChainController,
      abi.encodeWithSelector(ICrossChainReceiver.receiveCrossChainMessage.selector),
      abi.encode()
    );
    vm.expectCall(
      crossChainController,
      0,
      abi.encodeWithSelector(
        ICrossChainReceiver.receiveCrossChainMessage.selector,
        message,
        ChainIds.ETHEREUM
      )
    );
    zkSyncAdapter.receiveMessage(message);
  }

  function testReceiveWhenRemoteNotTrusted(
    address crossChainController,
    address mailbox,
    address originForwarder,
    address refundAddress,
    address remote
  )
    public
    setZkSyncAdapter(
      crossChainController,
      originForwarder,
      mailbox,
      refundAddress,
      0,
      ChainIds.ETHEREUM
    )
  {
    vm.assume(remote != originForwarder);

    hoax(AddressAliasHelper.applyL1ToL2Alias(remote));
    vm.expectRevert(bytes(Errors.REMOTE_NOT_TRUSTED));

    zkSyncAdapter.receiveMessage(abi.encode('test message'));
  }

  // test of deployed infra in zksync sepolia
  event TestWorked(address indexed originSender, uint256 indexed originChainId, bytes message);
  event TransactionReceived(
    bytes32 transactionId,
    bytes32 indexed envelopeId,
    uint256 indexed originChainId,
    Transaction transaction,
    address indexed bridgeAdapter,
    uint8 confirmations
  );
  event EnvelopeDeliveryAttempted(bytes32 envelopeId, Envelope envelope, bool isDelivered);

  function _testForwardMessageWhenNoValue(
    address mailbox,
    address receiver,
    uint256 dstGasLimit
  ) internal {
    bytes memory message = abi.encode('test message');

    vm.mockCall(
      mailbox,
      abi.encodeWithSelector(IBridgehub.l2TransactionBaseCost.selector),
      abi.encode(10)
    );
    vm.mockCall(
      mailbox,
      10,
      abi.encodeWithSelector(IBridgehub.requestL2TransactionDirect.selector),
      abi.encode(bytes32('test'))
    );
    vm.expectRevert(bytes(Errors.NOT_ENOUGH_VALUE_TO_PAY_BRIDGE_FEES));

    (bool success, ) = address(zkSyncAdapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        receiver,
        dstGasLimit,
        ChainIds.ZKSYNC,
        message
      )
    );
    assertEq(success, false);
  }

  function _testForwardMessage(Params memory params) internal {
    bytes memory message = abi.encode('test message');

    hoax(params.caller, 100 ether);

    vm.mockCall(
      params.mailbox,
      abi.encodeWithSelector(IBridgehub.l2TransactionBaseCost.selector),
      abi.encode(10)
    );
    vm.mockCall(
      params.mailbox,
      10,
      abi.encodeWithSelector(IBridgehub.requestL2TransactionDirect.selector),
      abi.encode(bytes32('test'))
    );
    (bool success, bytes memory returnData) = address(zkSyncAdapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        params.receiver,
        params.dstGasLimit,
        ChainIds.ZKSYNC,
        message
      )
    );
    vm.clearMockedCalls();

    assertEq(success, true);
    assertEq(returnData, abi.encode(params.mailbox, bytes32('test')));
  }
}
