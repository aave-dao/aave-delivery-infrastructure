// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {CrossChainControllerWithEmergencyMode} from '../CrossChainControllerWithEmergencyMode.sol';
import {ILayerZeroEndpointV2} from '../adapters/layerZero/interfaces/ILayerZeroEndpointV2.sol';

contract LayerZeroCrossChainControllerWithEmergencyMode is CrossChainControllerWithEmergencyMode {
  constructor(address clEmergencyOracle)
    CrossChainControllerWithEmergencyMode(clEmergencyOracle)
  {
  }

  function initialize(
    address owner,
    address guardian,
    address clEmergencyOracle,
    ConfirmationInput[] memory initialRequiredConfirmations,
    ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToAllow,
    ForwarderBridgeAdapterConfigInput[] memory forwarderBridgeAdaptersToEnable,
    address[] memory sendersToApprove,
    OptimalBandwidthByChain[] memory optimalBandwidthByChain,
    address lzEndpoint,
    address delegate
  ) external initializer {
    _updateCLEmergencyOracle(clEmergencyOracle);
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
