// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IMessageService} from './interfaces/IMessageService.sol';
import {BaseAdapter} from '../BaseAdapter.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../../libs/Errors.sol';
import {ILineaAdapter, IBaseAdapter} from './ILineaAdapter.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

/**
 * @title LineaAdapter
 * @author BGD Labs
 * @notice Linea bridge adapter. Used to send and receive messages cross chain between Ethereum and Linea
 * @dev it uses the eth balance of CrossChainController contract to pay for message bridging as the method to bridge
        is called via delegate call
 * @dev note that this adapter can only be used for the communication path ETHEREUM -> LINEA
 * @dev documentation regarding the Linea bridge can be found here: https://docs.linea.build/get-started/concepts/message-service#technical-reference
 */
contract LineaAdapter is ILineaAdapter, BaseAdapter {
  /// @inheritdoc ILineaAdapter
  address public immutable LINEA_MESSAGE_SERVICE;

  uint256 public constant L2_FEE = 0.002 ether;

  /**
   * @notice only calls from the set message service are accepted.
   */
  modifier onlyLineaMessageService() {
    require(msg.sender == address(LINEA_MESSAGE_SERVICE), Errors.CALLER_NOT_LINEA_MESSAGE_SERVICE);
    _;
  }

  /**
   * @param params object containing the necessary parameters to initialize the contract
   */
  constructor(
    LineaParams memory params
  )
    BaseAdapter(
      params.crossChainController,
      params.providerGasLimit,
      'Linea native adapter',
      params.trustedRemotes
    )
  {
    require(
      params.lineaMessageService != address(0),
      Errors.LINEA_MESSAGE_SERVICE_CANT_BE_ADDRESS_0
    );
    LINEA_MESSAGE_SERVICE = params.lineaMessageService;
  }

  /// @inheritdoc IBaseAdapter
  function forwardMessage(
    address receiver,
    uint256,
    uint256 destinationChainId,
    bytes calldata message
  ) external virtual returns (address, uint256) {
    require(
      isDestinationChainIdSupported(destinationChainId),
      Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED
    );
    require(receiver != address(0), Errors.RECEIVER_NOT_SET);

    require(address(this).balance >= L2_FEE, Errors.NOT_ENOUGH_VALUE_TO_PAY_BRIDGE_FEES);

    // @dev we set _fee to hardcoded L2_FEE to overpay to ensure automatic claiming. If by some case it is not enough then
    // we will do the claim manually. Until an automated way of getting the price is implemented by Linea
    IMessageService(LINEA_MESSAGE_SERVICE).sendMessage{value: L2_FEE}(
      receiver,
      L2_FEE,
      abi.encodeWithSelector(ILineaAdapter.receiveMessage.selector, message)
    );
    return (LINEA_MESSAGE_SERVICE, 0);
  }

  /// @inheritdoc ILineaAdapter
  function receiveMessage(bytes calldata message) external onlyLineaMessageService {
    uint256 originChainId = getOriginChainId();
    address srcAddress = IMessageService(LINEA_MESSAGE_SERVICE).sender();
    require(
      _trustedRemotes[originChainId] == srcAddress && srcAddress != address(0),
      Errors.REMOTE_NOT_TRUSTED
    );

    _registerReceivedMessage(message, originChainId);
  }

  /// @inheritdoc ILineaAdapter
  function getOriginChainId() public pure virtual returns (uint256) {
    return ChainIds.ETHEREUM;
  }

  /// @inheritdoc ILineaAdapter
  function isDestinationChainIdSupported(uint256 chainId) public pure virtual returns (bool) {
    return chainId == ChainIds.LINEA;
  }

  /// @inheritdoc IBaseAdapter
  function nativeToInfraChainId(
    uint256 nativeChainId
  ) public pure override(BaseAdapter, IBaseAdapter) returns (uint256) {
    return nativeChainId;
  }

  /// @inheritdoc IBaseAdapter
  function infraToNativeChainId(
    uint256 infraChainId
  ) public pure override(BaseAdapter, IBaseAdapter) returns (uint256) {
    return infraChainId;
  }
}
