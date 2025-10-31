// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {CrossChainReceiver} from '../munged/src/contracts/CrossChainReceiver.sol';
import {Envelope, Transaction, TransactionUtils} from '../munged/src/contracts/libs/EncodingUtils.sol';
import {EnumerableSet} from '../munged/src/contracts/interfaces/ICrossChainReceiver.sol';
import {Errors} from '../munged/src/contracts/libs/Errors.sol';
import {IBaseReceiverPortal} from '../munged/src/contracts/interfaces/IBaseReceiverPortal.sol';


abstract contract CrossChainReceiverHarnessAbstract is CrossChainReceiver {
  using EnumerableSet for EnumerableSet.AddressSet;

    bytes malicious_s;
    Transaction transaction_s;
    Envelope envelope_s;
    bool nondet_s;


    function getEnvelopeId(Envelope memory envelope) external returns (bytes32){
        return envelope.getId();
    }   

    function getEncodedTransactionId(bytes memory encodedTransaction) external returns (bytes32) {
        return TransactionUtils.getId(encodedTransaction);

    }


    function getEnvelopeId(bytes memory encodedTransaction) external returns (bytes32) {
        Transaction memory transaction = TransactionUtils.decode(encodedTransaction);
        bytes32 toReturn = transaction.getEnvelopeId();
        return toReturn; 
    }

       
    function getEnvelope(bytes memory encodedTransaction) external returns (Envelope memory) {
        Transaction memory transaction = TransactionUtils.decode(encodedTransaction);
        Envelope memory toReturn = transaction.getEnvelope();
        require(keccak256(abi.encode(toReturn)) == keccak256(transaction.encodedEnvelope));//TODO: check as an assertion on the forwarder
        return toReturn;
    }

    function getConfirmations(bytes32 transactionId) external view returns (uint8) {
            return _transactionsState[transactionId].confirmations;
    }
    function getFirstBridgedAt(bytes32 transactionId) external view returns (uint120) {
            return _transactionsState[transactionId].firstBridgedAt;
    }
    function getValidityTimestamp(uint256 chainId) external view returns (uint120) {
    return _configurationsByChain[chainId].configuration.validityTimestamp;
  }
    function compare(bytes memory b1, bytes memory b2) external pure returns (bool) {
        return keccak256(abi.encodePacked(b1)) == keccak256(abi.encodePacked(b2));
    }

    function compare(bytes32 b1, bytes32 b2) external pure returns (bool) {
        return keccak256(abi.encodePacked(b1)) == keccak256(abi.encodePacked(b2));
    }

    function compare(Envelope memory envelope1, Envelope memory envelope2) external pure returns (bool) {
        return 
                envelope1.nonce == envelope2.nonce 
                && envelope1.origin == envelope2.origin        
                && envelope1.destination == envelope2.destination        
                && envelope1.originChainId == envelope2.originChainId        
                && envelope1.destinationChainId == envelope2.destinationChainId
                && keccak256(abi.encodePacked(envelope1.message)) == keccak256(abi.encodePacked(envelope2.message));
    }

    function getAllowedBridgeAdaptersLength(uint256 chainId) external view returns (uint256){
           return _configurationsByChain[chainId].allowedBridgeAdapters.length();
    }


}

    
