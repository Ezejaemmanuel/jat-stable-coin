// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployJatEngine} from "../../script/DeployJatEngine.s.sol";
import {JatStableCoin} from "../../src/JatStableCoin.sol";
import {JatEngine} from "../../src/JatEngine.sol";

contract TestJatEngine is Test {
    JatEngine jatEngine;
    JatStableCoin jatCoin;
    DeployJatEngine.Config config;
    DeployJatEngine deployerEngine;
    address JATIQUE = makeAddr("jatique");

    function setUp() public {
        deployerEngine = new DeployJatEngine();
        (jatCoin, jatEngine, config) = deployerEngine.run();
    }

    function testConstructorInitializesStateCorrectly() public view {
        // (
        //     address wethUsdPriceFeed,
        //     address wbtcUsdPriceFeed,
        //     address weth,
        //     address wbtc,
        //     uint256 deployerKey,
        //     uint256 interestRate
        // ) = config.activeNetworkConfig();

        assertEq(address(jatEngine.getJatStableCoinAddress()), address(jatCoin));
        assertEq(jatEngine.getInterestRate(), config.interestRate);

        address[] memory collateralAddresses = new address[](2);
        collateralAddresses[0] = config.weth;
        collateralAddresses[1] = config.wbtc;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = config.wethUsdPriceFeed;
        priceFeedAddresses[1] = config.wbtcUsdPriceFeed;

        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            assertEq(jatEngine.getCollateralPriceFeedAddress(collateralAddresses[i]), priceFeedAddresses[i]);
        }
        console.log("Collateral addresses and price feeds verified");

        address[] memory retrievedCollateralAddresses = jatEngine.getListOfCollateralAddresses();
        assertEq(retrievedCollateralAddresses.length, collateralAddresses.length);
        console.log("Collateral addresses length verified");

        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            console.log("Verifying collateral address: ", collateralAddresses[i]);
            assertEq(retrievedCollateralAddresses[i], collateralAddresses[i]);
        }
        console.log("Collateral addresses verified");

        // Uncomment and update the following line if you want to check the owner
        // assertEq(jatEngine.owner(), msg.sender);
        // console.log("Owner verified");
    }

    function testConstructorRevertsIfLengthsAreNotEqual() public {
        console.log("Running testConstructorRevertsIfLengthsAreNotEqual...");

        address[] memory collateralAddresses = new address[](2);
        collateralAddresses[0] = address(0x1);
        collateralAddresses[1] = address(0x2);

        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = address(0x3);

        console.log("Expecting revert due to unequal lengths of collateral and price feed addresses");
        vm.expectRevert(JatEngine.JatEngine__TheyAreNotOfTheSameLength.selector);
        new JatEngine(address(jatCoin), collateralAddresses, priceFeedAddresses, 5e18, address(this));
    }

    function testConvertFromCollateralValueToUsdValue() public {
        // Setup initial values and expectations
        // (
        //     address wethUsdPriceFeed,
        //     address wbtcUsdPriceFeed,
        //     address weth,
        //     address wbtc,
        //     uint256 deployerKey,
        //     uint256 interestRate
        // ) = config.activeNetworkConfig();
        uint256 collateralAmount = 2e18; // Example collateral amount
        uint256 expectedEthUsdPrice = uint256(deployerEngine.ETH_USD_PRICE()); // Example ETH/USD price from config
        console.log("This is the expectedEthUsdPrice", expectedEthUsdPrice);
        uint256 expectedUsdValue = collateralAmount * expectedEthUsdPrice / (10 ** uint256(deployerEngine.DECIMALS()));
        // Call the function and get the returned USD value
        uint256 returnedUsdValue = jatEngine.convertCollateralValueToUsd(config.weth, collateralAmount);
        // Log the expected and returned values for debugging
        console.log("Expected USD Value:", expectedUsdValue);
        console.log("Returned USD Value:", returnedUsdValue);

        // Assert that the returned value is as expected
        assertEq(returnedUsdValue, expectedUsdValue);
    }

    function testConvertUsdValueToCollateral() public view {
        // Setup initial values and expectations
        // (
        //     address wethUsdPriceFeed,
        //     address wbtcUsdPriceFeed,
        //     address weth,
        //     address wbtc,
        //     uint256 deployerKey,
        //     uint256 interestRate
        // ) = config.activeNetworkConfig();

        uint256 usdAmount = 10 * 1e18; // Example USD amount in wei (assuming 18 decimals for USD)
        uint256 expectedEthUsdPrice = uint256(deployerEngine.ETH_USD_PRICE()); // Example ETH/USD price from config
        uint8 decimals = deployerEngine.DECIMALS(); // Get decimals for the price feed

        uint256 expectedCollateralAmount = (usdAmount * (10 ** uint256(decimals))) / expectedEthUsdPrice;

        // Call the function and get the returned collateral amount
        uint256 returnedCollateralAmount = jatEngine.convertUsdValueToCollateral(config.weth, usdAmount);

        // Log the expected and returned values for debugging
        console.log("Expected Collateral Amount:", expectedCollateralAmount);
        console.log("Returned Collateral Amount:", returnedCollateralAmount);

        // Assert that the returned value is as expected
        assertEq(returnedCollateralAmount, expectedCollateralAmount);
    }

    function testGetUserTotalCollateralValueInUsd() public {
        // Sample collateral addresses and amounts for testing
        // (
        //     address wethUsdPriceFeed,
        //     address wbtcUsdPriceFeed,
        //     address weth,
        //     address wbtc,
        //     uint256 deployerKey,
        //     uint256 interestRate
        // ) = config.activeNetworkConfig();
        uint256 wethAmount = 2 * 1e18; // 2 WETH
        uint256 wbtcAmount = 1 * 1e8; // 1 WBTC (assuming 8 decimals for BTC)

        // Set collateral amounts for the user
        jatEngine.setUserCollateral(JATIQUE, config.weth, wethAmount);
        jatEngine.setUserCollateral(JATIQUE, config.wbtc, wbtcAmount);

        // Calculate expected USD values
        uint256 wethUsdPrice = uint256(deployerEngine.ETH_USD_PRICE());
        uint256 wbtcUsdPrice = uint256(deployerEngine.BTC_USD_PRICE());
        uint256 wethUsdValue = wethAmount * wethUsdPrice / (10 ** uint256(deployerEngine.DECIMALS()));
        uint256 wbtcUsdValue = wbtcAmount * wbtcUsdPrice / (10 ** uint256(deployerEngine.DECIMALS()));
        uint256 expectedTotalUsdValue = wethUsdValue + wbtcUsdValue;

        // Start the prank
        vm.startPrank(JATIQUE);
        uint256 returnedTotalUsdValue = jatEngine.getUserTotalCollateralValueInUsd(JATIQUE);
        console.log("This is returned total value", returnedTotalUsdValue);
        vm.stopPrank();

        // Log the expected and returned values for debugging
        console.log("Expected Total USD Value:", expectedTotalUsdValue);
        console.log("Returned Total USD Value:", returnedTotalUsdValue);

        // Assert that the returned value is as expected
        assertEq(returnedTotalUsdValue, expectedTotalUsdValue);
    }
}
