const path = require("path");

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    develop: {
      port: 7545,
      gas: 9000000,
      network_id: 5777
    },
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 1000
    },
  },
  // use native binaries rather than solc.js
  compilers: {
    solc: {
      version: "0.6.11"
    }
  },
  // plugins: [
  //   'truffle-ganache-test'
  // ],
  // mocha: {
  //   reporter: 'eth-gas-reporter'
  // }
}
