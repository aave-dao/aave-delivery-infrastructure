# Aave Delivery Infrastructure Scripts

In this folder, you can find the base scripts necessary for aDI deployment (used in [adi-deploy](https://github.com/aave-dao/adi-deploy)).
In this folder, there are no direct deployment scripts.

The scripts are divided as:

- [Access Control](./README.md#access-control)
- [Adapters](./README.md#adapters)
- [CCC](./README.md#ccc)
- [Emergency](./README.md#emergency)

Most of the scripts depend on [BaseScript](./BaseScript.sol) and Create2 from [solidity-utils](https://github.com/bgd-labs/solidity-utils).
On `BaseScript` we can find the method to deploy using Create2 and the method to predict the address when using Create2. These two methods form the base to use when deploying all contracts.

## Access Control

- [Deploy_Granular_CCC_Guardian.s.sol](./access_control/Deploy_Granular_CCC_Guardian.sol)

On this script we have the base code to deploy the GranularGuardian. For this it will need the:

- Default admin: should be executor lvl 1
- Retry Guardian: should be BGD Guardian, or guardian that will be able to call the aDI retry methods.
- Solve Emergency Guardian: should be the Aave Governance Guardian, which will be allowed (when signaled by emergency oracle) to solve emergencies on aDI.

## Adapters

- [Adapters](./Adapters)

On this folder we will find one deployment script for every network / adapter pair for native adapters (L2) and the adapters that support multiple networks (ex: CCIP, LZ, etc).
These set default gas limit (amount of gas that needs to be paid for message passing on destination network), and expect the destination network CCC. This is enforced by making all adapter deployment scripts inherit from [BaseAdapterScript](./Adapters/BaseAdapterScript.sol).

Depending on the adapter it will also expect the bridge provider router address (address that will communicate with the adapters (initiates the passing of the message to / from other networks)), and some specific bridge provider addresses / configurations.

## CCC

- [DeployCrossChainController.sol](./CCC/DeployCrossChainController.sol)

This script has the logic to deploy both CCC implementation versions, depending on if the CL_EMERGENCY_ORACLE is set.

## Emergency

- [Deploy_EmergencyRegistry.sol](./emergency/Deploy_EmergencyRegistry.sol)

This is the script to deploy the emergency registry (responsible to trigger emergency oracle updates on specified networks). It expects the owner address, which is the one allowed to set emergencies (Should be executor lvl 1).
