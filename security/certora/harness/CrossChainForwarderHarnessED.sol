// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {CrossChainForwarder} from "../munged/src/contracts/CrossChainForwarder.sol";
//import {Envelope} from '../munged/src/contracts/libs/EncodingUtils.sol';
import {Transaction, EncodedTransaction, Envelope, EncodedEnvelope, TransactionUtils, EnvelopeUtils} from '../munged/src/contracts/libs/EncodingUtils.sol';

/**
 * @title CrossChainForwarderHarness
 * @dev Needed to use `EnvelopeUtils` methods.
 */
contract CrossChainForwarderHarnessED is CrossChainForwarder {
    bool _bridgeTransaction_was_called = false;
    bytes _last_encodedTX;

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
       about sended TX.
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
        _last_encodedTX = encodedTransaction;


        bool ret_val = super._bridgeTransaction
            (envelopeId, transactionId, encodedTransaction, destinationChainId,
             gasLimit,  bridgeAdapters);

        return ret_val;
    }

   
    function reset_harness_storage() external {
        _bridgeTransaction_was_called = false;
    }


    function bridgeTransaction_was_called() external view returns (bool) {
        return _bridgeTransaction_was_called;
    }
    function get_last_encodedTX() external view returns (bytes memory) {
        return _last_encodedTX;
    }
    
    
    function get_TX_from_encodedTX(bytes memory encodedTX)
        external view returns (Transaction memory) {
        Transaction memory TX = TransactionUtils.decode(encodedTX);
        return TX;
    }
   

    function get_envelope_from_TX(Transaction memory transaction)
        external view returns (Envelope memory) {
        return transaction.getEnvelope();
    }
    function encode_EN(Envelope memory envelope) external view returns (bytes memory) {
        return abi.encode(envelope);
    }
    function compare_bytes(bytes memory x, bytes memory y) external view returns (bool) {
        return keccak256(x)==keccak256(y);
        //        if (x.length != y.length)
        //    return false;
        //return true;
    }
    function get_bytes_X() external view returns (bytes memory) {
        bytes memory b = bytes("X");
        return b;
    }

    function get_an_envelope() external view returns (Envelope memory) {
        Envelope memory EN;
        EN.nonce = 10;
        EN.origin=address(5);
        EN.destination=address(6);
        EN.originChainId=30;
        EN.destinationChainId=31;
        EN.message = bytes("XY");

        return EN;
    }

    function create_real_TX(uint256 nonce,
                            address origin,
                            address destination,
                            uint256 originChainId,
                            uint256 destinationChainId,
                            bytes memory message,
                            uint256 TXnonce
                           ) external view returns (Transaction memory) {
        Envelope memory EN;
        EN.nonce = nonce;
        EN.origin = origin;
        EN.destination = destination;
        EN.originChainId = originChainId;
        EN.destinationChainId = destinationChainId;
        EN.message = message;

        EncodedEnvelope memory encodedEN = EN.encode();
        
        Transaction memory TX;
        TX.nonce = TXnonce;
        TX.encodedEnvelope = encodedEN.data;

        return TX;
    }
}

