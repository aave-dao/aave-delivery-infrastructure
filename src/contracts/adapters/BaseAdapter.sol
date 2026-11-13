// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {IBaseAdapter, IBaseCrossChainController} from './IBaseAdapter.sol';
import {Errors} from '../libs/Errors.sol';

/**
 * @title BaseAdapter
 * @author BGD Labs
 * @notice base contract implementing the method to route a bridged message to the CrossChainController contract.
 * @dev All bridge adapters must implement this contract
 */
abstract contract BaseAdapter is IBaseAdapter {
  /// @inheritdoc IBaseAdapter
  IBaseCrossChainController public immutable CROSS_CHAIN_CONTROLLER;

  /// @inheritdoc IBaseAdapter
  uint256 public immutable BASE_GAS_LIMIT;

  // @dev this is the original address of the contract. Required to identify and prevent delegate calls.
  address private immutable _selfAddress;

  // (standard chain id -> origin forwarder address) saves for every chain the address that can forward messages to this adapter
  mapping(uint256 => address) internal _trustedRemotes;

  /// @inheritdoc IBaseAdapter
  string public adapterName;

  /**
   * @param crossChainController address of the CrossChainController the bridged messages will be routed to
   * @param providerGasLimit base gas limit used by the bridge adapter
   * @param name name of the bridge adapter contract
   * @param originConfigs pair of origin address and chain id that adapter is allowed to get messages from
   */
  constructor(
    address crossChainController,
    uint256 providerGasLimit,
    string memory name,
    TrustedRemotesConfig[] memory originConfigs
  ) {
    require(crossChainController != address(0), Errors.INVALID_BASE_ADAPTER_CROSS_CHAIN_CONTROLLER);
    CROSS_CHAIN_CONTROLLER = IBaseCrossChainController(crossChainController);

    BASE_GAS_LIMIT = providerGasLimit;
    adapterName = name;

    _selfAddress = address(this);

    for (uint256 i = 0; i < originConfigs.length; i++) {
      TrustedRemotesConfig memory originConfig = originConfigs[i];
      require(originConfig.originForwarder != address(0), Errors.INVALID_TRUSTED_REMOTE);
      _trustedRemotes[originConfig.originChainId] = originConfig.originForwarder;
      emit SetTrustedRemote(originConfig.originChainId, originConfig.originForwarder);
    }
  }

  /// @inheritdoc IBaseAdapter
  function nativeToInfraChainId(uint256 nativeChainId) public view virtual returns (uint256);

  /// @inheritdoc IBaseAdapter
  function infraToNativeChainId(uint256 infraChainId) public view virtual returns (uint256);

  /// @inheritdoc IBaseAdapter
  function setupPayments() external virtual {}

  /// @inheritdoc IBaseAdapter
  function getTrustedRemoteByChainId(uint256 chainId) external view returns (address) {
    return _trustedRemotes[chainId];
  }

  /**
   * @notice calls CrossChainController to register the bridged payload
   * @param _payload bytes containing the bridged message
   * @param originChainId id of the chain where the message originated
   */
  function _registerReceivedMessage(bytes memory _payload, uint256 originChainId) internal {
    // this method should be always called via call
    require(address(this) == _selfAddress, Errors.DELEGATE_CALL_FORBIDDEN);
    CROSS_CHAIN_CONTROLLER.receiveCrossChainMessage(_payload, originChainId);
  }
}
