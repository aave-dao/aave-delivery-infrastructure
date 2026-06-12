import "methods.spec";

methods{
  function get__emergencyCount() external returns(uint256)  envfree;

  // declared in ICLEmergencyOracle.sol
//  function _.latestRoundData() external returns (uint80,int256,uint256,uint256,uint80) => NONDET;
  function _.latestRoundData() external => NONDET;

  // The following should be change to a DISPATCHER. Naftali is working to allow delegatecall to be dispatched.
  function _.forwardMessage(address receiver,uint256 executionGasLimit,uint256 destinationChainId,bytes message)
    external => NONDET;
}

definition is_invalidating_function(method f) returns bool =
  f.selector == sig:updateMessagesValidityTimestamp(ICrossChainReceiver.ValidityTimestampInput[]).selector ||
  f.selector == sig:solveEmergency(ICrossChainReceiver.ConfirmationInput[],
                                   ICrossChainReceiver.ValidityTimestampInput[],
                                   ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[],
                                   ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[],
                                   address[],
                                   address[],
                                   ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[],
                                   ICrossChainForwarder.BridgeAdapterToDisable[],
                                   ICrossChainForwarder.OptimalBandwidthByChain[]
                                  ).selector;

// Propert #9: Only the Owner or Guardian in emergency state can invalidate Envelopes.
//todo: add check of emergency state
rule only_owner_change_validityTimestamp(method f) 
filtered {f -> is_invalidating_function(f)}
{
  env e;
  calldataarg args;
  uint256 chainId;
  address guardian_before = guardian(); // to workaround DEFAULT HAVOC caused by delegatecall
  uint120 validityTimestamp_before = getValidityTimestamp(chainId);
  f(e, args);
  uint120 validityTimestamp_after = getValidityTimestamp(chainId);
  assert validityTimestamp_before != validityTimestamp_after => 
      e.msg.sender == owner() ||  
      e.msg.sender == guardian_before;
}


rule only_invalidating_functions_can_change_validityTimestamp(method f)
filtered {f -> !f.isView &&
        // ignore CrossChainForwarder.enableBridgeAdapters() because CrossChainForwarder is out of scope
        f.selector != sig:enableBridgeAdapters(ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[]).selector &&
        // ignore CrossChainForwarder.configBridgeAdapters() because CrossChainForwarder is out of scope
        f.selector != sig:configBridgeAdapters(ICrossChainForwarder.BridgeAdapterConfig[]).selector
        }
{
  env e;
  calldataarg args;
  uint256 chainId;
  uint120 validityTimestamp_before = getValidityTimestamp(chainId);
  f(e, args);
  uint120 validityTimestamp_after = getValidityTimestamp(chainId);
  assert validityTimestamp_before != validityTimestamp_after => is_invalidating_function(f);
}

rule only_owner_change_validityTimestamp_witness_1(method f) 
filtered {f -> is_invalidating_function(f)}
{
  env e;
  calldataarg args;
  uint256 chainId;
  uint120 validityTimestamp_before = getValidityTimestamp(chainId);
  f(e, args);
  uint120 validityTimestamp_after = getValidityTimestamp(chainId);
  satisfy validityTimestamp_before != validityTimestamp_after;
}

rule only_owner_change_validityTimestamp_witness_2(method f) 
filtered {f -> is_invalidating_function(f)}
{
  env e;
  calldataarg args;
  uint256 chainId;
  uint120 validityTimestamp_before = getValidityTimestamp(chainId);
  f(e, args);
  uint120 validityTimestamp_after = getValidityTimestamp(chainId);
  require validityTimestamp_before != validityTimestamp_after;
  satisfy e.msg.sender == owner();
}

rule only_owner_change_validityTimestamp_witness_3(method f) 
filtered {f -> is_invalidating_function(f)}
{
  env e;
  calldataarg args;
  uint256 chainId;
  uint256 _emergencyCount_before = get__emergencyCount();
  uint120 validityTimestamp_before = getValidityTimestamp(chainId);
  f(e, args);
  uint120 validityTimestamp_after = getValidityTimestamp(chainId);
  require validityTimestamp_before != validityTimestamp_after;
  require _emergencyCount_before > 0;
  satisfy e.msg.sender == guardian();
}



