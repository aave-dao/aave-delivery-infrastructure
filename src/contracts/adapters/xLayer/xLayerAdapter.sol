// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {BaseAdapter, IBaseAdapter} from '../BaseAdapter.sol';
import {Errors} from '../../libs/Errors.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {OpAdapter, IOpAdapter} from '../optimism/OpAdapter.sol';

/**
 * @param crossChainController address of the cross chain controller that will use this bridge adapter
 * @param ovmCrossDomainMessenger XLayer entry point address
 * @param providerGasLimit base gas limit used by the bridge adapter
 * @param trustedRemotes list of remote configurations to set as trusted
 */
struct XLayerAdapterArgs {
  address crossChainController;
  address ovmCrossDomainMessenger;
  uint256 providerGasLimit;
  IBaseAdapter.TrustedRemotesConfig[] trustedRemotes;
}

/**
 * @title XLayerAdapter
 * @author BGD Labs
 * @notice XLayer bridge adapter. Used to send and receive messages cross chain between Ethereum and XLayer
 * @dev it uses the eth balance of CrossChainController contract to pay for message bridging as the method to bridge
        is called via delegate call
 * @dev note that this adapter can only be used for the communication path ETHEREUM -> XLAYER
 * @dev note that this adapter inherits from Optimism adapter and overrides only supported chain
 */
contract XLayerAdapter is OpAdapter {
  /**
   * @param args XLayerAdapterArgs necessary to initialize the adapter
   */
  constructor(
    XLayerAdapterArgs memory args
  )
    OpAdapter(
      args.crossChainController,
      args.ovmCrossDomainMessenger,
      args.providerGasLimit,
      'XLayer native adapter',
      args.trustedRemotes
    )
  {}

  /// @inheritdoc IOpAdapter
  function isDestinationChainIdSupported(
    uint256 chainId
  ) public view virtual override returns (bool) {
    return chainId == ChainIds.XLAYER;
  }

  /// @inheritdoc IOpAdapter
  function getOriginChainId() public pure virtual override returns (uint256) {
    return ChainIds.ETHEREUM;
  }
}
