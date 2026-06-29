// SPDX-License-Identifier: Apache 2
// Adapted from: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/main/src/interfaces/IExecutor.sol
pragma solidity ^0.8.0;

/**
 * @title IVaaV1Receiver
 * @notice required interface for receiving MultiSig (=V1) VAAs from the Wormhole Executor relay provider.
 * @dev the relay provider delivers a message by calling `executeVAAv1` on the destination contract. This
 *      call is permissionless, so the receiving contract MUST verify the VAA via the Core bridge and that
 *      its emitter is a known trusted remote.
 */
interface IVaaV1Receiver {
  /**
   * @notice entry point invoked by the Executor relay provider to deliver an attested message
   * @param multiSigVaa the encoded, guardian-signed VAA
   */
  function executeVAAv1(bytes memory multiSigVaa) external payable;
}
