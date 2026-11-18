// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

//import {CrossChainControllerWithEmergencyMode} from '../../../src/contracts/CrossChainControllerWithEmergencyMode.sol';
import {CrossChainControllerWithEmergencyMode} from '../munged/src/contracts/CrossChainControllerWithEmergencyMode.sol';
import {BaseCrossChainControllerHarness} from './BaseCrossChainControllerHarness.sol';

contract CrossChainControllerWithEmergencyModeHarness is 
    CrossChainControllerWithEmergencyMode, BaseCrossChainControllerHarness {
constructor(address clEmergencyOracle) CrossChainControllerWithEmergencyMode(clEmergencyOracle) {}

    function get__emergencyCount() external view returns(uint256) {
        return _emergencyCount;
    }
}
