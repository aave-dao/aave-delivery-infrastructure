// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

contract BaseReceiverPortalDummy {
  
  
  // Global call counter of receiveCrossChainMessage(address,uint256,bytes)
  uint256 public receiveCrossChainMessage_success_counter;
  bool internal _receiveCrossChainMessage_reverts;

  mapping (address => mapping(uint256 => mapping(bytes => uint256))) internal _receive_cross_chain_message_counter;

  // Decides nondeterministically whteher to revert
  function receiveCrossChainMessage_reverts() internal view returns (bool) {return _receiveCrossChainMessage_reverts;}

  // message-specific call counter of receiveCrossChainMessage(address,uint256,bytes)
  function get_receive_cross_chain_message_counter
          (address originSender, uint256 originChainId, bytes memory message) view external returns (uint256)
      {
         return _receive_cross_chain_message_counter[originSender][originChainId][message];
      }
   
  function receiveCrossChainMessage(address originSender, uint256 originChainId, bytes memory message) external{
        require ( receiveCrossChainMessage_reverts());
        _receive_cross_chain_message_counter[originSender][originChainId][message]++;
        receiveCrossChainMessage_success_counter++;
      
    }

}