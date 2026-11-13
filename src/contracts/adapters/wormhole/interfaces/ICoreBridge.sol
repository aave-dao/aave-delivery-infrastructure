// SPDX-License-Identifier: Apache 2
// Slimmed-down interface of the Wormhole Core bridge.
// Adapted from: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/main/src/interfaces/ICoreBridge.sol
pragma solidity ^0.8.0;

struct GuardianSignature {
  bytes32 r;
  bytes32 s;
  uint8 v;
  uint8 guardianIndex;
}

/**
 * @notice VM = Verified Message, the legacy struct returned by the Core bridge on `parseAndVerifyVM`.
 * @dev finalized VAAs should use the unique (emitterChainId, emitterAddress, sequence) triple for cheap
 *      replay protection.
 */
struct CoreBridgeVM {
  uint8 version;
  uint32 timestamp;
  uint32 nonce;
  uint16 emitterChainId;
  bytes32 emitterAddress;
  uint64 sequence;
  uint8 consistencyLevel;
  bytes payload;
  uint32 guardianSetIndex;
  GuardianSignature[] signatures;
  bytes32 hash;
}

/**
 * @title ICoreBridge
 * @notice interface of the Wormhole Core bridge (aka the Wormhole contract) used by the Wormhole Executor adapter
 */
interface ICoreBridge {
  /**
   * @notice method to get the fee that must be paid as `msg.value` when publishing a message
   * @return the message fee in units of the native currency
   */
  function messageFee() external view returns (uint256);

  /**
   * @notice publishes a message to be attested by the Wormhole guardians
   * @dev requires `msg.value` equal to `messageFee()`
   * @param nonce arbitrary nonce (unused here)
   * @param payload arbitrary message bytes
   * @param consistencyLevel finality level at which the guardians should attest the message
   * @return sequence sequence number of the published message for the calling emitter
   */
  function publishMessage(
    uint32 nonce,
    bytes memory payload,
    uint8 consistencyLevel
  ) external payable returns (uint64 sequence);

  /**
   * @notice parses and verifies the guardian signatures of an encoded VAA
   * @param encodedVM the encoded VAA bytes
   * @return vm the parsed VAA
   * @return valid whether the VAA signatures are valid
   * @return reason failure reason when `valid` is false
   */
  function parseAndVerifyVM(
    bytes calldata encodedVM
  ) external view returns (CoreBridgeVM memory vm, bool valid, string memory reason);

  /**
   * @notice method to get the Wormhole chain id of the chain where this Core bridge is deployed
   * @return the Wormhole chain id
   */
  function chainId() external view returns (uint16);
}
