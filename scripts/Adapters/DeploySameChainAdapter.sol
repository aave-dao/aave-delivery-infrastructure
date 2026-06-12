// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {SameChainAdapter} from '../../src/contracts/adapters/sameChain/SameChainAdapter.sol';
import './BaseAdapterScript.sol';

library SameChainAdapterDeploymentHelper {
  function getAdapterCode() internal pure returns (bytes memory) {
    bytes memory creationCode = type(SameChainAdapter).creationCode;
    return abi.encodePacked(creationCode, abi.encode());
  }
}

abstract contract BaseSameChainAdapter is BaseAdapterScript {
  function _getAdapterByteCode(
    BaseAdapterArgs memory
  ) internal view override returns (bytes memory) {
    return SameChainAdapterDeploymentHelper.getAdapterCode();
  }
}
