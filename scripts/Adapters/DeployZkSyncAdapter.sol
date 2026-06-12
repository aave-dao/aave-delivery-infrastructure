// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './BaseAdapterScript.sol';
import {ZkSyncAdapter} from '../../src/contracts/adapters/zkSync/ZkSyncAdapter.sol';
import {ZkSyncAdapterTestnet} from '../contract_extensions/ZkSyncAdapterTestnet.sol';

library ZkSyncAdapterDeploymentHelper {
  struct ZkSyncAdapterArgs {
    BaseAdapterArgs baseArgs;
    address bridgeHub;
    address refundAddress;
  }

  function getAdapterCode(
    ZkSyncAdapterArgs memory zkSyncArgs
  ) internal pure returns (bytes memory) {
    bytes memory creationCode = zkSyncArgs.baseArgs.isTestnet
      ? type(ZkSyncAdapterTestnet).creationCode
      : type(ZkSyncAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          zkSyncArgs.baseArgs.crossChainController,
          zkSyncArgs.bridgeHub,
          zkSyncArgs.refundAddress,
          zkSyncArgs.baseArgs.providerGasLimit,
          zkSyncArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseZkSyncAdapter is BaseAdapterScript {
  function BRIDGE_HUB() internal view virtual returns (address);

  function REFUND_ADDRESS() internal view virtual returns (address) {
    return address(0);
  }

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(BRIDGE_HUB() != address(0), 'Invalid BRIDGE_HUB');

    return
      ZkSyncAdapterDeploymentHelper.getAdapterCode(
        ZkSyncAdapterDeploymentHelper.ZkSyncAdapterArgs({
          baseArgs: baseArgs,
          bridgeHub: BRIDGE_HUB(),
          refundAddress: REFUND_ADDRESS()
        })
      );
  }

  function _deployWithoutCreate2(BaseAdapterArgs memory baseArgs) internal returns (address) {
    require(BRIDGE_HUB() != address(0), 'Invalid BRIDGE_HUB');
    if (isTestnet()) {
      return
        address(
          new ZkSyncAdapterTestnet(
            baseArgs.crossChainController,
            BRIDGE_HUB(),
            REFUND_ADDRESS(),
            baseArgs.providerGasLimit,
            baseArgs.trustedRemotes
          )
        );
    } else {
      return
        address(
          new ZkSyncAdapter(
            baseArgs.crossChainController,
            BRIDGE_HUB(),
            REFUND_ADDRESS(),
            baseArgs.providerGasLimit,
            baseArgs.trustedRemotes
          )
        );
    }
  }
}
