// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';
import {OwnableWithGuardian} from '../src/contracts/old-oz/OwnableWithGuardian.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ERC20} from './mocks/ERC20.sol';
import {IBaseCrossChainController, ICrossChainForwarder, ICrossChainReceiver} from 'src/contracts/interfaces/IBaseCrossChainController.sol';
import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../src/contracts/libs/Errors.sol';
import {IBaseAdapter} from '../src/contracts/adapters/IBaseAdapter.sol';
import {IRescuable} from 'solidity-utils/contracts/utils/interfaces/IRescuable.sol';

abstract contract BaseCrossChainControllerTest is Test {
  address public constant OWNER = address(65536 + 123);
  address public constant GUARDIAN = address(65536 + 1234);
  address public constant BRIDGE_ADAPTER = address(65536 + 123456);

  uint8 public constant CONFIRMATIONS = 1;

  TransparentProxyFactory public proxyFactory;
  address public crossChainControllerImpl;
  IBaseCrossChainController public crossChainController;

  bytes32 public constant PROXY_ADMIN_SALT = keccak256('proxy admin salt');
  bytes32 public constant CROSS_CHAIN_CONTROLLER_SALT = keccak256('cross chain controller salt');

  IERC20 public testToken;

  event ERC20Rescued(
    address indexed caller,
    address indexed token,
    address indexed to,
    uint256 amount
  );

  event NativeTokensRescued(address indexed caller, address indexed to, uint256 amount);

  function _deployControllerImplementation() internal virtual returns (address);

  function _getEncodedInitializer(
    address owner,
    address guardian,
    ICrossChainReceiver.ConfirmationInput[] memory initialRequiredConfirmations,
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToAllow,
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[] memory forwarderBridgeAdaptersToEnable,
    address[] memory sendersToApprove,
    ICrossChainForwarder.OptimalBandwidthByChain[] memory optimalBandwidthByChain
  ) internal view virtual returns (bytes memory);

  function setUp() public {
    testToken = new ERC20('Test', 'TST');
    proxyFactory = new TransparentProxyFactory();

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
    sendersToApprove[0] = address(65536 + 102);
    ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]
      memory forwarderBridgeAdaptersToEnable = new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](
        1
      );
    forwarderBridgeAdaptersToEnable[0] = ICrossChainForwarder.ForwarderBridgeAdapterConfigInput({
      currentChainBridgeAdapter: address(65536 + 103),
      destinationBridgeAdapter: address(65536 + 110),
      destinationChainId: ChainIds.POLYGON
    });
    ICrossChainForwarder.OptimalBandwidthByChain[]
      memory optimalBandwidthByChain = new ICrossChainForwarder.OptimalBandwidthByChain[](1);
    optimalBandwidthByChain[0] = ICrossChainForwarder.OptimalBandwidthByChain({
      chainId: 1,
      optimalBandwidth: 1
    });

    crossChainControllerImpl = _deployControllerImplementation();

    vm.mockCall(
      address(65536 + 103),
      abi.encodeWithSelector(IBaseAdapter.setupPayments.selector),
      abi.encode()
    );
    crossChainController = IBaseCrossChainController(
      proxyFactory.createDeterministic(
        crossChainControllerImpl,
        OWNER,
        _getEncodedInitializer(
          OWNER,
          GUARDIAN,
          initialRequiredConfirmations,
          receiverBridgeAdaptersToAllow,
          forwarderBridgeAdaptersToEnable,
          sendersToApprove,
          optimalBandwidthByChain
        ),
        CROSS_CHAIN_CONTROLLER_SALT
      )
    );
  }

  function testInitializeWhenAdaptersLessThanConfirmations() public {
    // chains
    uint256[] memory chainIds = new uint256[](1);
    chainIds[0] = ChainIds.ETHEREUM;

    // confirmations
    ICrossChainReceiver.ConfirmationInput memory confirmation = ICrossChainReceiver
      .ConfirmationInput({chainId: ChainIds.ETHEREUM, requiredConfirmations: 3});
    ICrossChainReceiver.ConfirmationInput[]
      memory initialRequiredConfirmations = new ICrossChainReceiver.ConfirmationInput[](1);
    initialRequiredConfirmations[0] = confirmation;

    // adapters
    ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[]
      memory receiverBridgeAdaptersToAllow = new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](
        1
      );
    receiverBridgeAdaptersToAllow[0] = ICrossChainReceiver.ReceiverBridgeAdapterConfigInput({
      bridgeAdapter: BRIDGE_ADAPTER,
      chainIds: chainIds
    });

    vm.expectRevert(bytes(Errors.INVALID_REQUIRED_CONFIRMATIONS));
    proxyFactory.createDeterministic(
      crossChainControllerImpl,
      OWNER,
      _getEncodedInitializer(
        OWNER,
        GUARDIAN,
        initialRequiredConfirmations,
        receiverBridgeAdaptersToAllow,
        new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
        new address[](0),
        new ICrossChainForwarder.OptimalBandwidthByChain[](0)
      ),
      CROSS_CHAIN_CONTROLLER_SALT
    );
  }

  function testOwnership() public {
    assertEq(OwnableWithGuardian(address(crossChainController)).owner(), OWNER);
    assertEq(OwnableWithGuardian(address(crossChainController)).guardian(), GUARDIAN);
  }

  function testEmergencyEtherTransfer() public {
    address randomWallet = address(1239516);
    hoax(randomWallet, 50 ether);
    Address.sendValue(payable(address(crossChainController)), 5 ether);

    assertEq(address(crossChainController).balance, 5 ether);

    address recipient = address(1230123519);

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit NativeTokensRescued(OWNER, recipient, 5 ether);
    crossChainController.emergencyEtherTransfer(recipient, 5 ether);

    assertEq(address(crossChainController).balance, 0 ether);
    assertEq(address(recipient).balance, 5 ether);
  }

  function testEmergencyEtherTransferWhenNotOwner() public {
    address randomWallet = address(1239516);

    hoax(randomWallet, 50 ether);
    Address.sendValue(payable(address(crossChainController)), 5 ether);

    assertEq(address(crossChainController).balance, 5 ether);

    address recipient = address(1230123519);

    vm.expectRevert(abi.encodeWithSelector(IRescuable.OnlyRescueGuardian.selector));
    crossChainController.emergencyEtherTransfer(recipient, 5 ether);
  }

  function testEmergencyTokenTransfer() public {
    address randomWallet = address(1239516);
    deal(address(testToken), randomWallet, 10 ether);
    hoax(randomWallet);
    testToken.transfer(address(crossChainController), 3 ether);

    assertEq(testToken.balanceOf(address(crossChainController)), 3 ether);

    address recipient = address(1230123519);

    hoax(OWNER);
    vm.expectEmit(true, true, false, true);
    emit ERC20Rescued(OWNER, address(testToken), recipient, 3 ether);
    crossChainController.emergencyTokenTransfer(address(testToken), recipient, 3 ether);

    assertEq(testToken.balanceOf(address(crossChainController)), 0);
    assertEq(testToken.balanceOf(address(recipient)), 3 ether);
  }

  function testEmergencyTokenTransferWhenNotOwner() public {
    address randomWallet = address(1239516);
    deal(address(testToken), randomWallet, 10 ether);
    hoax(randomWallet);
    testToken.transfer(address(crossChainController), 3 ether);

    assertEq(testToken.balanceOf(address(crossChainController)), 3 ether);

    address recipient = address(1230123519);

    vm.expectRevert(abi.encodeWithSelector(IRescuable.OnlyRescueGuardian.selector));
    crossChainController.emergencyTokenTransfer(address(testToken), recipient, 3 ether);
  }
}
