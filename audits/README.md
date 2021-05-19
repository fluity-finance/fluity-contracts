# Current Issues

Addressing issues found in [this report](https://github.com/fluity-finance/fluity-contracts/blob/main/audits/Fluity%20-%20Smart%20Contract%20Audit%20v210517.pdf).

| ID      | Description | Risk | Resolution |
| ----------- | ----------- | ------ | ------|
| FTY-001     | Event EarningAdd never emitted       | Low | Won't fix
| FTY-002     | Insufficient testing of new functionality | Low | Will add more tests for reward vesting
| FTY-003     | Tellor oracle address can be changed multiple times |Medium| Won't fix. As long as Chainlink as the primary oracle is functioning properly, capabilities of Tellor admin's role are limited
