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

    struct BorrowDetails {
        address collateralAddress;
        uint256 amountOfJatCoinBorrowed;
        uint256 borrowTime;
    }

    address JATIQUE = makeAddr("jatique");

    function setUp() public {
        DeployJatEngine deployerEngine = new DeployJatEngine();
        (jatCoin, jatEngine, config) = deployerEngine.run();
        // (ethUsdPriceFeedAddress, btcUsdPriceFeedAddress, weth, wbtc,) = config.activeNetworkConfig();
    }

    function testIfTheSetInterestRateFunctionIsProperlySettingTheInterestRate() public {
        uint256 INTEREST_TO_SET = 10;
        uint256 interestRate = jatEngine.getInterestRate();
        console.log("this is the interest rate after initialization ", interestRate);
        jatEngine.setInterestRate(INTEREST_TO_SET);
        uint256 interestRateAfter = jatEngine.getInterestRate();
        console.log("this is the interest rate after ", interestRateAfter);
        assert(interestRateAfter == INTEREST_TO_SET);
    }

    function testIfgetPriceFeedPartAndDecimalIsWorkingProperly() public view {
        int256 expectedEthPrice = config.ETH_USD_PRICE();
        uint256 expectedDecimal = config.DECIMALS();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = config.activeNetworkConfig();
        console.log("this is the expectedEthPrice", expectedEthPrice);
        console.log("this is the expected decimal", expectedDecimal);

        (uint256 returnedEthPrice, uint8 returnedDecimal) = jatEngine.getPriceAndDecimalsFromFeed(wethUsdPriceFeed);
        console.log("this is the eth price that was returned", returnedEthPrice);
        console.log("this is the returned decimal", returnedDecimal);
        assert(expectedDecimal == returnedDecimal);
        assert(uint256(expectedEthPrice) == returnedEthPrice);
    }

    function testUserBorrowDetails() public {
        uint256 testId = 1;
        JatEngine.BorrowDetails memory details = JatEngine.BorrowDetails({
            collateralAddress: JATIQUE,
            amountOfJatCoinBorrowed: 10000,
            borrowTime: block.timestamp
        });
        console.log("this is the block timestamp", block.timestamp);
        jatEngine.setUserBorrowDetails(JATIQUE, testId, details);

        JatEngine.BorrowDetails memory retrievedDetails = jatEngine.getUserBorrowDetails(JATIQUE, testId);

        assertEq(retrievedDetails.collateralAddress, details.collateralAddress);
        assertEq(retrievedDetails.amountOfJatCoinBorrowed, details.amountOfJatCoinBorrowed);
        assertEq(retrievedDetails.borrowTime, details.borrowTime);

        console.log("User borrow details set and retrieved successfully");
        console.log("Collateral Address: ", retrievedDetails.collateralAddress);
        console.log("Amount Borrowed: ", retrievedDetails.amountOfJatCoinBorrowed);
        console.log("Borrow Time: ", retrievedDetails.borrowTime);
    }
}
