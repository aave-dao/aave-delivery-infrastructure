// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './BaseCrossChainController.t.sol';
import {ICLEmergencyOracle} from '../src/contracts/emergency/interfaces/ICLEmergencyOracle.sol';
import {CrossChainControllerWithEmergencyMode, ICrossChainControllerWithEmergencyMode} from '../src/contracts/CrossChainControllerWithEmergencyMode.sol';
import {IWithGuardian} from '../src/contracts/old-oz/interfaces/IWithGuardian.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';

contract CrossChainControllerWithEmergencyModeTest is BaseCrossChainControllerTest {
  address public constant CL_EMERGENCY_ORACLE = address(12345);
  event CLEmergencyOracleUpdated(address indexed newChainlinkEmergencyOracle);

  function _deployControllerImplementation() internal override returns (address) {
    return address(new CrossChainControllerWithEmergencyMode(CL_EMERGENCY_ORACLE));
  }

  function _getEncodedInitializer(
    address owner,
    address guardian,
    ICrossChainReceiver.ConfirmationInput[] memory initialRequiredConfirmations,
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToAllow,
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[] memory forwarderBridgeAdaptersToEnable,
    address[] memory sendersToApprove,
    ICrossChainForwarder.OptimalBandwidthByChain[] memory optimalBandwidthByChain
  ) internal pure override returns (bytes memory) {
    return
      abi.encodeWithSelector(
        ICrossChainControllerWithEmergencyMode.initialize.selector,
        owner,
        guardian,
        CL_EMERGENCY_ORACLE,
        initialRequiredConfirmations,
        receiverBridgeAdaptersToAllow,
        forwarderBridgeAdaptersToEnable,
        sendersToApprove,
        optimalBandwidthByChain
      );
  }

  function testInitializeWithZeroCLEmergencyOracleAddress() public {
    // receiver configs
    uint256[] memory chainIds = new uint256[](1);
    chainIds[0] = ChainIds.ETHEREUM;
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory receiverBridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](
        1
      );
    receiverBridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: BRIDGE_ADAPTER,
      chainIds: chainIds
    });

    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: ChainIds.ETHEREUM, requiredConfirmations: CONFIRMATIONS});
    ICrossChainReceiver.ConfirmationInput[]
      memory initialRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    initialRequiredConfirmations[0] = confirmation;

    // forwarder configs
    address[] memory sendersToApprove = new address[](1);
    sendersToApprove[0] = address(102);
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory forwarderBridgeAdaptersToEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        1
      );
    forwarderBridgeAdaptersToEnable[0] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(103),
      destinationBridgeAdapter: address(110),
      destinationChainId: ChainIds.POLYGON
    });

    ICrossChainForwarder.OptimalBandwidthByChain[]
      memory optimalBandwidthByChain = new ICrossChainForwarder.OptimalBandwidthByChain[](0);

    vm.expectRevert(bytes(Errors.INVALID_EMERGENCY_ORACLE));
    proxyFactory.createDeterministic(
      crossChainControllerImpl,
      OWNER,
      abi.encodeWithSelector(
        ICrossChainControllerWithEmergencyMode.initialize.selector,
        OWNER,
        GUARDIAN,
        address(0),
        initialRequiredConfirmations,
        receiverBridgeAdaptersToAllow,
        forwarderBridgeAdaptersToEnable,
        sendersToApprove,
        optimalBandwidthByChain
      ),
      CROSS_CHAIN_CONTROLLER_SALT
    );
  }

  function testCLEmergencyOracle() public {
    assertEq(
      ICrossChainControllerWithEmergencyMode(address(crossChainController))
        .getChainlinkEmergencyOracle(),
      CL_EMERGENCY_ORACLE
    );
  }

  struct EmergencyArgs {
    ICrossChainReceiver.ConfirmationInput[] newConfirmations;
    ICrossChainReceiver.ValidityTimestampInput[] newValidityTimestamps;
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[] receiverBridgeAdaptersToAllow;
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[] receiverBridgeAdaptersToDisallow;
    address[] sendersToApprove;
    address[] sendersToRemove;
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[] forwarderBridgeAdaptersToEnable;
    ICrossChainForwarder.BridgeAdapterToDisable[] forwarderBridgeAdaptersToDisable;
    ICrossChainForwarder.OptimalBandwidthByChain[] optimalBandwidthByChain;
  }

  function testSolveEmergency() public {
    ICrossChainForwarder.ChainIdBridgeConfig[]
      memory forwarderBridgeAdaptersBefore = crossChainController.getForwarderBridgeAdaptersByChain(
        ChainIds.POLYGON
      );

    EmergencyArgs memory args = EmergencyArgs({
      newConfirmations: new ICrossChainReceiver.ConfirmationInput[](1),
      newValidityTimestamps: new ICrossChainReceiver.ValidityTimestampInput[](1),
      receiverBridgeAdaptersToAllow: new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1),
      receiverBridgeAdaptersToDisallow: new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](
        1
      ),
      sendersToApprove: new address[](1),
      sendersToRemove: new address[](1),
      forwarderBridgeAdaptersToEnable: new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        1
      ),
      forwarderBridgeAdaptersToDisable: new ICrossChainForwarder.BridgeAdapterToDisable[](1),
      optimalBandwidthByChain: new ICrossChainForwarder.OptimalBandwidthByChain[](1)
    });
    // receiver config
    uint256[] memory originChainIds = new uint256[](1);
    originChainIds[0] = ChainIds.ETHEREUM;

    args.receiverBridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: address(201),
      chainIds: originChainIds
    });
    uint8 newConfirmation = 1;
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: ChainIds.ETHEREUM, requiredConfirmations: newConfirmation});
    args.newConfirmations[0] = confirmation;

    args.receiverBridgeAdaptersToDisallow[0].bridgeAdapter = BRIDGE_ADAPTER;
    args.receiverBridgeAdaptersToDisallow[0].chainIds = new uint256[](2);
    args.receiverBridgeAdaptersToDisallow[0].chainIds[0] = 1;
    args.receiverBridgeAdaptersToDisallow[0].chainIds[1] = 137;

    uint120 newValidityTimestamp = uint120(block.timestamp + 5);
    args.newValidityTimestamps[0] = ICrossChainReceiver.ValidityTimestampInput({
      chainId: ChainIds.ETHEREUM,
      validityTimestamp: newValidityTimestamp
    });

    // forwarder config
    args.sendersToApprove[0] = address(202);
    args.sendersToRemove[0] = address(102);
    args.forwarderBridgeAdaptersToEnable[0] = ICrossChainForwarder
      .ForwarderBridgeAdapterConfigInput({
        currentChainBridgeAdapter: address(203),
        destinationBridgeAdapter: address(210),
        destinationChainId: ChainIds.POLYGON
      });
    uint256[] memory chainIds = new uint256[](1);
    chainIds[0] = ChainIds.POLYGON;
    args.forwarderBridgeAdaptersToDisable[0] = ICrossChainForwarder.BridgeAdapterToDisable({
      bridgeAdapter: address(103),
      chainIds: chainIds
    });
    args.optimalBandwidthByChain[0] = ICrossChainForwarder.OptimalBandwidthByChain({
      chainId: 1,
      optimalBandwidth: 3
    });

    skip(10);

    hoax(GUARDIAN);
    vm.mockCall(
      CL_EMERGENCY_ORACLE,
      abi.encodeWithSelector(ICLEmergencyOracle.latestRoundData.selector),
      abi.encode(uint80(0), int256(1), 0, 0, uint80(0))
    );
    vm.mockCall(
      address(203),
      abi.encodeWithSelector(IBaseAdapter.setupPayments.selector),
      abi.encode()
    );

    ICrossChainControllerWithEmergencyMode(address(crossChainController)).solveEmergency(
      args.newConfirmations,
      args.newValidityTimestamps,
      args.receiverBridgeAdaptersToAllow,
      args.receiverBridgeAdaptersToDisallow,
      args.sendersToApprove,
      args.sendersToRemove,
      args.forwarderBridgeAdaptersToEnable,
      args.forwarderBridgeAdaptersToDisable,
      args.optimalBandwidthByChain
    );

    ICrossChainReceiver.ReceiverConfiguration memory receiverConfig = crossChainController
      .getConfigurationByChain(ChainIds.ETHEREUM);
    assertEq(receiverConfig.requiredConfirmation, newConfirmation);
    assertEq(receiverConfig.validityTimestamp, newValidityTimestamp);
    assertEq(
      crossChainController.isReceiverBridgeAdapterAllowed(address(201), ChainIds.ETHEREUM),
      true
    );
    assertEq(
      crossChainController.isReceiverBridgeAdapterAllowed(BRIDGE_ADAPTER, ChainIds.ETHEREUM),
      false
    );
    assertEq(crossChainController.isSenderApproved(address(202)), true);
    assertEq(crossChainController.isSenderApproved(address(102)), false);

    ICrossChainForwarder.ChainIdBridgeConfig[] memory forwarderBridgeAdapters = crossChainController
      .getForwarderBridgeAdaptersByChain(ChainIds.POLYGON);

    assertEq(forwarderBridgeAdapters.length, forwarderBridgeAdaptersBefore.length + 1);
    assertEq(
      forwarderBridgeAdapters[0].destinationBridgeAdapter,
      forwarderBridgeAdaptersBefore[0].destinationBridgeAdapter
    );
    assertEq(
      forwarderBridgeAdapters[0].currentChainBridgeAdapter,
      forwarderBridgeAdaptersBefore[0].currentChainBridgeAdapter
    );
    assertEq(forwarderBridgeAdapters[1].destinationBridgeAdapter, address(210));
    assertEq(forwarderBridgeAdapters[1].currentChainBridgeAdapter, address(203));
    assertEq(crossChainController.getOptimalBandwidthByChain(1), 3);
  }

  function testSolveEmergencyWhenUnreachableConfirmations() public {
    EmergencyArgs memory args = EmergencyArgs({
      newConfirmations: new ICrossChainReceiver.ConfirmationInput[](1),
      newValidityTimestamps: new ICrossChainReceiver.ValidityTimestampInput[](1),
      receiverBridgeAdaptersToAllow: new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](1),
      receiverBridgeAdaptersToDisallow: new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](
        1
      ),
      sendersToApprove: new address[](1),
      sendersToRemove: new address[](1),
      forwarderBridgeAdaptersToEnable: new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        1
      ),
      forwarderBridgeAdaptersToDisable: new ICrossChainForwarder.BridgeAdapterToDisable[](1),
      optimalBandwidthByChain: new ICrossChainForwarder.OptimalBandwidthByChain[](0)
    });

    // receiver config
    uint256[] memory originChainIds = new uint256[](1);
    originChainIds[0] = ChainIds.ETHEREUM;
    args.receiverBridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: address(201),
      chainIds: originChainIds
    });
    uint8 newConfirmation = 3;
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: ChainIds.ETHEREUM, requiredConfirmations: newConfirmation});
    args.newConfirmations[0] = confirmation;

    args.receiverBridgeAdaptersToDisallow[0].bridgeAdapter = BRIDGE_ADAPTER;
    args.receiverBridgeAdaptersToDisallow[0].chainIds = new uint256[](2);
    args.receiverBridgeAdaptersToDisallow[0].chainIds[0] = 1;
    args.receiverBridgeAdaptersToDisallow[0].chainIds[1] = 137;

    uint120 newValidityTimestamp = uint120(block.timestamp + 5);
    args.newValidityTimestamps[0] = ICrossChainReceiver.ValidityTimestampInput({
      chainId: ChainIds.ETHEREUM,
      validityTimestamp: newValidityTimestamp
    });

    // forwarder config
    args.sendersToApprove[0] = address(202);
    args.sendersToRemove[0] = address(102);
    args.forwarderBridgeAdaptersToEnable[0] = ICrossChainForwarder
      .ForwarderBridgeAdapterConfigInput({
        currentChainBridgeAdapter: address(203),
        destinationBridgeAdapter: address(210),
        destinationChainId: ChainIds.POLYGON
      });
    uint256[] memory chainIds = new uint256[](1);
    chainIds[0] = ChainIds.POLYGON;
    args.forwarderBridgeAdaptersToDisable[0] = ICrossChainForwarder.BridgeAdapterToDisable({
      bridgeAdapter: address(103),
      chainIds: chainIds
    });

    hoax(GUARDIAN);
    vm.mockCall(
      CL_EMERGENCY_ORACLE,
      abi.encodeWithSelector(ICLEmergencyOracle.latestRoundData.selector),
      abi.encode(uint80(0), int256(1), 0, 0, uint80(0))
    );
    vm.expectRevert(bytes(Errors.INVALID_REQUIRED_CONFIRMATIONS));
    ICrossChainControllerWithEmergencyMode(address(crossChainController)).solveEmergency(
      args.newConfirmations,
      args.newValidityTimestamps,
      args.receiverBridgeAdaptersToAllow,
      args.receiverBridgeAdaptersToDisallow,
      args.sendersToApprove,
      args.sendersToRemove,
      args.forwarderBridgeAdaptersToEnable,
      args.forwarderBridgeAdaptersToDisable,
      args.optimalBandwidthByChain
    );
  }

  function testSolveEmergencyWhenNotGuardian() public {
    vm.expectRevert(bytes('ONLY_BY_GUARDIAN'));
    ICrossChainControllerWithEmergencyMode(address(crossChainController)).solveEmergency(
      new ICrossChainReceiver.ConfirmationInput[](0),
      new ICrossChainReceiver.ValidityTimestampInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new address[](0),
      new address[](0),
      new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
      new ICrossChainForwarder.BridgeAdapterToDisable[](0),
      new ICrossChainForwarder.OptimalBandwidthByChain[](0)
    );
  }

  function testSolveEmergencyWhenGuardianNotEmergencyMode() public {
    uint80 roundId = uint80(0);
    int256 answer = int256(0);
    uint256 startedAt = 0;
    uint256 updatedAt = 0;
    uint80 answeredInRound = uint80(0);

    hoax(GUARDIAN);
    vm.mockCall(
      CL_EMERGENCY_ORACLE,
      abi.encodeWithSelector(ICLEmergencyOracle.latestRoundData.selector),
      abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
    );
    vm.expectRevert(bytes(Errors.NOT_IN_EMERGENCY));
    ICrossChainControllerWithEmergencyMode(address(crossChainController)).solveEmergency(
      new ICrossChainReceiver.ConfirmationInput[](0),
      new ICrossChainReceiver.ValidityTimestampInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new address[](0),
      new address[](0),
      new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
      new ICrossChainForwarder.BridgeAdapterToDisable[](0),
      new ICrossChainForwarder.OptimalBandwidthByChain[](0)
    );
  }

  function testUpdateCLEmergencyOracle() public {
    address newChainlinkEmergencyOracle = address(101);

    hoax(OWNER);
    vm.expectEmit(true, false, false, true);
    emit CLEmergencyOracleUpdated(newChainlinkEmergencyOracle);
    ICrossChainControllerWithEmergencyMode(address(crossChainController)).updateCLEmergencyOracle(
      newChainlinkEmergencyOracle
    );

    assertEq(
      ICrossChainControllerWithEmergencyMode(address(crossChainController))
        .getChainlinkEmergencyOracle(),
      newChainlinkEmergencyOracle
    );
  }

  function testUpdateCLEmergencyOracleWhenNotOwner() public {
    address newChainlinkEmergencyOracle = address(101);

    vm.expectRevert(
      bytes(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)))
    );
    ICrossChainControllerWithEmergencyMode(address(crossChainController)).updateCLEmergencyOracle(
      newChainlinkEmergencyOracle
    );

    assertEq(
      ICrossChainControllerWithEmergencyMode(address(crossChainController))
        .getChainlinkEmergencyOracle(),
      CL_EMERGENCY_ORACLE
    );
  }
}
