// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {OpAdapter, IOpAdapter} from '../optimism/OpAdapter.sol';
import {IMantleAdapter} from './IMantleAdapter.sol';

/**
 * @title MantleAdapter
 * @author BGD Labs
 * @notice Mantle bridge adapter. Used to send and receive messages cross chain between Ethereum and Mantle
 * @dev it uses the eth balance of CrossChainController contract to pay for message bridging as the method to bridge
        is called via delegate call
 * @dev note that this adapter can only be used for the communication path ETHEREUM -> MANTLE
 * @dev note that this adapter inherits from Optimism adapter and overrides only supported chain
 * @dev note that max total gas limit is 1M
 */
contract MantleAdapter is OpAdapter, IMantleAdapter {
  /**
   * @param params object containing the necessary parameters to initialize the contract
   */
  constructor(
    MantleParams memory params
  )
    OpAdapter(
      params.crossChainController,
      params.ovmCrossDomainMessenger,
      params.providerGasLimit,
      'Mantle native adapter',
      params.trustedRemotes
    )
  {}

  /// @inheritdoc IOpAdapter
  function isDestinationChainIdSupported(
    uint256 chainId
  ) public view virtual override returns (bool) {
    return chainId == ChainIds.MANTLE;
  }

  /// @inheritdoc IOpAdapter
  function getOriginChainId() public pure virtual override returns (uint256) {
    return ChainIds.ETHEREUM;
  }
}
