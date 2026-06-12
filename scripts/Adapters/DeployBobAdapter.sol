// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {BobAdapter, IBaseAdapter, BobAdapterArgs as BobAdapterArgsType} from '../../src/contracts/adapters/bob/BobAdapter.sol';
import './BaseAdapterScript.sol';

library BobAdapterDeploymentHelper {
  struct BobAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(BobAdapterArgs memory bobArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = type(BobAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          BobAdapterArgsType({
            crossChainController: bobArgs.baseArgs.crossChainController,
            ovmCrossDomainMessenger: bobArgs.ovm,
            providerGasLimit: bobArgs.baseArgs.providerGasLimit,
            trustedRemotes: bobArgs.baseArgs.trustedRemotes
          })
        )
      );
  }
}

abstract contract BaseBobAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM address');

    return
      BobAdapterDeploymentHelper.getAdapterCode(
        BobAdapterDeploymentHelper.BobAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
