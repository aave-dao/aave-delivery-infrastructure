// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';

import {CrossChainForwarder, ICrossChainForwarder} from '../../src/contracts/CrossChainForwarder.sol';
import {IBaseAdapter} from '../../src/contracts/adapters/IBaseAdapter.sol';
import {LayerZeroAdapter} from '../../src/contracts/adapters/layerZero/LayerZeroAdapter.sol';
import {ILayerZeroEndpointV2Extra} from '../interfaces/ILayerZeroEndpointV2Extra.sol';
import {CCCOwnerStub} from '../mocks/CCCOwnerStub.sol';

/// @dev Fork-based integration tests against the real LayerZero V2 endpoint on Ethereum mainnet.
///      Skipped when `RPC_MAINNET` is not configured.
contract LayerZeroAdapterForkTest is Test {
  address internal constant LZ_ENDPOINT_V2_MAINNET = 0x1a44076050125825900e736c501f859c50fE728c;
  uint32 internal constant POLYGON_EID = 30109;

  address internal constant OWNER = address(uint160(uint256(keccak256('LZ_FORK_OWNER'))));
  address internal constant ORIGIN_FORWARDER =
    address(uint160(uint256(keccak256('LZ_FORK_ORIGIN'))));
  address internal constant DELEGATE_A = address(uint160(uint256(keccak256('LZ_FORK_DELEGATE_A'))));
  address internal constant DELEGATE_B = address(uint160(uint256(keccak256('LZ_FORK_DELEGATE_B'))));

  bytes4 internal constant LZ_UNAUTHORIZED_SELECTOR = bytes4(keccak256('LZ_Unauthorized()'));

  CCCOwnerStub internal ccc;
  LayerZeroAdapter internal adapter;
  ILayerZeroEndpointV2Extra internal endpoint;
  address internal registeredSendLib;

  function setUp() public {
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(rpc);

    endpoint = ILayerZeroEndpointV2Extra(LZ_ENDPOINT_V2_MAINNET);
    registeredSendLib = endpoint.defaultSendLibrary(POLYGON_EID);
    ccc = new CCCOwnerStub(OWNER);

    IBaseAdapter.TrustedRemotesConfig[] memory trusted = new IBaseAdapter.TrustedRemotesConfig[](1);
    trusted[0] = IBaseAdapter.TrustedRemotesConfig({
      originForwarder: ORIGIN_FORWARDER,
      originChainId: 137
    });

    adapter = new LayerZeroAdapter(address(ccc), LZ_ENDPOINT_V2_MAINNET, 0, trusted);
  }

  function testFork_AdapterDelegateCanModifyOAppConfig() public {
    hoax(OWNER);
    adapter.config(0, abi.encode(DELEGATE_A));

    assertEq(endpoint.delegates(address(adapter)), DELEGATE_A);

    hoax(DELEGATE_A);
    endpoint.setSendLibrary(address(adapter), POLYGON_EID, registeredSendLib);
  }

  function testFork_OldDelegateCannotAfterRotation() public {
    hoax(OWNER);
    adapter.config(0, abi.encode(DELEGATE_A));
    assertEq(endpoint.delegates(address(adapter)), DELEGATE_A);

    hoax(OWNER);
    adapter.config(0, abi.encode(DELEGATE_B));
    assertEq(endpoint.delegates(address(adapter)), DELEGATE_B);

    hoax(DELEGATE_A);
    try endpoint.setSendLibrary(address(adapter), POLYGON_EID, registeredSendLib) {
      revert('expected revert for rotated-out delegate');
    } catch (bytes memory reason) {
      assertTrue(_isUnauthorizedError(reason), 'old delegate must hit the LZ unauthorized check');
    }

    hoax(DELEGATE_B);
    endpoint.setSendLibrary(address(adapter), POLYGON_EID, registeredSendLib);
  }

  function testFork_CCCDelegatePathViaForwarder() public {
    CrossChainForwarder forwarder = new CrossChainForwarder(
      new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
      new address[](0),
      new ICrossChainForwarder.OptimalBandwidthByChain[](0)
    );
    Ownable(address(forwarder)).transferOwnership(OWNER);

    CCCOwnerStub forwarderCcc = new CCCOwnerStub(OWNER);
    IBaseAdapter.TrustedRemotesConfig[] memory trusted = new IBaseAdapter.TrustedRemotesConfig[](1);
    trusted[0] = IBaseAdapter.TrustedRemotesConfig({
      originForwarder: ORIGIN_FORWARDER,
      originChainId: 137
    });
    LayerZeroAdapter forwarderAdapter = new LayerZeroAdapter(
      address(forwarderCcc),
      LZ_ENDPOINT_V2_MAINNET,
      0,
      trusted
    );

    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory toEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](1);
    toEnable[0] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(forwarderAdapter),
      destinationBridgeAdapter: address(0xBEEF),
      destinationChainId: 137
    });
    hoax(OWNER);
    forwarder.enableBridgeAdapters(toEnable);

    ICrossChainForwarder.BridgeAdapterConfig[]
      memory configs = new ICrossChainForwarder.BridgeAdapterConfig[](1);
    configs[0] = ICrossChainForwarder.BridgeAdapterConfig({
      destinationChainId: 137,
      bridgeAdapter: address(forwarderAdapter),
      data: abi.encode(DELEGATE_A)
    });

    hoax(OWNER);
    forwarder.configBridgeAdapters(configs);

    assertEq(endpoint.delegates(address(forwarder)), DELEGATE_A);
    assertEq(endpoint.delegates(address(forwarderAdapter)), address(0));

    hoax(DELEGATE_A);
    endpoint.setSendLibrary(address(forwarder), POLYGON_EID, registeredSendLib);

    configs[0].data = abi.encode(DELEGATE_B);
    hoax(OWNER);
    forwarder.configBridgeAdapters(configs);
    assertEq(endpoint.delegates(address(forwarder)), DELEGATE_B);

    hoax(DELEGATE_A);
    try endpoint.setSendLibrary(address(forwarder), POLYGON_EID, registeredSendLib) {
      revert('expected revert for rotated-out delegate');
    } catch (bytes memory reason) {
      assertTrue(_isUnauthorizedError(reason), 'old delegate must hit the LZ unauthorized check');
    }
  }

  function _isUnauthorizedError(bytes memory reason) internal pure returns (bool) {
    if (reason.length < 4) return false;
    bytes4 selector;
    assembly {
      selector := mload(add(reason, 32))
    }
    return selector == LZ_UNAUTHORIZED_SELECTOR;
  }
}
