// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {HyperLaneAdapter, IHyperLaneAdapter, IBaseAdapter} from '../../src/contracts/adapters/hyperLane/HyperLaneAdapter.sol';
import './BaseAdapterScript.sol';

library HLAdapterDeploymentHelper {
  struct HLAdapterArgs {
    BaseAdapterArgs baseArgs;
    address mailBox;
  }

  function getAdapterCode(HLAdapterArgs memory hlArgs) internal pure returns (bytes memory) {
    bytes memory creationCode = type(HyperLaneAdapter).creationCode;

    return
      abi.encodePacked(
        creationCode,
        abi.encode(
          hlArgs.baseArgs.crossChainController,
          hlArgs.mailBox,
          hlArgs.baseArgs.providerGasLimit,
          hlArgs.baseArgs.trustedRemotes
        )
      );
  }
}

abstract contract BaseHLAdapter is BaseAdapterScript {
  function HL_MAIL_BOX() internal view virtual returns (address);

  function _getAdapterByteCode(
    BaseAdapterArgs memory baseArgs
  ) internal view override returns (bytes memory) {
    require(HL_MAIL_BOX() != address(0), 'Invalid HL MailBox');

    return
      HLAdapterDeploymentHelper.getAdapterCode(
        HLAdapterDeploymentHelper.HLAdapterArgs({baseArgs: baseArgs, mailBox: HL_MAIL_BOX()})
      );
  }
}
