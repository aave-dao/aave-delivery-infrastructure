// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {LayerZeroAdapter, Origin, ILayerZeroEndpointV2, MessagingFee, MessagingReceipt} from '../../src/contracts/adapters/layerZero/LayerZeroAdapter.sol';
import {ICrossChainReceiver} from '../../src/contracts/interfaces/ICrossChainReceiver.sol';
import {IBaseAdapter} from '../../src/contracts/adapters/IBaseAdapter.sol';
import {ILayerZeroAdapter} from '../../src/contracts/adapters/layerZero/ILayerZeroAdapter.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../../src/contracts/libs/Errors.sol';
import {BaseAdapterTest} from './BaseAdapterTest.sol';
import {IERC5313} from 'openzeppelin-contracts/contracts/interfaces/IERC5313.sol';

contract LayerZeroAdapterTest is BaseAdapterTest {
  LayerZeroAdapter layerZeroAdapter;

  modifier setLZAdapter(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId
  ) {
    vm.assume(crossChainController != tx.origin); // zkVM doesn't support mocking tx.origin
    vm.assume(baseGasLimit < 1 ether);
    _assumeSafeAddress(crossChainController);
    _assumeSafeAddress(lzEndpoint);
    vm.assume(originForwarder != address(0));
    vm.assume(originChainId > 0);

    IBaseAdapter.TrustedRemotesConfig memory originConfig = IBaseAdapter.TrustedRemotesConfig({
      originForwarder: originForwarder,
      originChainId: originChainId
    });
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](1);
    originConfigs[0] = originConfig;

    layerZeroAdapter = new LayerZeroAdapter(
      crossChainController,
      lzEndpoint,
      baseGasLimit,
      originConfigs
    );
    _;
  }

  function setUp() public {}

  function testWrongLZEndpoint(
    address crossChainController,
    uint256 baseGasLimit,
    address originForwarder,
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

    vm.expectRevert(bytes(Errors.INVALID_LZ_ENDPOINT));
    new LayerZeroAdapter(crossChainController, address(0), baseGasLimit, originConfigs);
  }

  function testInit(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, originChainId)
  {
    assertEq(
      keccak256(abi.encode(layerZeroAdapter.adapterName())),
      keccak256(abi.encode('LayerZero adapter'))
    );
    assertEq(originForwarder, layerZeroAdapter.getTrustedRemoteByChainId(originChainId));
    assertEq(address(layerZeroAdapter.LZ_ENDPOINT()), lzEndpoint);
  }

  function testGetInfraChainFromBridgeChain(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, originChainId)
  {
    assertEq(layerZeroAdapter.nativeToInfraChainId(30109), ChainIds.POLYGON);
  }

  function testGetBridgeChainFromInfraChain(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 originChainId
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, originChainId)
  {
    assertEq(layerZeroAdapter.infraToNativeChainId(ChainIds.POLYGON), 30109);
  }

  function testLzReceive(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    bytes memory payload = abi.encode('test message');

    Origin memory origin = Origin({
      srcEid: uint32(30101),
      sender: bytes32(uint256(uint160(originForwarder))),
      nonce: uint64(1)
    });

    hoax(lzEndpoint);
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
        payload,
        ChainIds.ETHEREUM
      )
    );
    layerZeroAdapter.lzReceive(origin, bytes32(0), payload, address(23), bytes(''));
    vm.clearMockedCalls();
  }

  function testLzReceiveWhenNotEndpoint(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    address caller
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    Origin memory origin = Origin({
      srcEid: uint32(30101),
      sender: bytes32(uint256(uint160(originForwarder))),
      nonce: uint64(1)
    });
    bytes memory payload = abi.encode('test message');

    vm.assume(caller != lzEndpoint);
    hoax(caller);
    vm.expectRevert(bytes(Errors.CALLER_NOT_LZ_ENDPOINT));
    layerZeroAdapter.lzReceive(origin, bytes32(0), payload, address(23), bytes(''));
  }

  function testLzReceiveWhenIncorrectSource(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    address srcAddress
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    vm.assume(srcAddress != originForwarder);

    Origin memory origin = Origin({
      srcEid: uint32(30101),
      sender: bytes32(uint256(uint160(srcAddress))),
      nonce: uint64(1)
    });
    bytes memory payload = abi.encode('test message');

    hoax(lzEndpoint);
    vm.expectRevert(bytes(Errors.REMOTE_NOT_TRUSTED));
    layerZeroAdapter.lzReceive(origin, bytes32(0), payload, address(23), bytes(''));
  }

  function testForwardPayload(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 dstGasLimit,
    address receiver,
    address caller
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    vm.assume(dstGasLimit < 1 ether);
    vm.assume(receiver != address(0));
    vm.assume(caller != address(0));

    _testForwardMessage(lzEndpoint, receiver, dstGasLimit, caller);
  }

  function testForwardPayloadWithNoValue(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 dstGasLimit,
    address receiver
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    vm.assume(dstGasLimit > 200000 && dstGasLimit < 1 ether);
    vm.assume(receiver != address(0));

    bytes memory payload = abi.encode('test message');

    vm.mockCall(
      lzEndpoint,
      abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
      abi.encode(MessagingFee({nativeFee: 10, lzTokenFee: 0}))
    );
    vm.expectRevert(bytes(Errors.NOT_ENOUGH_VALUE_TO_PAY_BRIDGE_FEES));
    (bool success, ) = address(layerZeroAdapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        receiver,
        dstGasLimit,
        ChainIds.POLYGON,
        payload
      )
    );
    assertEq(success, false);
  }

  function testForwardPayloadWhenNoChainSet(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 dstGasLimit,
    address receiver
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    vm.assume(receiver != address(0));
    vm.assume(dstGasLimit > 200000 && dstGasLimit < 1 ether);

    bytes memory message = abi.encode('test message');

    vm.expectRevert(bytes(Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED));
    layerZeroAdapter.forwardMessage(receiver, dstGasLimit, 102345, message);
  }

  function testForwardPayloadWhenNoReceiverSet(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    uint256 dstGasLimit
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    vm.assume(dstGasLimit > 200000 && dstGasLimit < 1 ether);

    bytes memory message = abi.encode('test message');

    vm.expectRevert(bytes(Errors.RECEIVER_NOT_SET));
    layerZeroAdapter.forwardMessage(address(0), dstGasLimit, ChainIds.POLYGON, message);
  }

  function _testForwardMessage(
    address lzEndpoint,
    address receiver,
    uint256 dstGasLimit,
    address caller
  ) internal {
    bytes memory payload = abi.encode('test message');

    hoax(caller, 10 ether);
    vm.mockCall(
      lzEndpoint,
      abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
      abi.encode(MessagingFee({nativeFee: 10, lzTokenFee: 0}))
    );
    vm.mockCall(
      lzEndpoint,
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
    (bool success, bytes memory returnData) = address(layerZeroAdapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        receiver,
        dstGasLimit,
        ChainIds.POLYGON,
        payload
      )
    );
    vm.clearMockedCalls();

    assertEq(success, true);
    assertEq(returnData, abi.encode(lzEndpoint, 2));
  }

  function testConfig(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    address cccOwner,
    address delegate
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    vm.assume(delegate != address(0));
    vm.assume(cccOwner != address(0));

    vm.mockCall(
      crossChainController,
      abi.encodeWithSelector(IERC5313.owner.selector),
      abi.encode(cccOwner)
    );
    vm.mockCall(
      lzEndpoint,
      abi.encodeWithSelector(ILayerZeroEndpointV2.setDelegate.selector),
      abi.encode()
    );

    hoax(cccOwner);
    vm.expectCall(lzEndpoint, abi.encodeCall(ILayerZeroEndpointV2.setDelegate, (delegate)));
    layerZeroAdapter.config(0, abi.encode(delegate));
    vm.clearMockedCalls();
  }

  function testConfigWhenNotCCCOwner(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    address cccOwner,
    address caller,
    address delegate
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    vm.assume(delegate != address(0));
    vm.assume(cccOwner != address(0));
    vm.assume(caller != cccOwner);

    vm.mockCall(
      crossChainController,
      abi.encodeWithSelector(IERC5313.owner.selector),
      abi.encode(cccOwner)
    );

    hoax(caller);
    vm.expectRevert(bytes(Errors.CALLER_NOT_CC_OWNER));
    layerZeroAdapter.config(0, abi.encode(delegate));
    vm.clearMockedCalls();
  }

  function testConfigWhenDelegateZero(
    address crossChainController,
    address lzEndpoint,
    address originForwarder,
    uint256 baseGasLimit,
    address cccOwner
  )
    public
    setLZAdapter(crossChainController, lzEndpoint, originForwarder, baseGasLimit, ChainIds.ETHEREUM)
  {
    vm.assume(cccOwner != address(0));

    vm.mockCall(
      crossChainController,
      abi.encodeWithSelector(IERC5313.owner.selector),
      abi.encode(cccOwner)
    );

    hoax(cccOwner);
    vm.expectRevert(bytes(Errors.INVALID_ADAPTER_CONFIG));
    layerZeroAdapter.config(0, abi.encode(address(0)));
    vm.clearMockedCalls();
  }
}
