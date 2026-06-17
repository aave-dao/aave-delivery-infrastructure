// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {BaseCrossChainController} from '../munged/src/contracts/BaseCrossChainController.sol';
import {CrossChainReceiverHarnessAbstract} from './CrossChainReceiverHarnessAbstract.sol';

contract BaseCrossChainControllerHarness is BaseCrossChainController, CrossChainReceiverHarnessAbstract {

}
