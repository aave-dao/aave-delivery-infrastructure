// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {SoneiumAdapter, IBaseAdapter, SoneiumAdapterArgs as SoneiumAdapterArgsType} from '../../src/contracts/adapters/soneium/soneiumAdapter.sol';
import './BaseAdapterScript.sol';

library SoneiumAdapterDeploymentHelper {
  struct SoneiumAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(
    SoneiumAdapterArgs memory soneiumArgs
  ) internal pure returns (bytes memory) {
    bytes memory creationCode = type(SoneiumAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          SoneiumAdapterArgsType({
            crossChainController: soneiumArgs.baseArgs.crossChainController,
            ovmCrossDomainMessenger: soneiumArgs.ovm,
            providerGasLimit: soneiumArgs.baseArgs.providerGasLimit,
            trustedRemotes: soneiumArgs.baseArgs.trustedRemotes
          })
        )
      );
  }
}

abstract contract BaseSoneiumAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM address');

    return
      SoneiumAdapterDeploymentHelper.getAdapterCode(
        SoneiumAdapterDeploymentHelper.SoneiumAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
