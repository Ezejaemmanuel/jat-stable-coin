// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployJatEngine} from "../../script/DeployJatEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {JatStableCoin} from "../../src/JatStableCoin.sol";
import {JatEngine} from "../../src/JatEngine.sol";

contract TestJatEngine is Test {
    JatEngine jatEngine;
    JatStableCoin jatCoin;
    HelperConfig config;
    address JATIQUE = makeAddr("jatique");

    function setUp() public {
        DeployJatEngine deployerEngine = new DeployJatEngine();

        (jatCoin, jatEngine, config) = deployerEngine.run();
    }

    function testCalculateCompoundInterest() public {
        console.log("Running testCalculateCompoundInterest...");

        // Array of initial amounts
        uint256[] memory initialAmounts = new uint256[](8);
        initialAmounts[0] = 1000 * 1e18;
        initialAmounts[1] = 2000 * 1e18;
        initialAmounts[2] = 1500 * 1e18;
        initialAmounts[3] = 2500 * 1e18;
        initialAmounts[4] = 3000 * 1e18;
        initialAmounts[5] = 500 * 1e18;
        initialAmounts[6] = 750 * 1e18;
        initialAmounts[7] = 1250 * 1e18;

        // Array of interest rates
        uint256[] memory interestRates = new uint256[](8);
        interestRates[0] = 5; // 5%
        interestRates[1] = 3; // 3%
        interestRates[2] = 7; // 7%
        interestRates[3] = 2; // 2%
        interestRates[4] = 6; // 6%
        interestRates[5] = 4; // 4%
        interestRates[6] = 8; // 8%
        interestRates[7] = 1; // 1%

        // Array of time periods
        uint256[] memory timePeriods = new uint256[](8);
        timePeriods[0] = 365 days; // 1 year
        timePeriods[1] = 182 days; // 6 months
        timePeriods[2] = 10 minutes; // 10 minutes
        timePeriods[3] = 10 seconds; // 10 seconds
        timePeriods[4] = 30 days; // 1 month
        timePeriods[5] = 90 days; // 3 months
        timePeriods[6] = 1 days; // 1 day
        timePeriods[7] = 5 days; // 5 days

        // Array of expected amounts (these should be calculated based on your interest rates and periods)
        uint256[] memory expectedAmounts = new uint256[](8);
        expectedAmounts[0] = 1050 * 1e18; // Example: 5% interest for 1 year on 1000
        expectedAmounts[1] = 2030 * 1e18; // Example: 3% interest for 1 year on 2000
        expectedAmounts[2] = 1605 * 1e18; // Example: 7% interest for 1 year on 1500
        expectedAmounts[3] = 2550 * 1e18; // Example: 2% interest for 1 year on 2500
        expectedAmounts[4] = 3180 * 1e18; // Example: 6% interest for 1 year on 3000
        expectedAmounts[5] = 510 * 1e18; // Example: 2% interest for 1 year on 500
        expectedAmounts[6] = 780 * 1e18; // Example: 4% interest for 1 year on 750
        expectedAmounts[7] = 1287 * 1e18; // Example: 3% interest for 1 year on 1250

        // for (uint256 i = 0; i < initialAmounts.length; i++) {
        uint256 initialAmount = initialAmounts[0];
        uint256 interestRate = interestRates[0];
        uint256 timeElapsed = timePeriods[0];
        uint256 expectedAmount = expectedAmounts[0];

        uint256 borrowTime = block.timestamp;
        uint256 simulatedTime = borrowTime + timeElapsed;

        // Move the block timestamp forward
        vm.warp(simulatedTime);
        console.log("Simulated Time: ", simulatedTime);

        console.log("Initial Amount: ", initialAmount);
        console.log("Interest Rate: ", interestRate);
        console.log("Time Elapsed: ", timeElapsed);
        console.log("Expected Amount: ", expectedAmount);

        // Call the calculateCompoundInterest function
        uint256 returnedAmount = jatEngine.calculateCompoundInterest(borrowTime, initialAmount, interestRate);
        console.log("Returned Amount: ", returnedAmount);

        // Assert that the returned value is as expected
        assertEq(returnedAmount, expectedAmount);
        // }
    }

    function testConstructorInitializesStateCorrectly() public view {
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = config.activeNetworkConfig();

        assertEq(address(jatEngine.getJatStableCoinAddress()), address(jatCoin));

        assertEq(jatEngine.getInterestRate(), interestRate);

        address[] memory collateralAddresses = new address[](2);
        collateralAddresses[0] = weth;
        collateralAddresses[1] = wbtc;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = wethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;

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
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = config.activeNetworkConfig();
        uint256 collateralAmount = 2e18; // Example collateral amount
        uint256 expectedEthUsdPrice = uint256(config.ETH_USD_PRICE()); // Example ETH/USD price from config
        console.log("this is the expectedEthUsdPrice", expectedEthUsdPrice);
        uint256 expectedUsdValue = collateralAmount * expectedEthUsdPrice / (10 ** uint256(config.DECIMALS()));
        // Call the function and get the returned USD value
        uint256 returnedUsdValue = jatEngine.convertCollateralValueToUsd(weth, collateralAmount);
        // Log the expected and returned values for debugging
        console.log("Expected USD Value:", expectedUsdValue);
        console.log("Returned USD Value:", returnedUsdValue);

        // Assert that the returned value is as expected
        assert(returnedUsdValue == expectedUsdValue);
    }

    function testConvertUsdValueToCollateral() public view {
        // Setup initial values and expectations
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = config.activeNetworkConfig();

        uint256 usdAmount = 10 * 1e18; // Example USD amount in wei (assuming 18 decimals for USD)
        uint256 expectedEthUsdPrice = uint256(config.ETH_USD_PRICE()); // Example ETH/USD price from config
        uint8 decimals = config.DECIMALS(); // Get decimals for the price feed

        uint256 expectedCollateralAmount = (usdAmount * (10 ** uint256(decimals))) / expectedEthUsdPrice;

        // Call the private function via a public wrapper (you may need to add a public wrapper for testing)
        uint256 returnedCollateralAmount = jatEngine.convertUsdValueToCollateral(weth, usdAmount);

        // Log the expected and returned values for debugging
        console.logUint(expectedCollateralAmount);
        console.log("Returned Collateral Amount:", returnedCollateralAmount);

        // Assert that the returned value is as expected
        assert(returnedCollateralAmount == expectedCollateralAmount);
    }

    function testGetUserTotalCollateralValueInUsd() public {
        // Sample collateral addresses and amounts for testing
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = config.activeNetworkConfig();
        uint256 wethAmount = 2 * 1e18; // 2 WETH
        uint256 wbtcAmount = 1 * 1e8; // 1 WBTC (assuming 8 decimals for BTC)

        // Set collateral amounts for the user
        jatEngine.setUserCollateral(JATIQUE, weth, wethAmount);
        jatEngine.setUserCollateral(JATIQUE, wbtc, wbtcAmount);

        // Calculate expected USD values
        uint256 wethUsdPrice = uint256(config.ETH_USD_PRICE());
        uint256 wbtcUsdPrice = uint256(config.BTC_USD_PRICE());
        uint256 wethUsdValue = wethAmount * wethUsdPrice / (10 ** uint256(config.DECIMALS()));
        uint256 wbtcUsdValue = wbtcAmount * wbtcUsdPrice / (10 ** uint256(config.DECIMALS()));
        uint256 expectedTotalUsdValue = wethUsdValue + wbtcUsdValue;

        // Start the prank
        vm.startPrank(JATIQUE);
        uint256 returnedTotalUsdValue = jatEngine.getUserTotalCollateralValueInUsd(JATIQUE);
        console.log("this is returned total value ", returnedTotalUsdValue);
        vm.stopPrank();

        // Log the expected and returned values for debugging
        console.log("Expected Total USD Value:", expectedTotalUsdValue);
        console.log("Returned Total USD Value:", returnedTotalUsdValue);

        // Assert that the returned value is as expected
        assertEq(returnedTotalUsdValue, expectedTotalUsdValue);
    }
}
