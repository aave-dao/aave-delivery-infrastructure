// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {WormholeExecutorAdapter, IWormholeExecutorAdapter, IBaseAdapter} from '../../src/contracts/adapters/wormhole/WormholeExecutorAdapter.sol';
import './BaseAdapterScript.sol';

library WormholeExecutorAdapterDeploymentHelper {
  struct WormholeExecutorAdapterArgs {
    BaseAdapterArgs baseArgs;
    address wormholeCore;
    address executorQuoterRouter;
    address quoter;
    address refundAddress;
  }

  function getAdapterCode(
    WormholeExecutorAdapterArgs memory wormholeArgs
  ) internal pure returns (bytes memory) {
    bytes memory creationCode = type(WormholeExecutorAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          wormholeArgs.baseArgs.crossChainController,
          wormholeArgs.wormholeCore,
          wormholeArgs.executorQuoterRouter,
          wormholeArgs.quoter,
          wormholeArgs.refundAddress,
          wormholeArgs.baseArgs.providerGasLimit,
          wormholeArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseWormholeExecutorAdapter is BaseAdapterScript {
  function WORMHOLE_CORE() internal view virtual returns (address);

  function EXECUTOR_QUOTER_ROUTER() internal view virtual returns (address);

  function QUOTER() internal view virtual returns (address);

  /// @dev refund address is only relevant on the sending side; receive-only deployments may return 0
  function REFUND_ADDRESS() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(WORMHOLE_CORE() != address(0), 'Wormhole core can not be 0');
    require(EXECUTOR_QUOTER_ROUTER() != address(0), 'Wormhole quoter router can not be 0');
    require(QUOTER() != address(0), 'Wormhole quoter can not be 0');

    return
      WormholeExecutorAdapterDeploymentHelper.getAdapterCode(
        WormholeExecutorAdapterDeploymentHelper.WormholeExecutorAdapterArgs({
          baseArgs: baseArgs,
          wormholeCore: WORMHOLE_CORE(),
          executorQuoterRouter: EXECUTOR_QUOTER_ROUTER(),
          quoter: QUOTER(),
          refundAddress: REFUND_ADDRESS()
        })
      );
  }
}
