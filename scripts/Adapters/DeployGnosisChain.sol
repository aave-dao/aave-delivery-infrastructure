// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './BaseAdapterScript.sol';
import {GnosisChainAdapter} from '../../src/contracts/adapters/gnosisChain/GnosisChainAdapter.sol';
import {BaseAdapterScript, IBaseAdapter} from './BaseAdapterScript.sol';

library GnosisAdapterDeploymentHelper {
  struct GnosisAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ambBridge;
  }

  function getAdapterCode(
    GnosisAdapterArgs memory gnosisArgs
  ) internal pure returns (bytes memory) {
    bytes memory creationCode = type(GnosisChainAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          gnosisArgs.baseArgs.crossChainController,
          gnosisArgs.ambBridge,
          gnosisArgs.baseArgs.providerGasLimit,
          gnosisArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseGnosisChainAdapter is BaseAdapterScript {
  function GNOSIS_AMB_BRIDGE() internal pure virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(GNOSIS_AMB_BRIDGE() != address(0), 'Invalid AMB BRIDGE Router');

    return
      GnosisAdapterDeploymentHelper.getAdapterCode(
        GnosisAdapterDeploymentHelper.GnosisAdapterArgs({
          baseArgs: baseArgs,
          ambBridge: GNOSIS_AMB_BRIDGE()
        })
      );
  }
}
