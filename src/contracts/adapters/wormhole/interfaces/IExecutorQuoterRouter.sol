// SPDX-License-Identifier: Apache 2
// Adapted from: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/main/src/interfaces/IExecutor.sol
pragma solidity ^0.8.0;

/**
 * @title IExecutorQuoterRouter
 * @notice interface of the Wormhole Executor on-chain quoter router. It is the canonical entry point used
 *         to request an on-chain delivery quote and to request execution (relaying) of a published message.
 * @dev see https://github.com/wormholelabs-xyz/example-messaging-executor
 */
interface IExecutorQuoterRouter {
  /**
   * @notice returns the native fee required to relay a request to `dstChain` using `quoterAddr`
   * @param dstChain destination chain in Wormhole chain id format
   * @param dstAddr destination contract (universal address format) that will receive the message
   * @param refundAddr address that will receive any leftover gas refunds
   * @param quoterAddr the on-chain quoter contract of the chosen relay provider
   * @param requestBytes encoded execution request (eg. a VAA v1 request)
   * @param relayInstructions encoded relay instructions (eg. gas limit)
   * @return the required executor fee in units of the native currency
   */
  function quoteExecution(
    uint16 dstChain,
    bytes32 dstAddr,
    address refundAddr,
    address quoterAddr,
    bytes calldata requestBytes,
    bytes calldata relayInstructions
  ) external view returns (uint256);

  /**
   * @notice requests execution (relaying) of an already published message, paying the executor fee
   * @dev must be called with `msg.value` equal to the value returned by `quoteExecution`
   * @param dstChain destination chain in Wormhole chain id format
   * @param dstAddr destination contract (universal address format) that will receive the message
   * @param refundAddr address that will receive any leftover gas refunds
   * @param quoterAddr the on-chain quoter contract of the chosen relay provider
   * @param requestBytes encoded execution request (eg. a VAA v1 request)
   * @param relayInstructions encoded relay instructions (eg. gas limit)
   */
  function requestExecution(
    uint16 dstChain,
    bytes32 dstAddr,
    address refundAddr,
    address quoterAddr,
    bytes calldata requestBytes,
    bytes calldata relayInstructions
  ) external payable;
}
