// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IConfigurableAdapter
 * @author Aave Labs
 * @notice Interface for bridge adapters with provider-specific configuration hooks.
 */
interface IConfigurableAdapter {
  /**
   * @notice Applies adapter-specific configuration.
   * @param remoteChainId id of the remote chain this configuration targets.
   * @param data ABI-encoded adapter configuration.
   */
  function config(uint256 remoteChainId, bytes calldata data) external;
}
