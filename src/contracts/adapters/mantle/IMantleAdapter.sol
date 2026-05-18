// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IBaseAdapter} from '../IBaseAdapter.sol';

/**
 * @title IMantleAdapter
 * @author BGD Labs
 * @notice interface containing the events, objects and method definitions used in the Mantle bridge adapter
 */
interface IMantleAdapter is IBaseAdapter {
  /**
   * @notice struct used to pass parameters to the Mantle constructor
   * @param crossChainController address of the cross chain controller that will use this bridge adapter
   * @param ovmCrossDomainMessenger Mantle entry point address
   * @param providerGasLimit base gas limit used by the bridge adapter
   * @param trustedRemotes list of remote configurations to set as trusted
   */
  struct MantleParams {
    address crossChainController;
    address ovmCrossDomainMessenger;
    uint256 providerGasLimit;
    TrustedRemotesConfig[] trustedRemotes;
  }
}
