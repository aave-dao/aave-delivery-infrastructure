// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;


import {CrossChainController} from '../CrossChainController.sol';
import {ILayerZeroEndpointV2} from '../adapters/layerZero/interfaces/ILayerZeroEndpointV2.sol';

contract LayerZeroCrossChainController is CrossChainController {
    function initialize(
    address owner,
    address guardian,
    ConfirmationInput[] memory initialRequiredConfirmations,
    ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToAllow,
    ForwarderBridgeAdapterConfigInput[] memory forwarderBridgeAdaptersToEnable,
    address[] memory sendersToApprove,
    OptimalBandwidthByChain[] memory optimalBandwidthByChain,
    address lzEndpoint,
    address delegate
  ) external initializer {
    _baseInitialize(
      owner,
      guardian,
      initialRequiredConfirmations,
      receiverBridgeAdaptersToAllow,
      forwarderBridgeAdaptersToEnable,
      sendersToApprove,
      optimalBandwidthByChain
    );
    ILayerZeroEndpointV2(lzEndpoint).setDelegate(delegate);
  }
}