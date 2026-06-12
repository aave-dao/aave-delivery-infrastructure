// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/// @dev Minimal IERC5313-compatible CrossChainController stub used to satisfy adapters that
///      authorize configuration callers against `owner()` on the CCC reference.
contract CCCOwnerStub {
  address public immutable owner;

  constructor(address ownerAddress) {
    owner = ownerAddress;
  }
}
