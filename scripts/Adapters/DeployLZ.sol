// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {LayerZeroAdapter, ILayerZeroAdapter, IBaseAdapter} from '../../src/contracts/adapters/layerZero/LayerZeroAdapter.sol';
import {LayerZeroAdapterTestnet} from '../contract_extensions/LayerZeroAdapter.sol';
import './BaseAdapterScript.sol';

library LZAdapterDeploymentHelper {
  struct LZAdapterArgs {
    BaseAdapterArgs baseArgs;
    address lzEndpoint;
  }

  function getAdapterCode(LZAdapterArgs memory lzArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = lzArgs.baseArgs.isTestnet
      ? type(LayerZeroAdapterTestnet).creationCode
      : type(LayerZeroAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          lzArgs.baseArgs.crossChainController,
          lzArgs.lzEndpoint,
          lzArgs.baseArgs.providerGasLimit,
          lzArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseLZAdapter is BaseAdapterScript {
  function LZ_ENDPOINT() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(LZ_ENDPOINT() != address(0), 'Invalid LZ Endpoint');

    return
      LZAdapterDeploymentHelper.getAdapterCode(
        LZAdapterDeploymentHelper.LZAdapterArgs({baseArgs: baseArgs, lzEndpoint: LZ_ENDPOINT()})
      );
  }
}
