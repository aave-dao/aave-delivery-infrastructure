// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {CBaseAdapter, IBaseAdapter} from '../../src/contracts/adapters/cBase/CBaseAdapter.sol';
import './BaseAdapterScript.sol';
import {CBaseAdapterTestnet} from '../contract_extensions/CBAdapter.sol';

library CBAdapterDeploymentHelper {
  struct CBAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(CBAdapterArgs memory cbArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = cbArgs.baseArgs.isTestnet
      ? type(CBaseAdapterTestnet).creationCode
      : type(CBaseAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          cbArgs.baseArgs.crossChainController,
          cbArgs.ovm,
          cbArgs.baseArgs.providerGasLimit,
          cbArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseCBAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM address');
    require(baseArgs.trustedRemotes.length == 1, 'Adapter can only have one remote');

    return
      CBAdapterDeploymentHelper.getAdapterCode(
        CBAdapterDeploymentHelper.CBAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
