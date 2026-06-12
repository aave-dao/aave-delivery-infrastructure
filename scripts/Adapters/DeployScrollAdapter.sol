// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ScrollAdapter, IBaseAdapter} from '../../src/contracts/adapters/scroll/ScrollAdapter.sol';
import './BaseAdapterScript.sol';
import {ScrollAdapterTestnet} from '../contract_extensions/ScrollAdapter.sol';

library ScrollAdapterDeploymentHelper {
  struct ScrollAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ovm;
  }

  function getAdapterCode(
    ScrollAdapterArgs memory scrollArgs
  ) internal pure returns (bytes memory) {
    bytes memory creationCode = scrollArgs.baseArgs.isTestnet
      ? type(ScrollAdapterTestnet).creationCode
      : type(ScrollAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          scrollArgs.baseArgs.crossChainController,
          scrollArgs.ovm,
          scrollArgs.baseArgs.providerGasLimit,
          scrollArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseScrollAdapter is BaseAdapterScript {
  function OVM() internal view virtual returns (address);

  function PROVIDER_GAS_LIMIT() internal view virtual override returns (uint256) {
    return 150_000;
  }

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(OVM() != address(0), 'Invalid OVM');

    return
      ScrollAdapterDeploymentHelper.getAdapterCode(
        ScrollAdapterDeploymentHelper.ScrollAdapterArgs({baseArgs: baseArgs, ovm: OVM()})
      );
  }
}
