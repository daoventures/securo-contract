require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('@nomiclabs/hardhat-ethers');
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-gas-reporter");
require('hardhat-contract-sizer');
require('solidity-coverage');
require("dotenv").config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const isBinance = (process.env.BLOCKCHAIN === 'binance') ? true : false;
const isPolygon = (process.env.BLOCKCHAIN === 'polygon') ? true : false;
const isAvalanche = (process.env.BLOCKCHAIN === 'avalanche') ? true : false;
const isAurora = (process.env.BLOCKCHAIN === 'aurora') ? true : false;

const apiKey = isBinance ? process.env.BSCSCAN_API_KEY
              : isPolygon ? process.env.POLYGONSCAN_API_KEY
              : isAvalanche ? process.env.AVAXSCAN_API_KEY
              : isAurora ? process.env.AURORASCAN_API_KEY
              : process.env.ETHERSCAN_API_KEY;

const chainId = isBinance ? 56
              : isPolygon ? 137
              : isAvalanche ? 43114
              : isAurora ? 1313161554
              : 1;

module.exports = {
  solidity: {
    compilers: [{
      version: "0.8.9",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }]
  },
  networks: {
    hardhat: {
      // chainId: chainId,
    },
    auroraMainnet: {
      url: `https://mainnet.aurora.dev`,
      accounts: [process.env.PRIVATE_KEY]
    },
    auroraTestnet: {
      url: `https://testnet.aurora.dev`,
      accounts: [process.env.PRIVATE_KEY]
    },
    avaxMainnet: {
      url: `https://api.avax.network/ext/bc/C/rpc`,
      accounts: [process.env.PRIVATE_KEY]
    },
    avaxTestnet: {
      url: `https://api.avax-test.network/ext/bc/C/rpc`,
      accounts: [process.env.PRIVATE_KEY]
    },
    bscMainnet: {
      url: `https://bsc-dataseed.binance.org`,
      accounts: [process.env.PRIVATE_KEY]
    },
    bscTestnet: {
      url: `https://data-seed-prebsc-2-s1.binance.org:8545`,
      accounts: [process.env.PRIVATE_KEY]
    },
    maticMainnet: {
      url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_MAINNET_API_KEY}`,
      // url: `https://rpc-mainnet.maticvigil.com`, // ethers.provider.getStorageAt is failed with this url
      accounts: [process.env.PRIVATE_KEY]
    },
    maticMumbai: {
      url: `https://rpc-mumbai.maticvigil.com`,
      accounts: [process.env.PRIVATE_KEY]
    },
  },
  etherscan: {
    apiKey: apiKey
  },
  gasReporter: {
    enabled: true
  },
  mocha: {
    timeout: 120000
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: false,
    strict: true,
  }
};
