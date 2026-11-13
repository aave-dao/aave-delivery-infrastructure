// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {ICoreBridge, CoreBridgeVM} from './interfaces/ICoreBridge.sol';
import {IExecutorQuoterRouter} from './interfaces/IExecutorQuoterRouter.sol';
import {IVaaV1Receiver} from './interfaces/IVaaV1Receiver.sol';
import {IWormholeExecutorAdapter} from './IWormholeExecutorAdapter.sol';
import {BaseAdapter, IBaseAdapter} from '../BaseAdapter.sol';

import {Errors} from '../../libs/Errors.sol';
import {WormholeExecutorEncoding} from './libs/WormholeExecutorEncoding.sol';


/**
 * @title WormholeExecutorAdapter
 * @author Aave Labs
 * @notice Wormhole bridge adapter built on the Wormhole Executor framework. Used to send and receive
 *         messages cross chain on networks that do not have the legacy Wormhole standard relayer
 *         (eg. Monad).
 * @dev to bridge a message it publishes it to the Wormhole Core bridge and requests its relaying via the
 *      Executor quoter router using an on-chain quote. It uses the eth balance of the CrossChainController
 *      contract to pay for message bridging as `forwardMessage` is called via delegate call.
 * @dev delivery on the destination chain is permissionless (anyone may call `executeVAAv1`), so the
 *      received VAA is verified against the Wormhole Core bridge and its emitter checked against the
 *      configured trusted remotes.
 */
