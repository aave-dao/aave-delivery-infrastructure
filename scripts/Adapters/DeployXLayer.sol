// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {XLayerAdapter, IBaseAdapter, XLayerAdapterArgs as XLayerAdapterArgsType} from '../../src/contracts/adapters/xLayer/xLayerAdapter.sol';
import './BaseAdapterScript.sol';

library XLayerAdapterDeploymentHelper {
  struct XLayerAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(
    XLayerAdapterArgs memory xLayerArgs
  ) internal pure returns (bytes memory) {
    bytes memory creationCode = type(XLayerAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          XLayerAdapterArgsType({
            crossChainController: xLayerArgs.baseArgs.crossChainController,
            ovmCrossDomainMessenger: xLayerArgs.ovm,
            providerGasLimit: xLayerArgs.baseArgs.providerGasLimit,
            trustedRemotes: xLayerArgs.baseArgs.trustedRemotes
          })
        )
      );
  }
}

abstract contract BaseXLayerAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM address');

    return
      XLayerAdapterDeploymentHelper.getAdapterCode(
        XLayerAdapterDeploymentHelper.XLayerAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
