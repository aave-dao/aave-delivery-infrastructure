# a.DI Properties

# Glossary

- **CrossChainController (CCC)**: Central controller smart contract for the cross chain infrastructure. It has the logic and funds to send
  and receive messages cross chain, and connects all components together.
- **CrossChainForwarder (CCF)**: Contract (parent of CCC) that has the logic to forward a `Message` to another (or same) chains.
- **CrossChainReceiver (CCR)**: Contract (parent of CCC) that has the logic to receive a `Transaction` and deliver the `Message` within it
  to a final destination address
- **EmergencyConsumer (EC)**: Contract (parent of CCC) with the logic to detect an emergency signal.
- **EmergencyRegistry**: Contract that holds a registry of the emergency events activated on all the chains controlled by the Aave Governance.
  To trigger an emergency on destination chain, a counter will be incremented in the registry.
- **BridgeAdapter/s**: Contracts with logic to interact with each Bridge Provider. Used as a stateless library from
  the CCC (via DELEGATECALL) when sending messages, and receiving the `Transaction`s and forwarding them to the CCC on the receiving flow.
- **Message**: Bytes-encoded data to be bridged from an origin network to a destination. Messages don't need to be unique.
  Messages are the only data structure exposed for senders via the cross-chain infrastructure.
- **Envelope**: CCC internal unique object containing a `Message`, origin and destination addresses, and an envelope nonce.
  Required to retry sending a message if the envelope arrived to the destination chain, but was invalidated before execution.
- **Transaction**: CCC internal unique object containing an `Envelope` and a transaction nonce. It is the final object
  used for bridging: every time an envelope is forwarded (no matter if originally or via retry), a new transaction is created.

## CrossChainController (CCC)

- The CCC has 3 responsibilities:
  1. Control forwarding of messages.
  2. Control receiving of messages.
  3. Detect emergency mode and modify the access control when it happens.
- Stores the funds to pay cross-chain messaging via different bridges, so MUST be able to receive and send both native and other tokens.
- Only permissioned entities can move funds out.
- Contract MUST have enough gas to pay for each bridging fees on sending side, and the gas limit on destination chain.
- The CCC detects an emergency state and gives power to a Guardian to solve it.
  - An emergency state can be triggered whenever the configured Chainlink Oracle indicates so.
  - In emergency state the Guardian has the power to:
    - Set required confirmations
    - Invalidate pending messages
    - Update bridge adapters
    - Update senders
    - Update receivers
  - An emergency is marked as solved if the resulting state is a working state
    (number of allowed adapters is >= than confirmations)

## CrossChainForwarder

- Only the approved senders can forward a message.
- Internal transaction nonces are sequential.
- Internal envelope nonces are sequential.
- A Transaction can only contain one Envelope.
- An Envelope should be unique.
- A Transaction should be unique.
- Every Transaction (created via forwardMessage) should be sent to all bridge adapters registered for the destination network.
- A new Envelope should always be registered.
- A Transaction should only be registered if sending it has been attempted.
- Forwarding a message should revert if no bridge adapters are registered for the destination chain.
- An Envelope can only be retried if it has been previously registered.
- An Envelope retry should be on a new Transaction.
- An Envelope retry should fail if there are no adapters registered for the envelope's destination chain.
- A Transaction can only be retried if it has been previously forwarded.
- The Adapters where the retried Transaction will be sent, should be valid.
- Forwarding a message should use the number of adapters specified by the configured optimal bandwidth for destination chain
  - If the optimal bandwidth is greater than the allowed adapters, all adapters should be used.
  - If the optimal bandwidth is 0, all adapters should be used.
- A Transaction can not be retried using the same adapter more than once (in the same attempt).
- A Transaction retry should fail if it has not been forwarded to any adapter.
- Only the Owner can enable/disable authorized senders.
- Only the Owner can enable/disable bridge adapters.
- An adapter can not be the address 0.
- A sender can not be the address 0.
- An Envelope/Transaction can only be forwarded to a supported (has a registered adapter) network.

## CrossChainReceiver

- A Transaction can only be received from authorized bridge adapters.
- Only the Owner can set the receiver's bridge adapters.
- Only the Owner can set the required confirmations.
- To forward a received Envelope to the final address destination, it needs to receive at least `_requiredConfirmations`.
- An Envelope should be marked as accepted only when it reaches `_requiredConfirmations`.
- An Envelope should be delivered to destination only once.
- A delivery of an Envelope can be triggered only if it has not been delivered yet.
- A delivery can be triggered by anyone.
- Only the Owner or Guardian in emergency state can invalidate Envelopes.
- When setting a new invalidation timestamp, all previous Envelopes that have less than the `_requiredConfirmations`
  (that have not been confirmed) will be invalidated: they can not be accepted reach confirmations and so, can not be delivered.
- A message can not get Confirmed or Delivered when requiredConfirmations for the chain are set to 0.

## EmergencyRegistry

- Only the owner can set an emergency on destination chain

## BridgeAdapters (CCIP, LayerZero, Hyperlane)

On sending side:

- A receiver for the message must be set
- The logic to send messages MUST NOT use any storage, as it will be called via delegatecall from the CCC.

On receiving side:

- When receiving a message, the origin chain must be supported by the system.
- When receiving a message, the origin forwarder must be a trusted contract (by general rule, CCC on the origin chain).

## SameChainAdapter

- Must forward a message directly to receiver contract located in same chain as originator.
- Used specifically on core network (Governance) as a fallback in case all voting networks are unreachable.
- Used when a payload needs to be executed on the same chain as Governance, skipping bridging.
