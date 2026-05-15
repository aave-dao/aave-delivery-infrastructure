
/* ==============================================================================
   Note: 
   1. We use TX for transaction, and EN for envelope.
   2. We use mirror for several maps and array from the solidity inorder to use them 
      inside forall statements.

   Munging:
   -------
   - We add virtual to the function _bridgeTransaction inorder to overload it in the
     harness. There we gather a lot of usefull data about sent TX.
   - We commented the delegate calls in 3 places: in _enableBridgeAdapters,
     _configBridgeAdapters, and in _bridgeTransaction.
   ============================================================================*/



//using SameChainAdapter as _SameChainAdapter;


methods {
    function getForwarderBridgeAdaptersByChain_len(uint256 chainId) external returns (uint) envfree;
    function getForwarderBridgeAdaptersByChainAtPos_dest(uint256 chainId, uint256 pos)
        external returns (address) envfree;
    function getForwarderBridgeAdaptersByChainAtPos_curr(uint256 chainId, uint256 pos)
        external returns (address) envfree;
    function owner() external returns (address) envfree;
    function isSenderApproved(address sender) external returns (bool) envfree;
    function approveSenders(address[] senders) external;
    function getCurrentTransactionNonce() external returns (uint256) envfree;
    function isTransactionForwarded(bytes32 transactionId) external returns (bool) envfree;
    function getEnvelopeId(CrossChainForwarderHarness.Envelope) external returns (bytes32) envfree;
    //function _SameChainAdapter.setupPayments() external envfree;
    function isEnvelopeRegistered(bytes32) external returns (bool) envfree;
    function isEnvelopeRegistered(CrossChainForwarderHarness.Envelope) external returns (bool) envfree;
    function getForwarderBridgeAdaptersByChain(uint256) external
        returns (ICrossChainForwarder.ChainIdBridgeConfig[] memory) envfree;
    function bridgeTransaction_was_called() external returns (bool) envfree;
    function reset_harness_storage() external envfree;
    function get_param_envelopeId() external returns (bytes32) envfree;
    function get_param_transactionId() external returns (bytes32) envfree;
    function get_param_destinationChainId() external returns (uint256) envfree;
    //function get_param_encodedTransaction() external returns (bytes) envfree;
    function get_envelope_from_encodedTX(bytes encodedTransaction)
        external returns (CrossChainForwarderHarness.Envelope) envfree;
    function get_transaction_ID_from_encodedTX(bytes) external returns (bytes32) envfree;
    function get_envelopID_from_encodedTX(bytes) external returns (bytes32) envfree;
    function get_last_nonceTX_sent() external returns (uint256) envfree;
    function get_TXnonceP1(bytes32 TXid) external returns (uint) envfree;
    function get_max_TXnonce() external returns (uint) envfree;
    function get_num_of_active_bridges() external returns (uint) envfree;
    function get_active_bridges_dest() external returns (address[]) envfree;
    function get_active_bridges_curr() external returns (address[]) envfree;
}


/* =================================================================================
   **********     MIRRORS for storage variable/arrays/maps               ***********
   ================================================================================*/

ghost uint256 mirror_max_TXnonce {
    init_state axiom mirror_max_TXnonce==0;
}
hook Sstore _max_TXnonce uint256 newVal (uint256 oldVal) {
      mirror_max_TXnonce = newVal;
}
hook Sload uint256 val _max_TXnonce  {
    require(mirror_max_TXnonce == val);
}


ghost uint256 mirror_currentTransactionNonce {
    init_state axiom mirror_currentTransactionNonce==0;
}
hook Sstore _currentTransactionNonce uint256 newVal (uint256 oldVal) {
      mirror_currentTransactionNonce = newVal;
}
hook Sload uint256 val _currentTransactionNonce  {
    require(mirror_currentTransactionNonce == val);
}


