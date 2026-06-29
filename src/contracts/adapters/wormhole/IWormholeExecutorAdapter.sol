// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWormholeExecutorAdapter
 * @author Aave Labs
 * @notice interface containing the methods definitions used in the Wormhole Executor bridge adapter
 */
interface IWormholeExecutorAdapter {
  /**
   * @notice method to get the Wormhole Core bridge address
   * @return address of the Wormhole Core bridge
   */
  function WORMHOLE_CORE() external view returns (address);

  /**
   * @notice method to get the Wormhole Executor quoter router address
   * @return address of the Wormhole Executor quoter router
   */
  function EXECUTOR_QUOTER_ROUTER() external view returns (address);

  /**
   * @notice method to get the on-chain quoter address of the chosen relay provider
   * @return address of the relay provider quoter
   */
  function QUOTER() external view returns (address);

  /**
   * @notice method to get the refund address on destination chain
   * @return address that will receive the refunds
   * @dev should be CrossChainController on destination chain
   */
  function REFUND_ADDRESS() external view returns (address);

  /**
   * @notice method to get the Wormhole chain id of the chain where this adapter is deployed
   * @return the Wormhole chain id used as the emitter chain of published messages
   */
  function WORMHOLE_SOURCE_CHAIN_ID() external view returns (uint16);

  /**
   * @notice method to get the Wormhole consistency (finality) level used when publishing messages
   * @return the consistency level (chain specific, eg. 202 = finalized on Ethereum, 0 on Monad)
   */
  function CONSISTENCY_LEVEL() external view returns (uint8);
}
