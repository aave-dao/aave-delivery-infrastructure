// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {MantleAdapter, IMantleAdapter} from '../../src/contracts/adapters/mantle/MantleAdapter.sol';
import './BaseAdapterScript.sol';
import {MantleAdapterTestnet} from '../contract_extensions/MantleAdapter.sol';

library MantleAdapterDeploymentHelper {
  struct MantleAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(MantleAdapterArgs memory mantleArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = mantleArgs.baseArgs.isTestnet
      ? type(MantleAdapterTestnet).creationCode
      : type(MantleAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          IMantleAdapter.MantleParams({
            crossChainController: mantleArgs.baseArgs.crossChainController,
            ovmCrossDomainMessenger: mantleArgs.ovm,
            providerGasLimit: mantleArgs.baseArgs.providerGasLimit,
            trustedRemotes: mantleArgs.baseArgs.trustedRemotes
          })
        )
      );
  }
}

abstract contract BaseMantleAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM address');

    return
      MantleAdapterDeploymentHelper.getAdapterCode(
        MantleAdapterDeploymentHelper.MantleAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
