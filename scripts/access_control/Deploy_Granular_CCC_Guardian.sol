// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../../src/contracts/access_control/GranularGuardianAccessControl.sol';
import '../BaseScript.sol';

library GranularGuardianDeploymentHelper {
  function getGranularGuardianCode(
    IGranularGuardianAccessControl.InitialGuardians memory initialGuardians,
    address crossChainController
  ) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        type(GranularGuardianAccessControl).creationCode,
        abi.encode(initialGuardians, crossChainController)
      );
  }
}

abstract contract BaseDeployGranularGuardian is BaseScript {
  function DEFAULT_ADMIN() internal view virtual returns (address);

  function RETRY_GUARDIAN() internal view virtual returns (address);

  function SOLVE_EMERGENCY_GUARDIAN() internal view virtual returns (address);

  function SALT() internal pure virtual returns (string memory) {
    return 'a.DI GranularGuardian';
  }

  function _deployGranularGuardian(address crossChainController) internal returns (address) {
    IGranularGuardianAccessControl.InitialGuardians
      memory initialGuardians = IGranularGuardianAccessControl.InitialGuardians({
        defaultAdmin: DEFAULT_ADMIN(),
        retryGuardian: RETRY_GUARDIAN(),
        solveEmergencyGuardian: SOLVE_EMERGENCY_GUARDIAN()
      });

    bytes memory ggCode = GranularGuardianDeploymentHelper.getGranularGuardianCode(
      initialGuardians,
      crossChainController
    );

    return _deployByteCode(ggCode, SALT());
  }
}
