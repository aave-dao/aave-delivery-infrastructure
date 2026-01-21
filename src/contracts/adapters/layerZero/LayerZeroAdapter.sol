// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {ILayerZeroReceiver} from './interfaces/ILayerZeroReceiver.sol';
import {MessagingParams, Origin, MessagingFee, MessagingReceipt} from './interfaces/ILayerZeroEndpointV2.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {OptionsBuilder} from './libs/OptionsBuilder.sol';
import {BaseAdapter, IBaseAdapter} from '../BaseAdapter.sol';
import {ILayerZeroAdapter, ILayerZeroEndpointV2} from './ILayerZeroAdapter.sol';
import {ChainIds} from 'solidity-utils/contracts/utils/ChainHelpers.sol';
import {Errors} from '../../libs/Errors.sol';

/**
 * @title LayerZeroAdapter
 * @author BGD Labs
 * @notice LayerZero bridge adapter. Used to send and receive messages cross chain
 * @dev it uses the eth balance of CrossChainController contract to pay for message bridging as the method to bridge
        is called via delegate call
 */
contract LayerZeroAdapter is BaseAdapter, ILayerZeroAdapter, ILayerZeroReceiver {
  /// @inheritdoc ILayerZeroAdapter
  ILayerZeroEndpointV2 public immutable LZ_ENDPOINT;

  /// @notice modifier to check that caller is LayerZero endpoint
  modifier onlyLZEndpoint() {
    require(msg.sender == address(LZ_ENDPOINT), Errors.CALLER_NOT_LZ_ENDPOINT);
    _;
  }

  /**
   * @notice constructor for the Layer Zero adapter
   * @param crossChainController address of the contract that manages cross chain infrastructure
   * @param lzEndpoint address of the layer zero endpoint on the current chain where adapter is deployed
   * @param providerGasLimit base gas limit used by the bridge adapter
   * @param trustedRemotes array of objects with chain id and origin addresses which will be allowed to send messages to this adapter
   * @param delegate address of the LayerZero delegate. Delegate can set configs
   */
  constructor(
    address crossChainController,
    address lzEndpoint,
    uint256 providerGasLimit,
    TrustedRemotesConfig[] memory trustedRemotes,
    address delegate
  ) BaseAdapter(crossChainController, providerGasLimit, 'LayerZero adapter', trustedRemotes) {
    require(lzEndpoint != address(0), Errors.INVALID_LZ_ENDPOINT);
    LZ_ENDPOINT = ILayerZeroEndpointV2(lzEndpoint);
    LZ_ENDPOINT.setDelegate(delegate);
  }

  /// @inheritdoc ILayerZeroReceiver
  function nextNonce(uint32 /*_srcEid*/, bytes32 /*_sender*/) public pure returns (uint64) {
    return 0;
  }

  /// @inheritdoc ILayerZeroReceiver
  function lzReceive(
    Origin calldata _origin,
    bytes32,
    bytes calldata _message,
    address,
    bytes calldata
  ) external payable onlyLZEndpoint {
    uint256 originChainId = nativeToInfraChainId(_origin.srcEid);

    require(allowInitializePath(_origin), Errors.REMOTE_NOT_TRUSTED);

    _registerReceivedMessage(_message, originChainId);
  }

  /// @inheritdoc ILayerZeroReceiver
  function allowInitializePath(Origin calldata origin) public view returns (bool) {
    uint256 originChainId = nativeToInfraChainId(origin.srcEid);
    address srcAddress = address(uint160(uint256(origin.sender)));
    return _trustedRemotes[originChainId] == srcAddress && srcAddress != address(0);
  }

  /// @inheritdoc IBaseAdapter
  function forwardMessage(
    address receiver,
    uint256 executionGasLimit,
    uint256 destinationChainId,
    bytes calldata message
  ) external returns (address, uint256) {
    uint32 nativeChainId = SafeCast.toUint32(infraToNativeChainId(destinationChainId));
    require(nativeChainId != uint32(0), Errors.DESTINATION_CHAIN_ID_NOT_SUPPORTED);
    require(receiver != address(0), Errors.RECEIVER_NOT_SET);

    bytes32 receiverAddress = bytes32(uint256(uint160(receiver)));

    uint256 totalGasLimit = executionGasLimit + BASE_GAS_LIMIT;

    bytes memory options = _generateOptions(SafeCast.toUint128(totalGasLimit));

    MessagingFee memory fee = LZ_ENDPOINT.quote(
      MessagingParams(nativeChainId, receiverAddress, message, options, false),
      address(this)
    );

    require(fee.nativeFee <= address(this).balance, Errors.NOT_ENOUGH_VALUE_TO_PAY_BRIDGE_FEES);

    MessagingReceipt memory receipt = LZ_ENDPOINT.send{value: fee.nativeFee}(
      MessagingParams(nativeChainId, receiverAddress, message, options, false),
      address(this)
    );

    return (address(LZ_ENDPOINT), uint256(receipt.nonce));
  }

  /// @inheritdoc IBaseAdapter
  function nativeToInfraChainId(
    uint256 nativeChainId
  ) public pure virtual override returns (uint256) {
    if (nativeChainId == 30101) {
      return ChainIds.ETHEREUM;
    } else if (nativeChainId == 30106) {
      return ChainIds.AVALANCHE;
    } else if (nativeChainId == 30109) {
      return ChainIds.POLYGON;
    } else if (nativeChainId == 30110) {
      return ChainIds.ARBITRUM;
    } else if (nativeChainId == 30111) {
      return ChainIds.OPTIMISM;
    } else if (nativeChainId == 30112) {
      return ChainIds.FANTOM;
    } else if (nativeChainId == 30116) {
      return ChainIds.HARMONY;
    } else if (nativeChainId == 30102) {
      return ChainIds.BNB;
    } else if (nativeChainId == 30151) {
      return ChainIds.METIS;
    } else if (nativeChainId == 30145) {
      return ChainIds.GNOSIS;
    } else if (nativeChainId == 30125) {
      return ChainIds.CELO;
    } else if (nativeChainId == 30332) {
      return ChainIds.SONIC;
    } else if (nativeChainId == 30383) {
      return ChainIds.PLASMA;
    } else {
      return 0;
    }
  }

  /// @inheritdoc IBaseAdapter
  function infraToNativeChainId(
    uint256 infraChainId
  ) public pure virtual override returns (uint256) {
    if (infraChainId == ChainIds.ETHEREUM) {
      return 30101;
    } else if (infraChainId == ChainIds.AVALANCHE) {
      return 30106;
    } else if (infraChainId == ChainIds.POLYGON) {
      return 30109;
    } else if (infraChainId == ChainIds.ARBITRUM) {
      return 30110;
    } else if (infraChainId == ChainIds.OPTIMISM) {
      return 30111;
    } else if (infraChainId == ChainIds.FANTOM) {
      return 30112;
    } else if (infraChainId == ChainIds.HARMONY) {
      return 30116;
    } else if (infraChainId == ChainIds.METIS) {
      return 30151;
    } else if (infraChainId == ChainIds.BNB) {
      return 30102;
    } else if (infraChainId == ChainIds.GNOSIS) {
      return 30145;
    } else if (infraChainId == ChainIds.CELO) {
      return 30125;
    } else if (infraChainId == ChainIds.SONIC) {
      return 30332;
    } else if (infraChainId == ChainIds.PLASMA) {
      return 30383;
    } else {
      return uint16(0);
    }
  }

  /**
   * @notice method to generate LayerZero options
   * @param gasLimit the gas limit to use on destination chain
   * @return bytes with the packed options
   */
  function _generateOptions(uint128 gasLimit) internal pure returns (bytes memory) {
    bytes memory options = OptionsBuilder.newOptions();
    return OptionsBuilder.addExecutorLzReceiveOption(options, gasLimit, 0);
  }
}
