// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {InkAdapter, IBaseAdapter, InkAdapterArgs as InkAdapterArgsType} from '../../src/contracts/adapters/ink/InkAdapter.sol';
import './BaseAdapterScript.sol';

library InkAdapterDeploymentHelper {
  struct InkAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(InkAdapterArgs memory inkArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = type(InkAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          InkAdapterArgsType({
            crossChainController: inkArgs.baseArgs.crossChainController,
            ovmCrossDomainMessenger: inkArgs.ovm,
            providerGasLimit: inkArgs.baseArgs.providerGasLimit,
            trustedRemotes: inkArgs.baseArgs.trustedRemotes
          })
        )
      );
  }
}

abstract contract BaseInkAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM address');

    return
      InkAdapterDeploymentHelper.getAdapterCode(
        InkAdapterDeploymentHelper.InkAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