contract WormholeExecutorAdapter is BaseAdapter, IWormholeExecutorAdapter, IVaaV1Receiver {
  using WormholeExecutorEncoding for *;

  /// @inheritdoc IWormholeExecutorAdapter
  address public immutable WORMHOLE_CORE;

  /// @inheritdoc IWormholeExecutorAdapter
  address public immutable EXECUTOR_QUOTER_ROUTER;

  /// @inheritdoc IWormholeExecutorAdapter
  address public immutable QUOTER;

  /// @inheritdoc IWormholeExecutorAdapter
  address public immutable REFUND_ADDRESS;

  /// @inheritdoc IWormholeExecutorAdapter
  uint16 public immutable WORMHOLE_SOURCE_CHAIN_ID;

  /// @inheritdoc IWormholeExecutorAdapter
  uint8 public constant CONSISTENCY_LEVEL = 202;

  /**
   * @param crossChainController address of the cross chain controller that will use this bridge adapter
   * @param wormholeCore Wormhole Core bridge entry point address
   * @param executorQuoterRouter Wormhole Executor on-chain quoter router address
   * @param quoter on-chain quoter address of the chosen relay provider
   * @param refundAddress address that will receive left over gas on destination
   * @param providerGasLimit base gas limit used by the bridge adapter
   * @param trustedRemotes list of remote configurations to set as trusted
   */
  constructor(
    address crossChainController,
    address wormholeCore,
    address executorQuoterRouter,
    address quoter,
    address refundAddress,
    uint256 providerGasLimit,
    TrustedRemotesConfig[] memory trustedRemotes
  )
    BaseAdapter(crossChainController, providerGasLimit, 'Wormhole Executor adapter', trustedRemotes)
  {
    require(wormholeCore != address(0), Errors.WORMHOLE_CORE_CANT_BE_ADDRESS_0);
    require(executorQuoterRouter != address(0), Errors.WORMHOLE_QUOTER_ROUTER_CANT_BE_ADDRESS_0);
    require(quoter != address(0), Errors.WORMHOLE_QUOTER_CANT_BE_ADDRESS_0);
    WORMHOLE_CORE = wormholeCore;
    EXECUTOR_QUOTER_ROUTER = executorQuoterRouter;
    QUOTER = quoter;
    REFUND_ADDRESS = refundAddress;
    WORMHOLE_SOURCE_CHAIN_ID = ICoreBridge(wormholeCore).chainId();
  }

  /// @inheritdoc IBaseAdapter
  function forwardMessage(
    address receiver,
    uint256 executionGasLimit,
    uint256 destinationChainId,
    bytes calldata message
  ) external returns (address, uint256) {
    uint16 nativeChainId = SafeCast.toUint16(infraToNativeChainId(destinationChainId));
    require(nativeChainId != uint16(0), Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED);
    require(receiver != address(0), Errors.RECEIVER_NOT_SET);

    bytes memory relayInstructions = WormholeExecutorEncoding.encodeGas(
      SafeCast.toUint128(executionGasLimit + BASE_GAS_LIMIT),
      0
    );

    uint64 sequence = _publishAndRequest(
      nativeChainId,
      bytes32(uint256(uint160(receiver))),
      relayInstructions,
      message
    );

    return (EXECUTOR_QUOTER_ROUTER, uint256(sequence));
  }

  /**
   * @notice Publishes the message to the Wormhole Core bridge and requests its relaying via the Executor
   * @return sequence the Wormhole sequence number of the published message
   */
  function _publishAndRequest(
    uint16 nativeChainId,
    bytes32 dstAddr,
    bytes memory relayInstructions,
    bytes calldata message
  ) private returns (uint64 sequence) {
    bytes32 emitter = bytes32(uint256(uint160(address(this))));

    // quote using a placeholder sequence: the executor fee does not depend on the sequence number
    uint256 executorFee = IExecutorQuoterRouter(EXECUTOR_QUOTER_ROUTER).quoteExecution(
      nativeChainId,
      dstAddr,
      REFUND_ADDRESS,
      QUOTER,
      WormholeExecutorEncoding.encodeVaaMultiSigRequest(WORMHOLE_SOURCE_CHAIN_ID, emitter, 0),
      relayInstructions
    );

    uint256 messageFee = ICoreBridge(WORMHOLE_CORE).messageFee();
    require(
      executorFee + messageFee <= address(this).balance,
      Errors.NOT_ENOUGH_VALUE_TO_PAY_BRIDGE_FEES
    );

    // the message is the a.DI Transaction envelope, which already carries the destination chain id and is
    // validated by the destination CrossChainController, so it is published as-is
    sequence = ICoreBridge(WORMHOLE_CORE).publishMessage{value: messageFee}(
      0, // nonce, unused (uniqueness comes from the auto-incremented sequence)
      message,
      CONSISTENCY_LEVEL
    );

    IExecutorQuoterRouter(EXECUTOR_QUOTER_ROUTER).requestExecution{value: executorFee}(
      nativeChainId,
      dstAddr,
      REFUND_ADDRESS,
      QUOTER,
      WormholeExecutorEncoding.encodeVaaMultiSigRequest(WORMHOLE_SOURCE_CHAIN_ID, emitter, sequence),
      relayInstructions
    );
  }

  /// @inheritdoc IVaaV1Receiver
  function executeVAAv1(bytes memory multiSigVaa) external payable {
    (CoreBridgeVM memory vm, bool valid, string memory reason) = ICoreBridge(WORMHOLE_CORE)
      .parseAndVerifyVM(multiSigVaa);
    require(valid, bytes(reason).length == 0 ? Errors.INVALID_VAA : reason);

    address srcAddress = address(uint160(uint256(vm.emitterAddress)));
    uint256 originChainId = nativeToInfraChainId(vm.emitterChainId);
    require(
      _trustedRemotes[originChainId] == srcAddress && srcAddress != address(0),
      Errors.REMOTE_NOT_TRUSTED
    );

    // delivery via `executeVAAv1` is permissionless, but the CrossChainController deduplicates messages
    // per adapter and validates the envelope's destination chain id, so no extra replay/destination guard
    // is needed here
    _registerReceivedMessage(vm.payload, originChainId);
  }

  /// @inheritdoc IBaseAdapter
  function nativeToInfraChainId(
    uint256 nativeChainId
  ) public pure virtual override returns (uint256) {
    if (nativeChainId == 2) {
      return ChainIds.ETHEREUM;
    } else if (nativeChainId == 4) {
      return ChainIds.BNB;
    } else if (nativeChainId == 5) {
      return ChainIds.POLYGON;
    } else if (nativeChainId == 6) {
      return ChainIds.AVALANCHE;
    } else if (nativeChainId == 14) {
      return ChainIds.CELO;
    } else if (nativeChainId == 23) {
      return ChainIds.ARBITRUM;
    } else if (nativeChainId == 24) {
      return ChainIds.OPTIMISM;
    } else if (nativeChainId == 30) {
      return ChainIds.BASE;
    } else if (nativeChainId == 34) {
      return ChainIds.SCROLL;
    } else if (nativeChainId == 35) {
      return ChainIds.MANTLE;
    } else if (nativeChainId == 37) {
      return ChainIds.XLAYER;
    } else if (nativeChainId == 38) {
      return ChainIds.LINEA;
    } else if (nativeChainId == 46) {
      return ChainIds.INK;
    } else if (nativeChainId == 48) {
      return ChainIds.MONAD;
    } else if (nativeChainId == 52) {
      return ChainIds.SONIC;
    } else if (nativeChainId == 58) {
      return ChainIds.PLASMA;
    } else if (nativeChainId == 64) {
      return ChainIds.MEGAETH;
    } else {
      return 0;
    }
  }

  /// @inheritdoc IBaseAdapter
  function infraToNativeChainId(
    uint256 infraChainId
  ) public pure virtual override returns (uint256) {
    if (infraChainId == ChainIds.ETHEREUM) {
      return 2;
    } else if (infraChainId == ChainIds.BNB) {
      return 4;
    } else if (infraChainId == ChainIds.POLYGON) {
      return 5;
    } else if (infraChainId == ChainIds.AVALANCHE) {
      return 6;
    } else if (infraChainId == ChainIds.CELO) {
      return 14;
    } else if (infraChainId == ChainIds.ARBITRUM) {
      return 23;
    } else if (infraChainId == ChainIds.OPTIMISM) {
      return 24;
    } else if (infraChainId == ChainIds.BASE) {
      return 30;
    } else if (infraChainId == ChainIds.SCROLL) {
      return 34;
    } else if (infraChainId == ChainIds.MANTLE) {
      return 35;
    } else if (infraChainId == ChainIds.XLAYER) {
      return 37;
    } else if (infraChainId == ChainIds.LINEA) {
      return 38;
    } else if (infraChainId == ChainIds.INK) {
      return 46;
    } else if (infraChainId == ChainIds.MONAD) {
      return 48;
    } else if (infraChainId == ChainIds.SONIC) {
      return 52;
    } else if (infraChainId == ChainIds.PLASMA) {
      return 58;
    } else if (infraChainId == ChainIds.MEGAETH) {
      return 64;
    } else {
      return 0;
    }
  }
}
