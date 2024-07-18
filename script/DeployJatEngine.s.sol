// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {JatEngine} from "../src/JatEngine.sol";
import {JatStableCoin} from "../src/JatStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployJatEngine is Script {
    struct Config {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
        uint256 interestRate;
    }

    function getConfig(HelperConfig helperConfig) internal view returns (Config memory) {
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = helperConfig.activeNetworkConfig();

        return Config({
            wethUsdPriceFeed: wethUsdPriceFeed,
            wbtcUsdPriceFeed: wbtcUsdPriceFeed,
            weth: weth,
            wbtc: wbtc,
            deployerKey: deployerKey,
            interestRate: interestRate
        });
    }

    function run() external returns (JatStableCoin, JatEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!

        Config memory config = getConfig(helperConfig);
        // console.log("Config fetched in run(): ", config);

        vm.startBroadcast(config.deployerKey);

        // Deploy the JatStableCoin contract
        JatStableCoin jatStableCoin = new JatStableCoin();

        // Deploy the JatEngine contract
        JatEngine jatEngine = createJatEngine(address(jatStableCoin), config, msg.sender);

        // Transfer ownership of the JatStableCoin contract to the JatEngine contract
        jatStableCoin.transferOwnership(address(jatEngine));

        vm.stopBroadcast();

        return (jatStableCoin, jatEngine, helperConfig);
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
