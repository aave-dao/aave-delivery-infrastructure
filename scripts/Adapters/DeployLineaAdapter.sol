// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './BaseAdapterScript.sol';
import {LineaAdapter, ILineaAdapter} from '../../src/contracts/adapters/linea/LineaAdapter.sol';
import {LineaAdapterTestnet} from '../contract_extensions/LineaAdapter.sol';

library LineaAdapterDeploymentHelper {
  struct LineaAdapterArgs {
    BaseAdapterArgs baseArgs;
    address lineaMessageService;
  }

  function getAdapterCode(LineaAdapterArgs memory lineaArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = lineaArgs.baseArgs.isTestnet
      ? type(LineaAdapterTestnet).creationCode
      : type(LineaAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          ILineaAdapter.LineaParams({
            crossChainController: lineaArgs.baseArgs.crossChainController,
            lineaMessageService: lineaArgs.lineaMessageService,
            providerGasLimit: lineaArgs.baseArgs.providerGasLimit,
            trustedRemotes: lineaArgs.baseArgs.trustedRemotes
          })
        )
      );
  }
}

abstract contract BaseDeployLineaAdapter is BaseAdapterScript {
  function LINEA_MESSAGE_SERVICE() internal view virtual returns (address) {
    return address(0);
  }

  function PROVIDER_GAS_LIMIT() internal view virtual override returns (uint256) {
    return 150_000;
  }

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(baseArgs.trustedRemotes.length == 1, 'Linea adapter can only have one remote');
    require(LINEA_MESSAGE_SERVICE() != address(0), 'Linea message service can not be 0');

    return
      LineaAdapterDeploymentHelper.getAdapterCode(
        LineaAdapterDeploymentHelper.LineaAdapterArgs({
          baseArgs: baseArgs,
          lineaMessageService: LINEA_MESSAGE_SERVICE()
        })
      );
  }
}
