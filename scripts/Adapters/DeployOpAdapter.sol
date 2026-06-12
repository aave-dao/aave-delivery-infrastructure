// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OpAdapter, IOpAdapter, IBaseAdapter} from '../../src/contracts/adapters/optimism/OpAdapter.sol';
import './BaseAdapterScript.sol';
import {OptimismAdapterTestnet} from '../contract_extensions/OptimismAdapter.sol';

library OpAdapterDeploymentHelper {
  struct OpAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(OpAdapterArgs memory opArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = opArgs.baseArgs.isTestnet
      ? type(OptimismAdapterTestnet).creationCode
      : type(OpAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          opArgs.baseArgs.crossChainController,
          opArgs.ovm,
          opArgs.baseArgs.providerGasLimit,
          opArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseOpAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM');

    return
      OpAdapterDeploymentHelper.getAdapterCode(
        OpAdapterDeploymentHelper.OpAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
