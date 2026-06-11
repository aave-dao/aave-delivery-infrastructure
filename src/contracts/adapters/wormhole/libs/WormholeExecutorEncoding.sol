// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title WormholeExecutorEncoding
 * @notice Minimal encoders for the Wormhole Executor relay request and relay instructions.
 * @dev Mirrors `RelayInstructionLib`/`RequestLib` from the wormhole-solidity-sdk so the off-chain relay
 *      providers can parse the request. Kept local to avoid pulling the whole SDK as a dependency.
 */
library WormholeExecutorEncoding {
  // recv instruction type for a plain gas limit (+ optional msg value) on the destination chain
  uint8 internal constant RECV_INST_TYPE_GAS = 1;
  // request type for a MultiSig (=V1) VAA
  bytes4 internal constant REQ_VAA_V1 = 'ERV1';

  function encodeGas(uint128 gasLimit, uint128 msgValue) internal pure returns (bytes memory) {
    return abi.encodePacked(RECV_INST_TYPE_GAS, gasLimit, msgValue);
  }

  function encodeVaaMultiSigRequest(
    uint16 emitterChain,
    bytes32 emitterAddress,
    uint64 sequence
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(REQ_VAA_V1, emitterChain, emitterAddress, sequence);
  }
}
