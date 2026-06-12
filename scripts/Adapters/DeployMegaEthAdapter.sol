// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {
  MegaEthAdapter,
  IBaseAdapter,
  MegaEthAdapterArgs as MegaEthAdapterArgsType
} from '../../src/contracts/adapters/megaEth/MegaEthAdapter.sol';
import './BaseAdapterScript.sol';

library MegaEthAdapterDeploymentHelper {
  struct MegaEthAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(
    MegaEthAdapterArgs memory megaEthArgs
  ) internal pure returns (bytes memory) {
    bytes memory creationCode = type(MegaEthAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          MegaEthAdapterArgsType({
            crossChainController: megaEthArgs.baseArgs.crossChainController,
            ovmCrossDomainMessenger: megaEthArgs.ovm,
            providerGasLimit: megaEthArgs.baseArgs.providerGasLimit,
            trustedRemotes: megaEthArgs.baseArgs.trustedRemotes
          })
        )
      );
  }
}

abstract contract BaseMegaEthAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM address');

    return
      MegaEthAdapterDeploymentHelper.getAdapterCode(
        MegaEthAdapterDeploymentHelper.MegaEthAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
