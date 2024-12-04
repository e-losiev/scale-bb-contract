import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require("dotenv").config();
import "@nomicfoundation/hardhat-foundry";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.26",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true,
        },
    },
    networks: {
        hardhat: {
            forking: {
                // url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
                url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
                blockNumber: 21286408,
            },
            // chainId: 1,
            // initialBaseFeePerGas: 1235612399,
        },
        sepolia: {
            url: process.env.SEPOLIA_RPC_URL,
            accounts: [process.env.SEPOLIA_PRIVATE_KEY as string],
            timeout: 999999,
        },
        eth: {
            url: process.env.MAINNET_RPC_URL,
            accounts: [process.env.MAINNET_PRIVATE_KEY as string],
            timeout: 999999,
        },
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_KEY,
    },
    gasReporter: {
        enabled: true,
        currency: "USD",
        gasPrice: 20,
        // gasPriceApi: "https://api.etherscan.io/api?module=proxy&action=eth_gasPrice",
        coinmarketcap: process.env.COINMKTCAP_API,
    },
};

export default config;
