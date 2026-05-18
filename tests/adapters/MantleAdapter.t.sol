// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IMantleAdapter, IBaseAdapter} from '../../src/contracts/adapters/mantle/IMantleAdapter.sol';
import {MantleAdapter} from '../../src/contracts/adapters/mantle/MantleAdapter.sol';
import {ICrossChainReceiver} from '../../src/contracts/interfaces/ICrossChainReceiver.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../../src/contracts/libs/Errors.sol';
import {BaseAdapterTest} from './BaseAdapterTest.sol';
import {ICrossDomainMessenger} from '../../src/contracts/adapters/optimism/interfaces/ICrossDomainMessenger.sol';

contract MantleAdapterTest is BaseAdapterTest {
  MantleAdapter internal mantleAdapter;
  event SetTrustedRemote(uint256 indexed originChainId, address indexed originForwarder);

  modifier setMantleAdapter(
    address crossChainController,
    address ovmCrossDomainMessenger,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId
  ) {
    vm.assume(crossChainController != tx.origin);
    vm.assume(baseGasLimit < 10_000_000);
    _assumeSafeAddress(crossChainController);
    _assumeSafeAddress(ovmCrossDomainMessenger);
    vm.assume(originForwarder != address(0));
    vm.assume(originChainId > 0);

    IBaseAdapter.TrustedRemotesConfig memory originConfig = IBaseAdapter.TrustedRemotesConfig({
      originForwarder: originForwarder,
      originChainId: originChainId
    });
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](1);
    originConfigs[0] = originConfig;

    mantleAdapter = new MantleAdapter(
      IMantleAdapter.MantleParams({
        crossChainController: crossChainController,
        ovmCrossDomainMessenger: ovmCrossDomainMessenger,
        providerGasLimit: baseGasLimit,
        trustedRemotes: originConfigs
      })
    );
    _;
  }

  struct Params {
    address ovmCrossDomainMessenger;
    address receiver;
    uint256 dstGasLimit;
    address caller;
  }

  function setUp() public {}

  function testInitialize(
    address crossChainController,
    address ovmCrossDomainMessenger,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId
  )
    public
    setMantleAdapter(
      crossChainController,
      ovmCrossDomainMessenger,
      originForwarder,
      baseGasLimit,
      originChainId
    )
  {
    assertEq(mantleAdapter.getTrustedRemoteByChainId(originChainId), originForwarder);
  }

  function testForwardMessage(
    address crossChainController,
    address ovmCrossDomainMessenger,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId
  )
    public
    setMantleAdapter(
      crossChainController,
      ovmCrossDomainMessenger,
      originForwarder,
      baseGasLimit,
      originChainId
    )
  {
    _testForwardMessage(
      Params({
        ovmCrossDomainMessenger: ovmCrossDomainMessenger,
        receiver: address(135961),
        dstGasLimit: 12,
        caller: address(12354)
      })
    );
  }

  function testForwardMessageWhenChainNotSupported(
    address crossChainController,
    address ovmCrossDomainMessenger,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId,
    uint256 dstGasLimit,
    address receiver,
    bytes memory message
  )
    public
    setMantleAdapter(
      crossChainController,
      ovmCrossDomainMessenger,
      originForwarder,
      baseGasLimit,
      originChainId
    )
  {
    vm.assume(receiver != address(0));

    vm.expectRevert(bytes(Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED));
    mantleAdapter.forwardMessage(receiver, dstGasLimit, 11, message);
  }

  function testForwardMessageWhenWrongReceiver(
    address crossChainController,
    address ovmCrossDomainMessenger,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId,
    uint256 dstGasLimit,
    bytes memory message
  )
    public
    setMantleAdapter(
      crossChainController,
      ovmCrossDomainMessenger,
      originForwarder,
      baseGasLimit,
      originChainId
    )
  {
    vm.expectRevert(bytes(Errors.RECEIVER_NOT_SET));
    mantleAdapter.forwardMessage(address(0), dstGasLimit, ChainIds.MANTLE, message);
  }

  function testReceive(
    address crossChainController,
    address ovmCrossDomainMessenger,
    address originForwarder,
    uint256 baseGasLimit,
    bytes memory message
  )
    public
    setMantleAdapter(
      crossChainController,
      ovmCrossDomainMessenger,
      originForwarder,
      baseGasLimit,
      1
    )
  {
    hoax(ovmCrossDomainMessenger);

    vm.mockCall(
      crossChainController,
      abi.encodeWithSelector(ICrossChainReceiver.receiveCrossChainMessage.selector),
      abi.encode()
    );
    vm.expectCall(
      crossChainController,
      0,
      abi.encodeWithSelector(ICrossChainReceiver.receiveCrossChainMessage.selector, message, 1)
    );
    vm.mockCall(
      ovmCrossDomainMessenger,
      abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
      abi.encode(originForwarder)
    );
    mantleAdapter.ovmReceive(message);
  }

  function testReceiveWhenRemoteNotTrusted(
    address crossChainController,
    address ovmCrossDomainMessenger,
    address originForwarder,
    uint256 baseGasLimit,
    bytes memory message,
    address remote
  )
    public
    setMantleAdapter(
      crossChainController,
      ovmCrossDomainMessenger,
      originForwarder,
      baseGasLimit,
      1
    )
  {
    vm.assume(remote != originForwarder);
    hoax(ovmCrossDomainMessenger);

    vm.mockCall(
      ovmCrossDomainMessenger,
      abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
      abi.encode(remote)
    );
    vm.expectRevert(bytes(Errors.REMOTE_NOT_TRUSTED));

    mantleAdapter.ovmReceive(message);
  }

  function testReceiveWhenIncorrectOriginChainId(
    address crossChainController,
    address ovmCrossDomainMessenger,
    address originForwarder,
    uint256 baseGasLimit,
    bytes memory message,
    uint256 originChainId
  )
    public
    setMantleAdapter(
      crossChainController,
      ovmCrossDomainMessenger,
      originForwarder,
      baseGasLimit,
      originChainId
    )
  {
    vm.assume(originChainId != 1);
    hoax(ovmCrossDomainMessenger);

    vm.mockCall(
      ovmCrossDomainMessenger,
      abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
      abi.encode(originForwarder)
    );
    vm.expectRevert(bytes(Errors.REMOTE_NOT_TRUSTED));

    mantleAdapter.ovmReceive(message);
  }

  function _testForwardMessage(Params memory params) internal {
    bytes memory message = abi.encode('test message');

    hoax(params.caller, 10 ether);

    vm.mockCall(
      params.ovmCrossDomainMessenger,
      abi.encodeWithSelector(ICrossDomainMessenger.sendMessage.selector),
      abi.encode()
    );
    (bool success, bytes memory returnData) = address(mantleAdapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        params.receiver,
        params.dstGasLimit,
        ChainIds.MANTLE,
        message
      )
    );
    vm.clearMockedCalls();

    assertEq(success, true);
    assertEq(returnData, abi.encode(params.ovmCrossDomainMessenger, 0));
  }
}
