// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {IEmergencyRegistry} from '../../src/contracts/emergency/interfaces/IEmergencyRegistry.sol';
import {EmergencyRegistry} from '../../src/contracts/emergency/EmergencyRegistry.sol';
import {Errors} from '../../src/contracts/libs/Errors.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';

contract EmergencyRegistryTest is Test {
  uint256 public constant AVALANCHE_CHAIN_ID = 43114;
  uint256 public constant POLYGON_CHAIN_ID = 137;
  IEmergencyRegistry public emergencyRegistry;

  event NetworkEmergencyStateUpdated(uint256 indexed chainId, int256 emergencyNumber);

  function setUp() public {
    emergencyRegistry = new EmergencyRegistry();
  }

  function testSetEmergency(uint256 chainId) public {
    uint256[] memory chains = new uint256[](1);
    chains[0] = chainId;

    vm.expectEmit(true, false, false, true);
    emit NetworkEmergencyStateUpdated(chainId, 1);
    emergencyRegistry.setEmergency(chains);

    assertEq(emergencyRegistry.getNetworkEmergencyCount(chainId), 1);
  }

  function testSetEmergencySameChainTwoTimes(uint256 chainId) public {
    uint256[] memory chains = new uint256[](2);
    chains[0] = chainId;
    chains[1] = chainId;

    vm.expectRevert(bytes(Errors.ONLY_ONE_EMERGENCY_UPDATE_PER_CHAIN));
    emergencyRegistry.setEmergency(chains);
  }

  function testSetEmergencyWhenNotOwner(address notOwner, uint256 chainId) public {
    vm.assume(notOwner != address(this));
    uint256[] memory chains = new uint256[](1);
    chains[0] = chainId;

    hoax(notOwner);
    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner))
    );
    emergencyRegistry.setEmergency(chains);
  }

  function testGetNetworkEmergencyCount(uint256 chainOne, uint256 chainTwo) public {
    vm.assume(chainOne != chainTwo);
    uint256[] memory chains0 = new uint256[](1);
    chains0[0] = chainOne;

    uint256[] memory chains1 = new uint256[](2);
    chains1[0] = chainOne;
    chains1[1] = chainTwo;

    emergencyRegistry.setEmergency(chains0);

    int256 emergency0 = emergencyRegistry.getNetworkEmergencyCount(chainOne);

    emergencyRegistry.setEmergency(chains1);

    int256 emergency1 = emergencyRegistry.getNetworkEmergencyCount(chainOne);
    int256 emergency2 = emergencyRegistry.getNetworkEmergencyCount(chainTwo);

    assertEq(emergency0, 1);
    assertEq(emergency1, 2);
    assertEq(emergency2, 1);
  }
}
