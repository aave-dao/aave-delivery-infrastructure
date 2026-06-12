// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './BaseAdapterScript.sol';
import {ArbAdapter, IArbAdapter} from '../../src/contracts/adapters/arbitrum/ArbAdapter.sol';
import {ArbitrumAdapterTestnet} from '../contract_extensions/ArbitrumAdapter.sol';

library ArbAdapterDeploymentHelper {
  struct ArbAdapterArgs {
    BaseAdapterArgs baseArgs;
    address inbox;
    address refundAddress;
  }

  function getAdapterCode(ArbAdapterArgs memory arbArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = arbArgs.baseArgs.isTestnet
      ? type(ArbitrumAdapterTestnet).creationCode
      : type(ArbAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          arbArgs.baseArgs.crossChainController,
          arbArgs.inbox,
          arbArgs.refundAddress,
          arbArgs.baseArgs.providerGasLimit,
          arbArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseDeployArbAdapter is BaseAdapterScript {
  function INBOX() internal view virtual returns (address) {
    return address(0);
  }

  function REFUND_ADDRESS() internal view virtual returns (address) {
    return address(0);
  }

  function PROVIDER_GAS_LIMIT() internal view virtual override returns (uint256) {
    return 150_000;
  }

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(baseArgs.trustedRemotes.length == 1, 'Arb adapter can only have one remote');
    if (
      TRANSACTION_NETWORK() == ChainIds.ETHEREUM ||
      TRANSACTION_NETWORK() == TestNetChainIds.ETHEREUM_SEPOLIA
    ) {
      require(REFUND_ADDRESS() != address(0), 'Arbitrum CCC must be deployed');
      require(INBOX() != address(0), 'Arbitrum inbox can not be 0');
    }

    return
      ArbAdapterDeploymentHelper.getAdapterCode(
        ArbAdapterDeploymentHelper.ArbAdapterArgs({
          baseArgs: baseArgs,
          inbox: INBOX(),
          refundAddress: REFUND_ADDRESS()
        })
      );
  }
}
