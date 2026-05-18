# a.DI. Setup instructions

<br>

## General setup

This project uses Foundry and partially Node/npm, so having them installed is a pre-requirement of the setup.

To install run:

```
npm i // Install package dependencies
forge install // Install dependency libraries
```

<br>

## Env Configuration

In order to run tests, a `.env` needs to be configured.

An `.env.example` in included in the repository, that can be used as template to fill all the required fields

```shell
cp .env.example .env
```

<br>

## Tests

The simplest ways of running test is with the following

```
forge test
```

Being Foundry based, any other granular way of executing isolated tests applies to this project.

<br>

## Scripts

The deployment scripts can be found [HERE](../scripts/). They inherit from the contract [BaseScripts](../scripts/BaseScript.sol) to register and use the deployed addresses between them, and coordinate a full network deployment.

The scripts consist of:

- [Adapters](../scripts/Adapters/): Folder containing all the bridge adapter contracts deployment scripts
- [CCC](../scripts/CCC/): Folder containing the necessary scripts to deploy and configure the `CrossChainController`s.
- [Contract extensions](../scripts/contract_extensions/): Folder with contracts that have been extended for testnet deployments. These contracts override the parent contract with specific configurations

<br>

## Makefile

We have created a [Makefile](../Makefile) with the necessary commands to trigger the different deployment scripts.

To trigger a full deployment this command should be called:

```shell
make deploy-full # Deployment for all the configured networks.
```

with the environment variable flags:

- `PROD`: if true, the deployment will happen on mainnet networks. If not it will deploy on test networks
- `LEDGER`: if true, the deployment will use a (connected) Ledger. If not, it will use the private key specified in the
  local environment.

A gas multiplier option has been added to the ethereum network (and testnets) to ensure proper deployment.

To add / remove a network from deployment it must be updated in the command.

The commands use the network names specified to search for the contracts on the deployment scripts (if no name for contracts
to execute are specified):
`$(call deploy_fn,InitialDeployments,ethereum avalanche polygon optimism arbitrum metis)` This takes the network name,
it capitalizes the name, and searches for the contract on the specified directory (it adds `_testnet` to the contract names
to be able to differenciate between a prod and test deployment).

If the script contract has a different naming (than a network name: `Ethereum`) it can also be specified in the command
like so: `$(call deploy_fn,SomeDir/SomeFile,ethereum,ContractToCall)`

<br>

## Addresses

The addresses obtained from triggering the deployment scripts can be found [here](../deployments/)

<br>

## Payload Scripts

Included [HERE](../scripts/create_payloads/) are scripts with governance payload templates that modify key parameters in a.DI. Each individual file can be duplicated and modified to achieve the desired parameter configuration. These are meant to be used as templates for creating new AIPs.

Furthermore, there is a pre-made payload, the `SolveEmergencyPayloadPrePopulated`. This payload implements the necessary logic to entirely close off a chain in emergency mode via `solveEmergency()`. Normal functionality could later be restored by triggering another emergency and solving it with the desired parameters.
