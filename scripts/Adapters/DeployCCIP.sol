// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {CCIPAdapter, ICCIPAdapter, IBaseAdapter} from '../../src/contracts/adapters/ccip/CCIPAdapter.sol';
import './BaseAdapterScript.sol';
import {CCIPAdapterTestnet} from '../contract_extensions/CCIPAdapter.sol';

library CCIPAdapterDeploymentHelper {
  struct CCIPAdapterArgs {
    BaseAdapterArgs baseArgs;
    address ccipRouter;
    address linkToken;
  }

  function getAdapterCode(CCIPAdapterArgs memory ccipArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = ccipArgs.baseArgs.isTestnet
      ? type(CCIPAdapterTestnet).creationCode
      : type(CCIPAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          ccipArgs.baseArgs.crossChainController,
          ccipArgs.ccipRouter,
          ccipArgs.baseArgs.providerGasLimit,
          ccipArgs.baseArgs.trustedRemotes,
          ccipArgs.linkToken
        )
      );
  }
}

// configs can be found here: https://docs.chain.link/ccip/supported-networks/v1_2_0/mainnet#bnb-mainnet
abstract contract BaseCCIPAdapter is BaseAdapterScript {
  function CCIP_ROUTER() internal view virtual returns (address);

  function LINK_TOKEN() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(CCIP_ROUTER() != address(0), 'Invalid CCIP Router');
    require(LINK_TOKEN() != address(0), 'Invalid Link Token');

    return
      CCIPAdapterDeploymentHelper.getAdapterCode(
        CCIPAdapterDeploymentHelper.CCIPAdapterArgs({
          baseArgs: baseArgs,
          ccipRouter: CCIP_ROUTER(),
          linkToken: LINK_TOKEN()
        })
      );
  }
}