ghost mapping(bytes32 => uint256) mirror_TXid_2_TXnonceP1 { 
    init_state axiom forall bytes32 a. mirror_TXid_2_TXnonceP1[a] == 0;
}
hook Sstore _TXid_2_TXnonceP1[KEY bytes32 key] uint256 newVal (uint256 oldVal)  {
      mirror_TXid_2_TXnonceP1[key] = newVal;
}
hook Sload uint256 val _TXid_2_TXnonceP1[KEY bytes32 key]  {
    require(mirror_TXid_2_TXnonceP1[key] == val);
}


ghost mapping(bytes32 => bytes32) mirror_TXid_2_ENid { 
    init_state axiom forall bytes32 a. mirror_TXid_2_ENid[a] == to_bytes32(0);
}
hook Sstore _TXid_2_ENid[KEY bytes32 key] bytes32 newVal (bytes32 oldVal)  {
      mirror_TXid_2_ENid[key] = newVal;
}
hook Sload bytes32 val _TXid_2_ENid[KEY bytes32 key]  {
    require(mirror_TXid_2_ENid[key] == val);
}


ghost mapping(bytes32 => bool) mirror_forwardedTransactions { 
    init_state axiom forall bytes32 a. mirror_forwardedTransactions[a] == false;
}
hook Sstore _forwardedTransactions[KEY bytes32 key] bool newVal (bool oldVal)  {
      mirror_forwardedTransactions[key] = newVal;
}
hook Sload bool val _forwardedTransactions[KEY bytes32 key]  {
    require(mirror_forwardedTransactions[key] == val);
}


ghost mapping(bytes32 => bool) mirror_registeredEnvelopes { 
    init_state axiom forall bytes32 a. mirror_registeredEnvelopes[a] == false;
}
hook Sstore _registeredEnvelopes[KEY bytes32 key] bool newVal (bool oldVal)  {
      mirror_registeredEnvelopes[key] = newVal;
}
hook Sload bool val _registeredEnvelopes[KEY bytes32 key]  {
    require(mirror_registeredEnvelopes[key] == val);
}




ghost mapping(uint => uint) mirror_bridgeAdaptersByChain_IDlen { 
    init_state axiom forall uint a. mirror_bridgeAdaptersByChain_IDlen[a] == 0;
}
hook Sstore _bridgeAdaptersByChain[KEY uint key].(offset 0) uint newLen (uint oldLen)  {
    mirror_bridgeAdaptersByChain_IDlen[key] = newLen;
}
hook Sload uint len _bridgeAdaptersByChain[KEY uint key].(offset 0)  {
    require(mirror_bridgeAdaptersByChain_IDlen[key] == len);
}

ghost mapping(uint256 => mapping(uint=>address)) mirrorArray_dest{
    init_state axiom forall uint256 i. forall uint j. mirrorArray_dest[i][j] == 0;
}
hook Sstore _bridgeAdaptersByChain[KEY uint key][INDEX uint256 i].(offset 0) address newAddr (bytes32 oldAddr)  {
    mirrorArray_dest[key][i] = newAddr;
}
hook Sload address addr _bridgeAdaptersByChain[KEY uint key][INDEX uint256 i].(offset 0)  {
    require(mirrorArray_dest[key][i] == addr);
}

ghost mapping(uint256 => mapping(uint=>address)) mirrorArray_curr{
    init_state axiom forall uint256 i. forall uint j. mirrorArray_curr[i][j] == 0;
}
hook Sstore _bridgeAdaptersByChain[KEY uint key][INDEX uint256 i].(offset 32) address newAddr (bytes32 oldAddr)  {
    mirrorArray_curr[key][i] = newAddr;
}
hook Sload address addr _bridgeAdaptersByChain[KEY uint key][INDEX uint256 i].(offset 32)  {
    require(mirrorArray_curr[key][i] == addr);
}


ghost mapping(address => bool) mirror_approvedSenders { 
    init_state axiom forall address a. mirror_approvedSenders[a] == false;
}
hook Sstore _approvedSenders[KEY address key] bool newVal (bool oldVal)  {
    mirror_approvedSenders[key] = newVal;
}
hook Sload bool val _approvedSenders[KEY address key]  {
    require(mirror_approvedSenders[key] == val);
}
