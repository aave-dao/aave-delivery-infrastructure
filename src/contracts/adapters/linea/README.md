# Manual Message Claiming

To manually claim a message sent from origin (Ethereum) on the Linea network follow these steps:

1. Get the tx hash where the message was sent on the origin network (Ethereum). This is to get all the information
   needed on the following steps. Once you have the tx hash, go to the block explorer, input the tx hash, and then go to events.
   Once you are on the events page of the tx, locate the event `MessageSent`
2. Go to the online event decode page: https://tools.deth.net/event-decoder and input the event topics from step 1, and the data.
   Add this code (event abi) to the ABI text box:

```
event MessageSent(
    address indexed _from,
    address indexed _to,
    uint256 _fee,
    uint256 _value,
    uint256 _nonce,
    bytes _calldata,
    bytes32 indexed _messageHash
  );
```

3. Go to the Linea block explorer: https://lineascan.build/ and add the Linea MessageService contract:

- mainnet: [0x508Ca82Df566dCD1B0DE8296e70a96332cD644ec](https://lineascan.build/address/0x508Ca82Df566dCD1B0DE8296e70a96332cD644ec#writeProxyContract)
- sepolia: [0x971e727e956690b9957be6d51Ec16E73AcAC83A7](https://sepolia.lineascan.build/address/0x971e727e956690b9957be6d51Ec16E73AcAC83A7#writeProxyContract)
  Once there go to write as proxy contract, and fill the information from step 2 to the method `claimMessage` and execute the tx.
  Take into account that the topics, calldata and nonce must be in Hex format.
