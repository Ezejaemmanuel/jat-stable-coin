// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployJatEngine} from "../../script/DeployJatEngine.s.sol";
import {JatStableCoin} from "../../src/JatStableCoin.sol";
import {JatEngine} from "../../src/JatEngine.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

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
        int256 expectedEthPrice = deployerEngine.ETH_USD_PRICE();
        uint8 expectedDecimal = deployerEngine.DECIMALS();

        address wethUsdPriceFeed = config.wethUsdPriceFeed;

        (uint256 returnedEthPrice, uint8 returnedDecimal) = jatEngine.getPriceAndDecimalsFromFeed(wethUsdPriceFeed);
        console.log("this is the eth price that was returned", returnedEthPrice);
        console.log("this is the returned decimal", returnedDecimal);
        assert(expectedDecimal == returnedDecimal);
        assert(uint256(expectedEthPrice) == returnedEthPrice);
    }

    function testUserBorrowDetails() public {
        uint256 testId = 1;
        JatEngine.BorrowDetails memory details = JatEngine.BorrowDetails({
            id: testId,
            user: msg.sender,
            collateralAddress: JATIQUE,
            amountOfJatCoinBorrowed: 10000,
            borrowTime: block.timestamp
        });
        console.log("this is the block timestamp", block.timestamp);
        jatEngine.setUserBorrowDetails(JATIQUE, testId, details);

        JatEngine.BorrowDetailsWithInterest memory retrievedDetailsWithInterest =
            jatEngine.getUserBorrowDetails(JATIQUE, testId);
        JatEngine.BorrowDetails memory retrievedDetails = retrievedDetailsWithInterest.borrowDetails;

        assertEq(retrievedDetails.collateralAddress, details.collateralAddress);
        assertEq(retrievedDetails.amountOfJatCoinBorrowed, details.amountOfJatCoinBorrowed);
        assertEq(retrievedDetails.borrowTime, details.borrowTime);

        console.log("User borrow details set and retrieved successfully");
        console.log("Collateral Address: ", retrievedDetails.collateralAddress);
        console.log("Amount Borrowed: ", retrievedDetails.amountOfJatCoinBorrowed);
        console.log("Borrow Time: ", retrievedDetails.borrowTime);
    }

    function testGetERC20Balance() public {
        // Mint some WETH and WBTC tokens to the JATIQUE address for testing
        uint256 initialWethBalance = 1000 * 10 ** 18;
        uint256 initialWbtcBalance = 500 * 10 ** 8; // Assuming WBTC has 8 decimals

        // Mock WETH and WBTC contracts
        IERC20(config.weth).transfer(JATIQUE, initialWethBalance);
        IERC20(config.wbtc).transfer(JATIQUE, initialWbtcBalance);

        // Test WETH balance
        uint256 wethBalance = jatEngine.getERC20Balance(JATIQUE, "WETH");
        console.log("WETH Balance: ", wethBalance);
        assertEq(wethBalance, initialWethBalance);

        // Test WBTC balance
        uint256 wbtcBalance = jatEngine.getERC20Balance(JATIQUE, "WBTC");
        console.log("WBTC Balance: ", wbtcBalance);
        assertEq(wbtcBalance, initialWbtcBalance);

        console.log("ERC20 balances retrieved successfully");
    }
}
