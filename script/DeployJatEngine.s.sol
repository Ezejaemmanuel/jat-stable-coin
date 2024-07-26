    // SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {JatEngine} from "../src/JatEngine.sol";
import {JatStableCoin} from "../src/JatStableCoin.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
// import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployJatEngine is Script {
    struct Config {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 interestRate;
    }

    uint8 public constant DECIMALS = 18;
    int256 public constant ETH_USD_PRICE = 3442 * int256(10 ** DECIMALS);
    int256 public constant BTC_USD_PRICE = 66407 * int256(10 ** DECIMALS);
    uint256 public constant INTEREST_RATE = 5;
    uint256 public constant AMOUNT_TO_MINT = 1e18 * 1e18;

    function getDeployerKey() public view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        if (chainId == 11155111) {
            return vm.envUint("PRIVATE_KEY");
        } else {
            return vm.envUint("DEFAULT_ANVIL_KEY");
        }
    }

    function run() external returns (JatStableCoin, JatEngine, Config memory) {
        Config memory config;
        uint256 deployerKey = getDeployerKey();
        vm.startBroadcast(deployerKey);
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);

        ERC20Mock wethMock = new ERC20Mock("wETH", "WETH", msg.sender, AMOUNT_TO_MINT);
        console.log("this is the collateral address for wethMock", address(wethMock));

        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, AMOUNT_TO_MINT);
        console.log("this is the address for wbtc mock", address(wbtcMock));

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        if (chainId == 11155111) {
            config = Config({
                // wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                // wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                // weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                // wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                wethUsdPriceFeed: address(ethUsdPriceFeed),
                wbtcUsdPriceFeed: address(btcUsdPriceFeed),
                weth: address(wethMock),
                wbtc: address(wbtcMock),
                interestRate: INTEREST_RATE
            });
        } else {
            config = Config({
                wethUsdPriceFeed: address(ethUsdPriceFeed),
                wbtcUsdPriceFeed: address(btcUsdPriceFeed),
                weth: address(wethMock),
                wbtc: address(wbtcMock),
                interestRate: INTEREST_RATE
            });
        }

        // Deploy the JatStableCoin contract
        JatStableCoin jatStableCoin = new JatStableCoin();
        // Deploy the JatEngine contract
        JatEngine jatEngine = createJatEngine(address(jatStableCoin), config, msg.sender);

        // Transfer ownership of the JatStableCoin contract to the JatEngine contract
        jatStableCoin.transferOwnership(address(jatEngine));

        vm.stopBroadcast();

        return (jatStableCoin, jatEngine, config);
    }

    function createJatEngine(address jatStableCoinAddress, Config memory config, address sender)
        internal
        returns (JatEngine)
    {
        // Array of token addresses and price feed addresses
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = config.weth;
        tokenAddresses[1] = config.wbtc;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = config.wethUsdPriceFeed;
        priceFeedAddresses[1] = config.wbtcUsdPriceFeed;

        JatEngine jatEngine =
            new JatEngine(jatStableCoinAddress, tokenAddresses, priceFeedAddresses, config.interestRate, sender);

        return jatEngine;
    }
}
