require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("solidity-coverage");
require("hardhat-gas-reporter");

const accounts = require("./hardhatAccountsList2k.js");
const accountsList = accounts.accountsList

const fs = require('fs')
const getSecret = (secretKey, defaultValue='') => {
    const SECRETS_FILE = "./secrets.js"
    let secret = defaultValue
    if (fs.existsSync(SECRETS_FILE)) {
        const { secrets } = require(SECRETS_FILE)
        if (secrets[secretKey]) { secret = secrets[secretKey] }
    }

    return secret
}

module.exports = {
    paths: {
        // contracts: "./contracts",
        // artifacts: "./artifacts"
    },
    solidity: {
        compilers: [
            {
                version: "0.4.23",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100
                    }
                }
            },
            {
                version: "0.5.17",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100
                    }
                }
            },
            {
                version: "0.6.11",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100
                    }
                }
            },
        ]
    },
    networks: {
        hardhat: {
            accounts: accountsList,
            gas: 10000000,  // tx gas limit
            blockGasLimit: 12500000,
            gasPrice: 20000000000,
        },
        bsctest: {
            url: "https://data-seed-prebsc-1-s1.binance.org:8545",
            accounts: [
                getSecret('TESTNET_PRIVATEKEY', '0x60ddfe7f579ab6867cbe7a2dc03853dc141d7a4ab6dbefc0dae2d2b1bd4e487f'),
            ]
        },
        bscmain: {
            url: "https://bsc-dataseed.binance.org/",
            accounts: [
              getSecret('MAINNET_PRIVATEKEY', '0x60ddfe7f579ab6867cbe7a2dc03853dc141d7a4ab6dbefc0dae2d2b1bd4e487f')
            ]
        }
    },
    etherscan: {
        apiKey: getSecret("ETHERSCAN_API_KEY")
    },
    mocha: { timeout: 12000000 },
    rpc: {
        host: "localhost",
        port: 8545
    },
    gasReporter: {
        enabled: (process.env.REPORT_GAS) ? true : false
    }
};
