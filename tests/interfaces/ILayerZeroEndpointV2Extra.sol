// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/// @dev Subset of the LayerZero V2 endpoint surface used by the LayerZero adapter fork tests.
///      `setSendLibrary` is delegate-gated: it requires the caller to equal the OApp or its
///      registered delegate. When called with a registered library address, the only remaining
///      failure mode is the authorization check, allowing tests to distinguish auth reverts
///      from other reverts by selector.
interface ILayerZeroEndpointV2Extra {
  function delegates(address oapp) external view returns (address);

  function defaultSendLibrary(uint32 eid) external view returns (address);

  function setSendLibrary(address oapp, uint32 eid, address newLib) external;
}
