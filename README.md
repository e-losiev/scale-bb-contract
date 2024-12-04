## Scale buy and burn repository

This repository contains code and tests for the Scale Buy & Burn contract.

### Tests

Test suite consist of foundry fork setup of: `unit`, `fuzz` and `invariant` tests
To execute the tests, you should clone this repo and use the following commands:

- `forge build` to build the project
- `forge test --fork-url <rpc-url> -vvvv` to run all foundry tests inside `test/foundry` dir forking mainnet last block
