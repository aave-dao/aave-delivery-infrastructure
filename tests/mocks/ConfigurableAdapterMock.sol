// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {BaseAdapter, IBaseAdapter} from '../../src/contracts/adapters/BaseAdapter.sol';
import {IConfigurableAdapter} from '../../src/contracts/adapters/interfaces/IConfigurableAdapter.sol';

/// @dev `config` is intended to be invoked via delegatecall from `CrossChainForwarder`;
///      it therefore observes the *caller* storage, so the mock signals back via an event
///      rather than via local state.
contract ConfigurableAdapterMock is BaseAdapter, IConfigurableAdapter {
  event ConfigCalled(uint256 remoteChainId, bytes data, address sender);

  constructor(
    address crossChainController,
    TrustedRemotesConfig[] memory trustedRemotes
  ) BaseAdapter(crossChainController, 0, 'configurable adapter mock', trustedRemotes) {}

  /// @inheritdoc IConfigurableAdapter
  function config(uint256 remoteChainId, bytes calldata data) external override {
    emit ConfigCalled(remoteChainId, data, msg.sender);
  }

  /// @inheritdoc IBaseAdapter
  function forwardMessage(
    address,
    uint256,
    uint256,
    bytes memory
  ) external pure returns (address, uint256) {
    return (address(0), 0);
  }

  /// @inheritdoc IBaseAdapter
  function nativeToInfraChainId(uint256 x) public pure override returns (uint256) {
    return x;
  }

  /// @inheritdoc IBaseAdapter
  function infraToNativeChainId(uint256 x) public pure override returns (uint256) {
    return x;
  }
}

contract RevertingConfigurableAdapterMock is BaseAdapter, IConfigurableAdapter {
  constructor(
    address crossChainController,
    TrustedRemotesConfig[] memory trustedRemotes
  ) BaseAdapter(crossChainController, 0, 'reverting configurable adapter mock', trustedRemotes) {}

  /// @inheritdoc IConfigurableAdapter
  /// @dev reverts with empty returndata so `Address.functionDelegateCall` falls back to the provided error message.
  function config(uint256, bytes calldata) external pure override {
    assembly {
      revert(0, 0)
    }
  }

  /// @inheritdoc IBaseAdapter
  function forwardMessage(
    address,
    uint256,
    uint256,
    bytes memory
  ) external pure returns (address, uint256) {
    return (address(0), 0);
  }

  /// @inheritdoc IBaseAdapter
  function nativeToInfraChainId(uint256 x) public pure override returns (uint256) {
    return x;
  }

  /// @inheritdoc IBaseAdapter
  function infraToNativeChainId(uint256 x) public pure override returns (uint256) {
    return x;
  }
}
