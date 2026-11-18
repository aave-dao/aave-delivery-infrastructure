// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {CrossChainForwarder} from "../munged/src/contracts/CrossChainForwarder.sol";
//import {Envelope} from '../munged/src/contracts/libs/EncodingUtils.sol';
import {Transaction, EncodedTransaction, Envelope, EncodedEnvelope, TransactionUtils, EnvelopeUtils} from '../munged/src/contracts/libs/EncodingUtils.sol';

/**
 * @title CrossChainForwarderHarness
 * @dev Needed to use `EnvelopeUtils` methods.
 */
contract CrossChainForwarderHarness is CrossChainForwarder {
    bool _bridgeTransaction_was_called = false;
    bytes32 _envelopeId;
    bytes32 _transactionId;
    uint256 _destinationChainId;

    uint256 _last_nonceTX_sent;
    uint256 _max_TXnonce;  // the maximal TX nonce ever sent

    mapping(bytes32 => bytes32) _TXid_2_ENid;  // transaction ID => envelope ID

    // mapping from TX-id to TX-nonce + 1.
    // Hence TXid was sended if and only if _TXid_2_TXnonceP1[TXid]>0
    mapping(bytes32 => uint) _TXid_2_TXnonceP1;

    address[] _active_bridges_dest;
    address[] _active_bridges_curr;
    uint256 _num_of_active_bridges;

    constructor(
                ForwarderBridgeAdapterConfigInput[] memory bridgeAdaptersToEnable,
                address[] memory sendersToApprove,
                OptimalBandwidthByChain[] memory optimalBandwidthByChain
    ) CrossChainForwarder (bridgeAdaptersToEnable,
                           sendersToApprove,
                           optimalBandwidthByChain) {
    }

    /* ==============================================================================
       The contract CrossChainForwarder sends out TX, by emiting them. Since CVL can't
       look at the emit data, we use the following function to "capture" information
       about the sended TX.
       We also maintain additional information that doesn't exist in the storage
       of CrossChainForwarder.
       ============================================================================*/
    function _bridgeTransaction(
                                bytes32 envelopeId,
                                bytes32 transactionId,
                                bytes memory encodedTransaction,
                                uint256 destinationChainId,
                                uint256 gasLimit,
                                ChainIdBridgeConfig[] memory bridgeAdapters
    ) internal override returns (bool) {
        _bridgeTransaction_was_called = true;
        _envelopeId = envelopeId;
        _transactionId = transactionId;
        _destinationChainId = destinationChainId;
        _last_nonceTX_sent = get_nonceTX_from_encodedT(encodedTransaction);
        if (_last_nonceTX_sent > _max_TXnonce) 
            _max_TXnonce = _last_nonceTX_sent;

        if (_TXid_2_TXnonceP1[transactionId]==0) { // this is the first time that this TX is sent.
            _TXid_2_TXnonceP1[transactionId] = _last_nonceTX_sent+1;
            _TXid_2_ENid[transactionId] = envelopeId;
        }
        else {
            // The following requires are very delicate. We must guarntee that
            // if the transactionId was already inserted to the following 2 maps
            // then the call to _bridgeTransaction is done using the same arguments.
            // Specifically we care about the envelopeId and the TX-nonce.
            require (_TXid_2_TXnonceP1[transactionId] == _last_nonceTX_sent+1);
            require (_TXid_2_ENid[transactionId] == envelopeId);
        }
        _num_of_active_bridges = bridgeAdapters.length;
        for (uint256 i = 0; i < bridgeAdapters.length; i++) {
          _active_bridges_dest[i] = bridgeAdapters[i].destinationBridgeAdapter;
          _active_bridges_curr[i] = bridgeAdapters[i].currentChainBridgeAdapter;
        }

        bool ret_val = super._bridgeTransaction
            (envelopeId, transactionId, encodedTransaction, destinationChainId,
             gasLimit,  bridgeAdapters);

        return ret_val;
    }

    
    function reset_harness_storage() external {
        _bridgeTransaction_was_called = false;
        _envelopeId = 0;
        _transactionId = 0;
        _destinationChainId = 0;
        _last_nonceTX_sent = 0;
    }

    function get_active_bridges_dest() external view returns (address[] memory) {
        return _active_bridges_dest;
    }
    function get_active_bridges_curr() external view returns (address[] memory) {
        return _active_bridges_curr;
    }

    function get_num_of_active_bridges() external view returns (uint) {
        return _num_of_active_bridges;
    }
    function get_max_TXnonce() external view returns (uint) {
        return _max_TXnonce;
    }
    function get_TXnonceP1(bytes32 TXid) external view returns (uint) {
        return (_TXid_2_TXnonceP1[TXid]);
    }
    function bridgeTransaction_was_called() external view returns (bool) {
        return _bridgeTransaction_was_called;
    }
    function get_param_envelopeId() external view returns (bytes32) {
        return _envelopeId;
    }
    function get_param_transactionId() external view returns (bytes32) {
        return _transactionId;
    }
    function get_param_destinationChainId() external view returns (uint256) {
      return _destinationChainId;
    }
    function get_last_nonceTX_sent() external view returns (uint256) {
        return _last_nonceTX_sent;
    }
    
    
    function get_envelope_from_encodedTX(bytes memory encodedTransaction)
        external view returns (Envelope memory) {
        Transaction memory transaction = TransactionUtils.decode(encodedTransaction);
        Envelope memory envelope = transaction.getEnvelope();
        return envelope;
    }
    function get_transaction_ID_from_encodedTX(bytes memory encodedTransaction) external pure returns (bytes32) {
        return TransactionUtils.getId(encodedTransaction);
    }
    function get_envelopID_from_encodedTX(bytes memory encodedTransaction) external pure returns (bytes32) {
        Transaction memory transaction = TransactionUtils.decode(encodedTransaction);
        return TransactionUtils.getEnvelopeId(transaction);
    }
    function get_nonceTX_from_encodedT(bytes memory encodedTransaction) public pure returns (uint) {
        Transaction memory transaction = TransactionUtils.decode(encodedTransaction);
        return transaction.nonce;
    }
    

    
    function getEnvelopeId(Envelope memory envelope) public view returns (bytes32) {
        return envelope.getId();
    }
    
    function getForwarderBridgeAdaptersByChain_len(uint256 chainId)
        external view returns (uint) {
        return _bridgeAdaptersByChain[chainId].length;
    }

    function getForwarderBridgeAdaptersByChainAtPos_dest(uint256 chainId, uint256 pos)
        external view returns (address) {
        return _bridgeAdaptersByChain[chainId][pos].destinationBridgeAdapter;
    }
    function getForwarderBridgeAdaptersByChainAtPos_curr(uint256 chainId, uint256 pos)
        external view returns (address) {
        return _bridgeAdaptersByChain[chainId][pos].currentChainBridgeAdapter;
    }
}

