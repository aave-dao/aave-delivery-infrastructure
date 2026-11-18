// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {CrossChainReceiverHarnessAbstract} from './CrossChainReceiverHarnessAbstract.sol';
import {CrossChainReceiver} from '../munged/src/contracts/CrossChainReceiver.sol';

contract CrossChainReceiverHarness is CrossChainReceiverHarnessAbstract {

constructor(
    ConfirmationInput[] memory initialRequiredConfirmations,
    ReceiverBridgeAdapterConfigInput[] memory bridgeAdaptersToAllow
  ) CrossChainReceiver(initialRequiredConfirmations, bridgeAdaptersToAllow) 
  {}


}
