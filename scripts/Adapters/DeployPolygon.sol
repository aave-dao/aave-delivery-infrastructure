// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './BaseAdapterScript.sol';
import {PolygonAdapterEthereum} from '../../src/contracts/adapters/polygon/PolygonAdapterEthereum.sol';
import {PolygonAdapterPolygon} from '../../src/contracts/adapters/polygon/PolygonAdapterPolygon.sol';

library PolygonAdapterDeploymentHelper {
  struct PolygonAdapterArgs {
    BaseAdapterArgs baseArgs;
    address fxTunnel;
  }

  function getAdapterCode(
    PolygonAdapterArgs memory polArgs,
    uint256 chainId
  ) internal pure returns (bytes memory) {
    bytes memory creationCode;
    // For now we dont have polygon testnets as we only have goerli implemented which should no longer be suported
    if (chainId == ChainIds.ETHEREUM) {
      creationCode = type(PolygonAdapterEthereum).creationCode;
    } else if (chainId == ChainIds.POLYGON) {
      creationCode = type(PolygonAdapterPolygon).creationCode;
    } else {
      revert('wrong chain id');
    }

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          polArgs.baseArgs.crossChainController,
          polArgs.fxTunnel,
          polArgs.baseArgs.providerGasLimit,
          polArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BasePolygonAdapter is BaseAdapterScript {
  function FX_TUNNEL() internal pure virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(FX_TUNNEL() != address(0), 'Invalid fx tunnel');

    return
      PolygonAdapterDeploymentHelper.getAdapterCode(
        PolygonAdapterDeploymentHelper.PolygonAdapterArgs({
          baseArgs: baseArgs,
          fxTunnel: FX_TUNNEL()
        }),
        TRANSACTION_NETWORK()
      );
  }
}
