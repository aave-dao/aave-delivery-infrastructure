// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {CCIPAdapter, IRouterClient, Client, IBaseAdapter} from '../../src/contracts/adapters/ccip/CCIPAdapter.sol';
import {ICCIPAdapter} from '../../src/contracts/adapters/ccip/ICCIPAdapter.sol';
import {ICrossChainReceiver} from '../../src/contracts/interfaces/ICrossChainReceiver.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../../src/contracts/libs/Errors.sol';
import {ERC20, IERC20} from '../mocks/ERC20.sol';

contract CCIPAdapterTest is Test {
  address public constant ORIGIN_FORWARDER = address(123);
  address public constant CROSS_CHAIN_CONTROLLER = address(1234);
  address public constant CCIP_ROUTER = address(12345);
  address public constant RECEIVER_CROSS_CHAIN_CONTROLLER = address(1234567);
  address public constant ADDRESS_WITH_ETH = address(12301234);

  uint256 public constant ORIGIN_CCIP_CHAIN_ID = ChainIds.ETHEREUM;

  uint256 public constant BASE_GAS_LIMIT = 10_000;

  IERC20 public LINK_TOKEN;

  IBaseAdapter.TrustedRemotesConfig internal originConfig =
    IBaseAdapter.TrustedRemotesConfig({
      originForwarder: ORIGIN_FORWARDER,
      originChainId: ORIGIN_CCIP_CHAIN_ID
    });

  CCIPAdapter internal ccipAdapter;

  event SetTrustedRemote(uint256 indexed originChainId, address indexed originForwarder);

  function setUp() public {
    IBaseAdapter.TrustedRemotesConfig[]
      memory originConfigs = new IBaseAdapter.TrustedRemotesConfig[](1);
    originConfigs[0] = originConfig;
    LINK_TOKEN = new ERC20('LINK', 'Mock LINK token');

    ccipAdapter = new CCIPAdapter(
      CROSS_CHAIN_CONTROLLER,
      CCIP_ROUTER,
      BASE_GAS_LIMIT,
      originConfigs,
      address(LINK_TOKEN)
    );
    deal(address(LINK_TOKEN), address(this), 100000 ether);
  }

  function testInitialize() public {
    assertEq(
      keccak256(abi.encode(ccipAdapter.adapterName())),
      keccak256(abi.encode('CCIP adapter'))
    );
    assertEq(ccipAdapter.getTrustedRemoteByChainId(ORIGIN_CCIP_CHAIN_ID), ORIGIN_FORWARDER);
  }

  function testGetInfraChainFromBridgeChain() public {
    assertEq(ccipAdapter.nativeToInfraChainId(uint64(4051577828743386545)), ChainIds.POLYGON);
  }

  function testGetBridgeChainFromInfraChain() public {
    assertEq(ccipAdapter.infraToNativeChainId(ChainIds.POLYGON), uint64(4051577828743386545));
  }

  function testForwardMessage() public {
    uint40 payloadId = uint40(0);
    bytes memory message = abi.encode(payloadId, CROSS_CHAIN_CONTROLLER);
    uint256 dstGasLimit = 600000;
    bytes32 messageId = keccak256(abi.encode(1));

    hoax(ADDRESS_WITH_ETH, 10 ether);
    vm.mockCall(
      CCIP_ROUTER,
      abi.encodeWithSelector(IRouterClient.isChainSupported.selector),
      abi.encode(true)
    );
    vm.mockCall(CCIP_ROUTER, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(10));
    vm.mockCall(
      CCIP_ROUTER,
      0,
      abi.encodeWithSelector(IRouterClient.ccipSend.selector),
      abi.encode(messageId)
    );
    (bool success, bytes memory returnData) = address(ccipAdapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        RECEIVER_CROSS_CHAIN_CONTROLLER,
        dstGasLimit,
        ChainIds.POLYGON,
        message
      )
    );
    vm.clearMockedCalls();

    assertEq(success, true);
    assertEq(returnData, abi.encode(CCIP_ROUTER, messageId));
  }

  function testForwardMessageWhenChainNotSupported() public {
    uint40 payloadId = uint40(0);
    bytes memory message = abi.encode(payloadId, CROSS_CHAIN_CONTROLLER);
    uint256 dstGasLimit = 600000;

    vm.mockCall(
      CCIP_ROUTER,
      abi.encodeWithSelector(IRouterClient.isChainSupported.selector),
      abi.encode(false)
    );
    vm.expectRevert(bytes(Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED));
    CCIPAdapter(address(ccipAdapter)).forwardMessage(
      RECEIVER_CROSS_CHAIN_CONTROLLER,
      dstGasLimit,
      10,
      message
    );
  }

  function testForwardMessageWithNoValue() public {
    uint40 payloadId = uint40(0);
    bytes memory payload = abi.encode(payloadId, CROSS_CHAIN_CONTROLLER);

    // Set LINK balance to 0 so the adapter cannot pay fees
    deal(address(LINK_TOKEN), address(this), 0);

    vm.mockCall(
      CCIP_ROUTER,
      abi.encodeWithSelector(IRouterClient.isChainSupported.selector),
      abi.encode(true)
    );
    vm.mockCall(CCIP_ROUTER, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(10));
    (bool success, bytes memory returnData) = address(ccipAdapter).delegatecall(
      abi.encodeWithSelector(
        IBaseAdapter.forwardMessage.selector,
        RECEIVER_CROSS_CHAIN_CONTROLLER,
        0,
        ChainIds.POLYGON,
        payload
      )
    );
    assertEq(success, false);
    assertEq(returnData, abi.encodeWithSignature("Error(string)", Errors.NOT_ENOUGH_VALUE_TO_PAY_BRIDGE_FEES));
  }

  function testForwardMessageWhenWrongReceiver() public {
    uint40 payloadId = uint40(0);
    bytes memory message = abi.encode(payloadId, CROSS_CHAIN_CONTROLLER);
    uint256 dstGasLimit = 600000;

    vm.mockCall(
      CCIP_ROUTER,
      abi.encodeWithSelector(IRouterClient.isChainSupported.selector),
      abi.encode(true)
    );
    vm.expectRevert(bytes(Errors.RECEIVER_NOT_SET));
    CCIPAdapter(address(ccipAdapter)).forwardMessage(
      address(0),
      dstGasLimit,
      ChainIds.POLYGON,
      message
    );
  }

  function testCCIPReceive() public {
    uint64 originChain = uint64(1);
    bytes memory message = abi.encode('some message');
    bytes32 messageId = keccak256(abi.encode(1));

    Client.Any2EVMMessage memory payload = Client.Any2EVMMessage({
      messageId: messageId,
      sourceChainSelector: originChain,
      sender: abi.encode(ORIGIN_FORWARDER),
      data: message,
      tokenAmounts: new Client.EVMTokenAmount[](0)
    });

    hoax(CCIP_ROUTER);
    vm.mockCall(
      CROSS_CHAIN_CONTROLLER,
      abi.encodeWithSelector(ICrossChainReceiver.receiveCrossChainMessage.selector),
      abi.encode()
    );
    vm.expectCall(
      CROSS_CHAIN_CONTROLLER,
      0,
      abi.encodeWithSelector(ICrossChainReceiver.receiveCrossChainMessage.selector, message, 1)
    );
    CCIPAdapter(address(ccipAdapter)).ccipReceive(payload);
  }

  function testCCIPReceiveWhenCallerNotRouter(uint32 originChain) public {
    bytes memory message = abi.encode('some message');
    bytes32 messageId = keccak256(abi.encode(1));

    Client.Any2EVMMessage memory payload = Client.Any2EVMMessage({
      messageId: messageId,
      sourceChainSelector: originChain,
      sender: abi.encode(ORIGIN_FORWARDER),
      data: message,
      tokenAmounts: new Client.EVMTokenAmount[](0)
    });

    vm.expectRevert(bytes(Errors.CALLER_NOT_CCIP_ROUTER));

    CCIPAdapter(address(ccipAdapter)).ccipReceive(payload);
  }

  function testCCIPReceiveWhenRemoteNotTrusted(uint32 originChain) public {
    bytes memory message = abi.encode('some message');
    bytes32 messageId = keccak256(abi.encode(1));

    Client.Any2EVMMessage memory payload = Client.Any2EVMMessage({
      messageId: messageId,
      sourceChainSelector: originChain,
      sender: abi.encode(address(410298289)),
      data: message,
      tokenAmounts: new Client.EVMTokenAmount[](0)
    });

    hoax(CCIP_ROUTER);
    vm.expectRevert(bytes(Errors.REMOTE_NOT_TRUSTED));

    CCIPAdapter(address(ccipAdapter)).ccipReceive(payload);
  }
}
