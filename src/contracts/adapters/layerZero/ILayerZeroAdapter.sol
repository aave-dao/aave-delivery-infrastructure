// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConfigurableAdapter} from '../interfaces/IConfigurableAdapter.sol';
import {ILayerZeroEndpointV2} from './interfaces/ILayerZeroEndpointV2.sol';

/**
 * @title ILayerZeroAdapter
 * @author BGD Labs
 * @notice interface containing the events, objects and method definitions used in the LayerZero bridge adapter
 */
interface ILayerZeroAdapter is IConfigurableAdapter {
  /**
   * @notice returns the layer zero endpoint address
   * @return LayerZero endpoint address
   */
  function LZ_ENDPOINT() external view returns (ILayerZeroEndpointV2);
}
