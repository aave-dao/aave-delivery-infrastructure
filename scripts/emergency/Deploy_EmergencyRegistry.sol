// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {EmergencyRegistry} from '../../src/contracts/emergency/EmergencyRegistry.sol';
import '../BaseScript.sol';

library EmergencyRegistryDeploymentHelper {
  function getEmergencyRegistryCode() internal pure returns (bytes memory) {
    return abi.encodePacked(type(EmergencyRegistry).creationCode, abi.encode());
  }
}

abstract contract BaseDeployEmergencyMode is BaseScript {
  function OWNER() internal view virtual returns (address) {
    return address(msg.sender);
  }

  function SALT() internal pure virtual returns (string memory) {
    return 'a.DI EmergencyRegistry';
  }

  function _deployEmergencyRegistry() internal returns (address) {
    bytes memory erCode = EmergencyRegistryDeploymentHelper.getEmergencyRegistryCode();
    return _deployByteCode(erCode, SALT());
  }
}
