// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {BaseAdapter, IBaseAdapter} from '../BaseAdapter.sol';
import {ICCIPAdapter, IRouterClient} from './ICCIPAdapter.sol';
import {IAny2EVMMessageReceiver, Client} from './interfaces/IAny2EVMMessageReceiver.sol';
import {IERC165} from './interfaces/IERC165.sol';
import {Errors} from '../../libs/Errors.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';

/**
 * @title CCIPAdapter
 * @author BGD Labs
 * @notice CCIP bridge adapter. Used to send and receive messages cross chain
 * @dev it uses the eth balance of CrossChainController contract to pay for message bridging as the method to bridge
        is called via delegate call
 */
contract CCIPAdapter is ICCIPAdapter, BaseAdapter, IAny2EVMMessageReceiver, IERC165 {
  using SafeERC20 for IERC20;

  /// @inheritdoc ICCIPAdapter
  IRouterClient public immutable CCIP_ROUTER;

  /// @inheritdoc ICCIPAdapter
  IERC20 public immutable LINK_TOKEN;

  /**
   * @notice only calls from the set router are accepted.
   */
  modifier onlyRouter() {
    require(msg.sender == address(CCIP_ROUTER), Errors.CALLER_NOT_CCIP_ROUTER);
    _;
  }

  /**
   * @param crossChainController address of the cross chain controller that will use this bridge adapter
   * @param ccipRouter ccip entry point address
   * @param providerGasLimit base gas limit used by the bridge adapter
   * @param trustedRemotes list of remote configurations to set as trusted
   * @param linkToken address of the erc20 LINK token
   */
  constructor(
    address crossChainController,
    address ccipRouter,
    uint256 providerGasLimit,
    TrustedRemotesConfig[] memory trustedRemotes,
    address linkToken
  ) BaseAdapter(crossChainController, providerGasLimit, 'CCIP adapter', trustedRemotes) {
    require(ccipRouter != address(0), Errors.CCIP_ROUTER_CANT_BE_ADDRESS_0);
    require(linkToken != address(0), Errors.LINK_TOKEN_CANT_BE_ADDRESS_0);
    CCIP_ROUTER = IRouterClient(ccipRouter);
    LINK_TOKEN = IERC20(linkToken);
  }

  /// @inheritdoc IERC165
  function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
    return
      interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  /// @inheritdoc IBaseAdapter
  function forwardMessage(
    address receiver,
    uint256 executionGasLimit,
    uint256 destinationChainId,
    bytes calldata message
  ) external returns (address, uint256) {
    uint64 nativeChainId = SafeCast.toUint64(infraToNativeChainId(destinationChainId));
    require(CCIP_ROUTER.isChainSupported(nativeChainId), Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED);
    require(receiver != address(0), Errors.RECEIVER_NOT_SET);

    uint256 totalGasLimit = executionGasLimit + BASE_GAS_LIMIT;

    Client.EVMExtraArgsV1 memory evmExtraArgs = Client.EVMExtraArgsV1({
      gasLimit: totalGasLimit,
      strict: false
    });

    bytes memory extraArgs = Client._argsToBytes(evmExtraArgs);

    Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(receiver),
      data: message,
      tokenAmounts: new Client.EVMTokenAmount[](0),
      feeToken: address(LINK_TOKEN),
      extraArgs: extraArgs
    });

    uint256 clFee = CCIP_ROUTER.getFee(nativeChainId, ccipMessage);

    require(clFee != 0, Errors.CCIP_MESSAGE_IS_INVALID);

    require(
      LINK_TOKEN.balanceOf(address(this)) >= clFee,
      Errors.NOT_ENOUGH_VALUE_TO_PAY_BRIDGE_FEES
    );

    bytes32 messageId = CCIP_ROUTER.ccipSend(nativeChainId, ccipMessage);
    return (address(CCIP_ROUTER), uint256(messageId));
  }

  /// @inheritdoc IAny2EVMMessageReceiver
  function ccipReceive(Client.Any2EVMMessage calldata message) external onlyRouter {
    address srcAddress = abi.decode(message.sender, (address));

    uint256 originChainId = nativeToInfraChainId(message.sourceChainSelector);

    require(
      _trustedRemotes[originChainId] == srcAddress && srcAddress != address(0),
      Errors.REMOTE_NOT_TRUSTED
    );

    _registerReceivedMessage(message.data, originChainId);
  }

  /// @inheritdoc IBaseAdapter
  function setupPayments() external override {
    LINK_TOKEN.forceApprove(address(CCIP_ROUTER), type(uint256).max);
  }

  /// @inheritdoc IBaseAdapter
  function nativeToInfraChainId(
    uint256 nativeChainId
  ) public pure virtual override returns (uint256) {
    if (nativeChainId == uint64(5009297550715157269)) {
      return ChainIds.ETHEREUM;
    } else if (nativeChainId == uint64(6433500567565415381)) {
      return ChainIds.AVALANCHE;
    } else if (nativeChainId == uint64(4051577828743386545)) {
      return ChainIds.POLYGON;
    } else if (nativeChainId == uint64(11344663589394136015)) {
      return ChainIds.BNB;
    } else if (nativeChainId == uint64(1346049177634351622)) {
      return ChainIds.CELO;
    } else if (nativeChainId == uint64(1673871237479749969)) {
      return ChainIds.SONIC;
    } else if (nativeChainId == uint64(9335212494177455608)) {
      return ChainIds.PLASMA;
    } else if (nativeChainId == uint64(8481857512324358265)) {
      return ChainIds.MONAD;
    }
    return nativeChainId;
  }

  /// @inheritdoc IBaseAdapter
  function infraToNativeChainId(
    uint256 infraChainId
  ) public pure virtual override returns (uint256) {
    if (infraChainId == ChainIds.ETHEREUM) {
      return uint64(5009297550715157269);
    } else if (infraChainId == ChainIds.AVALANCHE) {
      return uint64(6433500567565415381);
    } else if (infraChainId == ChainIds.POLYGON) {
      return uint64(4051577828743386545);
    } else if (infraChainId == ChainIds.BNB) {
      return uint64(11344663589394136015);
    } else if (infraChainId == ChainIds.CELO) {
      return uint64(1346049177634351622);
    } else if (infraChainId == ChainIds.SONIC) {
      return uint64(1673871237479749969);
    } else if (infraChainId == ChainIds.PLASMA) {
      return uint64(9335212494177455608);
    } else if (infraChainId == ChainIds.MONAD) {
      return uint64(8481857512324358265);
    }
    return infraChainId;
  }
}
