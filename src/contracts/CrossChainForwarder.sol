// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {OwnableWithGuardian} from './old-oz/OwnableWithGuardian.sol';
import {Address} from './old-oz/Address.sol';

import {ICrossChainForwarder} from './interfaces/ICrossChainForwarder.sol';
import {IBaseAdapter} from './adapters/IBaseAdapter.sol';
import {IConfigurableAdapter} from './adapters/interfaces/IConfigurableAdapter.sol';
import {Transaction, EncodedTransaction, Envelope, EncodedEnvelope, TransactionUtils} from './libs/EncodingUtils.sol';
import {Errors} from './libs/Errors.sol';
import {Utils} from './libs/Utils.sol';

/**
 * @title CrossChainForwarder
 * @author BGD Labs
 * @notice this contract contains the methods used to forward messages to different chains
 *         using registered bridge adapters.
 * @dev To be able to forward a message, caller needs to be an approved sender.
 */
contract CrossChainForwarder is OwnableWithGuardian, ICrossChainForwarder {
  // every message originator sends we put into an envelope and attach a nonce. It increments by one
  uint256 internal _currentEnvelopeNonce;

  // for every new bridging attempt of an envelope we attach a txId, that will be unique for every attempt. It increments by one
  // the rationality behind - is to be able to deliver envelope anyways, even if destination chain infra will be invalidated
  // so, we will be able to retry the envelope with the same nonce once it will recover
  uint256 internal _currentTransactionNonce;

  // specifies if an address is approved to forward messages
  mapping(address => bool) internal _approvedSenders;

  // Stores messages accepted from origin. hash(destinationChainId + (envelopeNonce, origin, destination, message)).
  // This is used to check if an envelop can be retried, in case one or more of bridges was out of gas at the forwardMessage call
  mapping(bytes32 => bool) internal _registeredEnvelopes;

  // Stores transactions sent. hash(transactionNonce, envelopeId).
  // This is used to check if a transaction can be retried
  // in a case when during the confirmation by recipient the recipient infrastructure got invalidated
  mapping(bytes32 => bool) internal _forwardedTransactions;

  // (chainId => chain configuration) list of bridge adapter configurations for a chain
  mapping(uint256 => ChainIdBridgeConfig[]) internal _bridgeAdaptersByChain;

  // configuration to limit bandwidth to only send via X bridge adapters out of the total allowed bridge adapters for
  // the specified chain
  // chainId => optimalBandwidth
  mapping(uint256 => uint256) internal _optimalBandwidthByChain;

  // storage gap allocation to be used for later updates. This way storage can be added on parent contract without
  // overwriting storage on child
  uint256[49] private __FORWARDER_GAP;

  // checks if caller is an approved sender
  modifier onlyApprovedSenders() {
    require(isSenderApproved(msg.sender), Errors.CALLER_IS_NOT_APPROVED_SENDER);
    _;
  }

  /**
   * @param bridgeAdaptersToEnable list of bridge adapter configurations to enable
   * @param sendersToApprove list of addresses to approve to forward messages
   */
  constructor(
    ForwarderBridgeAdapterConfigInput[] memory bridgeAdaptersToEnable,
    address[] memory sendersToApprove,
    OptimalBandwidthByChain[] memory optimalBandwidthByChain
  ) {
    _configureForwarderBasics(
      bridgeAdaptersToEnable,
      new BridgeAdapterToDisable[](0),
      sendersToApprove,
      new address[](0),
      optimalBandwidthByChain
    );
  }

  /// @inheritdoc ICrossChainForwarder
  function getOptimalBandwidthByChain(uint256 chainId) external view returns (uint256) {
    return _optimalBandwidthByChain[chainId];
  }

  /// @inheritdoc ICrossChainForwarder
  function getCurrentEnvelopeNonce() external view returns (uint256) {
    return _currentEnvelopeNonce;
  }

  /// @inheritdoc ICrossChainForwarder
  function getCurrentTransactionNonce() external view returns (uint256) {
    return _currentTransactionNonce;
  }

  /// @inheritdoc ICrossChainForwarder
  function isSenderApproved(address sender) public view returns (bool) {
    return _approvedSenders[sender];
  }

  /// @inheritdoc ICrossChainForwarder
  function isEnvelopeRegistered(Envelope memory envelope) public view returns (bool) {
    return isEnvelopeRegistered(envelope.getId());
  }

  /// @inheritdoc ICrossChainForwarder
  function isEnvelopeRegistered(bytes32 envelopeId) public view returns (bool) {
    return _registeredEnvelopes[envelopeId];
  }

  /// @inheritdoc ICrossChainForwarder
  function isTransactionForwarded(Transaction memory transaction) public view returns (bool) {
    return isTransactionForwarded(transaction.getId());
  }

  /// @inheritdoc ICrossChainForwarder
  function isTransactionForwarded(bytes32 transactionId) public view returns (bool) {
    return _forwardedTransactions[transactionId];
  }

  /// @inheritdoc ICrossChainForwarder
  function forwardMessage(
    uint256 destinationChainId,
    address destination,
    uint256 gasLimit,
    bytes memory message
  ) external onlyApprovedSenders returns (bytes32, bytes32) {
    ChainIdBridgeConfig[] memory bridgeAdapters = _getShuffledBridgeAdaptersByChain(
      destinationChainId
    );
    require(bridgeAdapters.length > 0, Errors.NO_BRIDGE_ADAPTERS_FOR_SPECIFIED_CHAIN);

    uint256 envelopeNonce = _currentEnvelopeNonce++;

    Envelope memory envelope = Envelope({
      nonce: envelopeNonce,
      origin: msg.sender,
      destination: destination,
      originChainId: block.chainid,
      destinationChainId: destinationChainId,
      message: message
    });
    EncodedEnvelope memory encodedEnvelope = envelope.encode();
    // save accepted envelope for future retries in case one ore more bridges will not deliver the message to the destination
    _registeredEnvelopes[encodedEnvelope.id] = true;
    emit EnvelopeRegistered(encodedEnvelope.id, envelope);

    EncodedTransaction memory encodedTransaction = (
      Transaction({nonce: _currentTransactionNonce++, encodedEnvelope: encodedEnvelope.data})
    ).encode();

    _forwardedTransactions[encodedTransaction.id] = true;

    _bridgeTransaction(
      encodedEnvelope.id,
      encodedTransaction.id,
      encodedTransaction.data,
      envelope.destinationChainId,
      gasLimit,
      bridgeAdapters
    );
    return (encodedEnvelope.id, encodedTransaction.id);
  }

  /// @inheritdoc ICrossChainForwarder
  function retryEnvelope(
    Envelope memory envelope,
    uint256 gasLimit
  ) external onlyOwnerOrGuardian returns (bytes32) {
    EncodedEnvelope memory encodedEnvelope = envelope.encode();

    // Message can be retried only if it was sent before with exactly the same parameters
    require(isEnvelopeRegistered(encodedEnvelope.id), Errors.ENVELOPE_NOT_PREVIOUSLY_REGISTERED);

    // As envelope has not ben previously sent, we need to get the optimalBandwidth shuffled bridge adapters array again.
    ChainIdBridgeConfig[] memory bridgeAdapters = _getShuffledBridgeAdaptersByChain(
      envelope.destinationChainId
    );
    require(bridgeAdapters.length > 0, Errors.NO_BRIDGE_ADAPTERS_FOR_SPECIFIED_CHAIN);

    EncodedTransaction memory encodedTransaction = (
      Transaction({nonce: _currentTransactionNonce++, encodedEnvelope: encodedEnvelope.data})
    ).encode();

    _forwardedTransactions[encodedTransaction.id] = true;

    _bridgeTransaction(
      encodedEnvelope.id,
      encodedTransaction.id,
      encodedTransaction.data,
      envelope.destinationChainId,
      gasLimit,
      bridgeAdapters
    );

    return encodedTransaction.id;
  }

  /// @inheritdoc ICrossChainForwarder
  function retryTransaction(
    bytes memory encodedTransaction,
    uint256 gasLimit,
    address[] memory bridgeAdaptersToRetry
  ) external onlyOwnerOrGuardian {
    bytes32 transactionId = TransactionUtils.getId(encodedTransaction);
    // Transaction can be retried only if it was sent before with exactly the same parameters
    require(isTransactionForwarded(transactionId), Errors.TRANSACTION_NOT_PREVIOUSLY_FORWARDED);

    Transaction memory transaction = TransactionUtils.decode(encodedTransaction);
    Envelope memory envelope = transaction.getEnvelope();

    ChainIdBridgeConfig[] memory registeredBridgeAdapters = _bridgeAdaptersByChain[
      envelope.destinationChainId
    ];
    require(registeredBridgeAdapters.length > 0, Errors.NO_BRIDGE_ADAPTERS_FOR_SPECIFIED_CHAIN);

    ChainIdBridgeConfig[] memory bridgeAdaptersToRetryConfig = new ChainIdBridgeConfig[](
      bridgeAdaptersToRetry.length
    );

    for (uint256 i = 0; i < bridgeAdaptersToRetry.length; i++) {
      // check that we're not sending 2 times to the same adapter
      for (uint256 j = i + 1; j < bridgeAdaptersToRetry.length; j++) {
        require(
          bridgeAdaptersToRetry[i] != bridgeAdaptersToRetry[j],
          Errors.BRIDGE_ADAPTERS_SHOULD_BE_UNIQUE
        );
      }

      // check that adapter is valid for this networkId
      bool isAdapterRegistered = false;
      for (uint256 j = 0; j < registeredBridgeAdapters.length; j++) {
        if (bridgeAdaptersToRetry[i] == registeredBridgeAdapters[j].currentChainBridgeAdapter) {
          bridgeAdaptersToRetryConfig[i] = registeredBridgeAdapters[j];
          isAdapterRegistered = true;
          break;
        }
      }
      require(isAdapterRegistered, Errors.INVALID_BRIDGE_ADAPTER);
    }

    bool isBridgedAtLeastOnce = _bridgeTransaction(
      transaction.getEnvelopeId(),
      transactionId,
      encodedTransaction,
      envelope.destinationChainId,
      gasLimit,
      bridgeAdaptersToRetryConfig
    );
    require(isBridgedAtLeastOnce, Errors.TRANSACTION_RETRY_FAILED);
  }

  /// @inheritdoc ICrossChainForwarder
  function getForwarderBridgeAdaptersByChain(
    uint256 chainId
  ) external view returns (ChainIdBridgeConfig[] memory) {
    return _bridgeAdaptersByChain[chainId];
  }

  /// @inheritdoc ICrossChainForwarder
  function approveSenders(address[] memory senders) external onlyOwner {
    _updateSenders(senders, true);
  }

  /// @inheritdoc ICrossChainForwarder
  function removeSenders(address[] memory senders) external onlyOwner {
    _updateSenders(senders, false);
  }

  /// @inheritdoc ICrossChainForwarder
  function enableBridgeAdapters(
    ForwarderBridgeAdapterConfigInput[] memory bridgeAdapters
  ) external onlyOwner {
    _enableBridgeAdapters(bridgeAdapters);
  }

  /// @inheritdoc ICrossChainForwarder
  function disableBridgeAdapters(
    BridgeAdapterToDisable[] memory bridgeAdapters
  ) external onlyOwner {
    _disableBridgeAdapters(bridgeAdapters);
  }

  /// @inheritdoc ICrossChainForwarder
  function configBridgeAdapters(
    BridgeAdapterConfig[] memory bridgeAdapterConfigs
  ) external onlyOwner {
    _configBridgeAdapters(bridgeAdapterConfigs);
  }

  /// @inheritdoc ICrossChainForwarder
  function updateOptimalBandwidthByChain(
    OptimalBandwidthByChain[] memory optimalBandwidthByChain
  ) external onlyOwner {
    _updateOptimalBandwidthByChain(optimalBandwidthByChain);
  }

  /**
   * @notice method to get a shuffled array of forwarder bridge adapters configurations
   * @param destinationChainId id of the destination chain to get the adapters that communicate to it
   * @return a shuffled array of the forwarder configurations for a destination chain
   */
  function _getShuffledBridgeAdaptersByChain(
    uint256 destinationChainId
  ) internal view returns (ChainIdBridgeConfig[] memory) {
    uint256 optimalBandwidth = _optimalBandwidthByChain[destinationChainId];
    ChainIdBridgeConfig[] storage forwarderAdapters = _bridgeAdaptersByChain[destinationChainId];

    // If configured optimal bandwidth for a destination network are set to 0 or are bigger than current adapters,
    // it will use all the adapters available. This way there would be no way of breaking forwarding communication
    // by setting wrong configuration.
    if (optimalBandwidth == 0 || optimalBandwidth >= forwarderAdapters.length) {
      return forwarderAdapters;
    }

    uint256[] memory shuffledIndexes = Utils.shuffleArray(
      Utils.generateIndexArray(forwarderAdapters.length),
      optimalBandwidth
    );

    ChainIdBridgeConfig[] memory selectedForwarderAdapters = new ChainIdBridgeConfig[](
      optimalBandwidth
    );

    for (uint256 i = 0; i < optimalBandwidth; i++) {
      selectedForwarderAdapters[i] = forwarderAdapters[shuffledIndexes[i]];
    }

    return selectedForwarderAdapters;
  }

  /**
   * @notice internal method that has the logic to forward a transaction to the specified chain
   * @param envelopeId the id of the envelope
   * @param transactionId id of the transaction to bridge
   * @param encodedTransaction the encoded Transaction data
   * @param destinationChainId id of the chain where the transaction needs to be forwarded to
   * @param gasLimit limit of gas to spend on forwarding per bridge
   * @param bridgeAdapters list of bridge adapters to be used for the transaction forwarding
   * @return flag indicating if transaction has been forwarded at least once. The transaction id
   */
  function _bridgeTransaction(
    bytes32 envelopeId,
    bytes32 transactionId,
    bytes memory encodedTransaction,
    uint256 destinationChainId,
    uint256 gasLimit,
    ChainIdBridgeConfig[] memory bridgeAdapters
  ) internal returns (bool) {
    bool isForwardedAtLeastOnce = false;
    for (uint256 i = 0; i < bridgeAdapters.length; i++) {
      (bool success, bytes memory returnData) = bridgeAdapters[i]
        .currentChainBridgeAdapter
        .delegatecall(
          abi.encodeWithSelector(
            IBaseAdapter.forwardMessage.selector,
            bridgeAdapters[i].destinationBridgeAdapter,
            gasLimit,
            destinationChainId,
            encodedTransaction
          )
        );

      if (success) {
        isForwardedAtLeastOnce = true;
      } else {
        // it doesn't revert as sending to other bridges might succeed
      }
      emit TransactionForwardingAttempted(
        transactionId,
        envelopeId,
        encodedTransaction,
        destinationChainId,
        bridgeAdapters[i].currentChainBridgeAdapter,
        bridgeAdapters[i].destinationBridgeAdapter,
        success,
        returnData
      );
    }

    return (isForwardedAtLeastOnce);
  }

  /**
   * @notice method to enable bridge adapters
   * @param bridgeAdapters array of new bridge adapter configurations
   */
  function _enableBridgeAdapters(
    ForwarderBridgeAdapterConfigInput[] memory bridgeAdapters
  ) internal {
    for (uint256 i = 0; i < bridgeAdapters.length; i++) {
      ForwarderBridgeAdapterConfigInput memory bridgeAdapterConfigInput = bridgeAdapters[i];

      require(
        bridgeAdapterConfigInput.destinationBridgeAdapter != address(0) &&
          bridgeAdapterConfigInput.currentChainBridgeAdapter != address(0),
        Errors.CURRENT_OR_DESTINATION_CHAIN_ADAPTER_NOT_SET
      );
      ChainIdBridgeConfig[] storage bridgeAdapterConfigs = _bridgeAdaptersByChain[
        bridgeAdapterConfigInput.destinationChainId
      ];
      bool configFound;
      // check that we don't push same config twice.
      for (uint256 j = 0; j < bridgeAdapterConfigs.length; j++) {
        ChainIdBridgeConfig storage bridgeAdapterConfig = bridgeAdapterConfigs[j];

        if (
          bridgeAdapterConfig.currentChainBridgeAdapter ==
          bridgeAdapterConfigInput.currentChainBridgeAdapter
        ) {
          if (
            bridgeAdapterConfig.destinationBridgeAdapter !=
            bridgeAdapterConfigInput.destinationBridgeAdapter
          ) {
            bridgeAdapterConfig.destinationBridgeAdapter = bridgeAdapterConfigInput
              .destinationBridgeAdapter;

            emit BridgeAdapterUpdated(
              bridgeAdapterConfigInput.destinationChainId,
              bridgeAdapterConfigInput.currentChainBridgeAdapter,
              bridgeAdapterConfigInput.destinationBridgeAdapter,
              true
            );
          }
          configFound = true;
          break;
        }
      }

      if (!configFound) {
        // preparing fees stream
        Address.functionDelegateCall(
          bridgeAdapterConfigInput.currentChainBridgeAdapter,
          abi.encodeWithSelector(IBaseAdapter.setupPayments.selector),
          Errors.ADAPTER_PAYMENT_SETUP_FAILED
        );

        bridgeAdapterConfigs.push(
          ChainIdBridgeConfig({
            destinationBridgeAdapter: bridgeAdapterConfigInput.destinationBridgeAdapter,
            currentChainBridgeAdapter: bridgeAdapterConfigInput.currentChainBridgeAdapter
          })
        );

        emit BridgeAdapterUpdated(
          bridgeAdapterConfigInput.destinationChainId,
          bridgeAdapterConfigInput.currentChainBridgeAdapter,
          bridgeAdapterConfigInput.destinationBridgeAdapter,
          true
        );
      }
    }
  }

  /**
   * @notice method to disable bridge adapters
   * @param bridgeAdaptersToDisable array of bridge adapter addresses to disable
   */
  function _disableBridgeAdapters(
    BridgeAdapterToDisable[] memory bridgeAdaptersToDisable
  ) internal {
    for (uint256 i = 0; i < bridgeAdaptersToDisable.length; i++) {
      for (uint256 j = 0; j < bridgeAdaptersToDisable[i].chainIds.length; j++) {
        ChainIdBridgeConfig[] storage bridgeAdapterConfigs = _bridgeAdaptersByChain[
          bridgeAdaptersToDisable[i].chainIds[j]
        ];

        for (uint256 k = 0; k < bridgeAdapterConfigs.length; k++) {
          if (
            bridgeAdapterConfigs[k].currentChainBridgeAdapter ==
            bridgeAdaptersToDisable[i].bridgeAdapter
          ) {
            address destinationBridgeAdapter = bridgeAdapterConfigs[k].destinationBridgeAdapter;

            bridgeAdapterConfigs[k] = bridgeAdapterConfigs[bridgeAdapterConfigs.length - 1];
            bridgeAdapterConfigs.pop();

            emit BridgeAdapterUpdated(
              bridgeAdaptersToDisable[i].chainIds[j],
              bridgeAdaptersToDisable[i].bridgeAdapter,
              destinationBridgeAdapter,
              false
            );
            break;
          }
        }
      }
    }
  }

  function _configBridgeAdapters(BridgeAdapterConfig[] memory bridgeAdapterConfigs) internal {
    for (uint256 i = 0; i < bridgeAdapterConfigs.length; i++) {
      BridgeAdapterConfig memory bridgeAdapterConfig = bridgeAdapterConfigs[i];
      ChainIdBridgeConfig[] memory bridgeAdapters = _bridgeAdaptersByChain[
        bridgeAdapterConfig.destinationChainId
      ];
      bool adapterRegistered;
      for (uint256 j = 0; j < bridgeAdapters.length; j++) {
        if (bridgeAdapters[j].currentChainBridgeAdapter == bridgeAdapterConfig.bridgeAdapter) {
          adapterRegistered = true;
          break;
        }
      }
      require(adapterRegistered, Errors.CONFIGURABLE_ADAPTER_NOT_REGISTERED);

      Address.functionDelegateCall(
        bridgeAdapterConfig.bridgeAdapter,
        abi.encodeWithSelector(
          IConfigurableAdapter.config.selector,
          bridgeAdapterConfig.destinationChainId,
          bridgeAdapterConfig.data
        ),
        Errors.ADAPTER_CONFIG_FAILED
      );

      emit BridgeAdapterConfigured(
        bridgeAdapterConfig.destinationChainId,
        bridgeAdapterConfig.bridgeAdapter,
        bridgeAdapterConfig.data
      );
    }
  }

  /**
   * @notice method to approve or disapprove a list of senders
   * @param senders list of addresses to update
   * @param newState indicates if the list of senders will be approved or disapproved
   */
  function _updateSenders(address[] memory senders, bool newState) internal {
    for (uint256 i = 0; i < senders.length; i++) {
      require(senders[i] != address(0), Errors.INVALID_SENDER);
      _approvedSenders[senders[i]] = newState;
      emit SenderUpdated(senders[i], newState);
    }
  }

  /**
  * @notice method to update the optimal bandwidth of a receiver chain
  * @param optimalBandwidthByChain array of objects containing the optimal bandwidth for a specified receiver chain id
  * @dev Setting optimal bandwidth to 0 means that no optimization will be applied, so all allowed bridges will be used to
         forward a message.
  */
  function _updateOptimalBandwidthByChain(
    OptimalBandwidthByChain[] memory optimalBandwidthByChain
  ) internal {
    for (uint256 i = 0; i < optimalBandwidthByChain.length; i++) {
      _optimalBandwidthByChain[optimalBandwidthByChain[i].chainId] = optimalBandwidthByChain[i]
        .optimalBandwidth;

      emit OptimalBandwidthUpdated(
        optimalBandwidthByChain[i].chainId,
        optimalBandwidthByChain[i].optimalBandwidth
      );
    }
  }

  /// @dev utility function, defining an order of actions commonly done in batch
  function _configureForwarderBasics(
    ForwarderBridgeAdapterConfigInput[] memory bridgesToEnable,
    BridgeAdapterToDisable[] memory bridgesToDisable,
    address[] memory sendersToEnable,
    address[] memory sendersToDisable,
    OptimalBandwidthByChain[] memory optimalBandwidthByChain
  ) internal {
    _enableBridgeAdapters(bridgesToEnable);
    _disableBridgeAdapters(bridgesToDisable);
    _updateSenders(sendersToEnable, true);
    _updateSenders(sendersToDisable, false);
    _updateOptimalBandwidthByChain(optimalBandwidthByChain);
  }
}
