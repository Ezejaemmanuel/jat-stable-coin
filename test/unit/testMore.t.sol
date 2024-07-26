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

    function testCalculateCompoundInterest() public {
        console.log("Running testCalculateCompoundInterest...");

        // Set a single initial amount, interest rate, and time period
        uint256 initialAmount = 1000 * 1e18; // 1000 JatCoins
        uint256 interestRate = 5; // 5%
        uint256 timeElapsedTestMode = 365; // 1 year in test mode (365 seconds)
        uint256 timeElapsedNonTestMode = 365 days; // 1 year in non-test mode

        // Set the test mode to true
        jatEngine.setTestMode(true);

        uint256 borrowTime = block.timestamp;
        uint256 simulatedTime = borrowTime + timeElapsedTestMode;

        // Move the block timestamp forward
        vm.warp(simulatedTime);
        console.log("Simulated Time (Test Mode): ", simulatedTime);

        console.log("Initial Amount: ", initialAmount);
        console.log("Interest Rate: ", interestRate);
        console.log("Time Elapsed (Test Mode): ", timeElapsedTestMode);

        // Hardcoded expected amount for test mode
        uint256 expectedAmountTestMode = 1050 * 1e18; // 5% interest for 1 year on 1000 JatCoins

        console.log("Expected Amount (Test Mode): ", expectedAmountTestMode);

        // Call the calculateCompoundInterest function
        uint256 returnedAmountTestMode = jatEngine.calculateCompoundInterest(borrowTime, initialAmount, interestRate);
        console.log("Returned Amount (Test Mode): ", returnedAmountTestMode);

        // Assert that the returned value is as expected
        assertEq(returnedAmountTestMode, expectedAmountTestMode);

        // Set the test mode to false and repeat the test
        jatEngine.setTestMode(false);

        borrowTime = block.timestamp;
        simulatedTime = borrowTime + timeElapsedNonTestMode;

        // Move the block timestamp forward
        vm.warp(simulatedTime);
        console.log("Simulated Time (Non-Test Mode): ", simulatedTime);

        console.log("Initial Amount: ", initialAmount);
        console.log("Interest Rate: ", interestRate);
        console.log("Time Elapsed (Non-Test Mode): ", timeElapsedNonTestMode);

        // Hardcoded expected amount for non-test mode
        uint256 expectedAmountNonTestMode = 1050 * 1e18; // 5% interest for 1 year on 1000 JatCoins

        console.log("Expected Amount (Non-Test Mode): ", expectedAmountNonTestMode);

        // Call the calculateCompoundInterest function
        uint256 returnedAmountNonTestMode = jatEngine.calculateCompoundInterest(borrowTime, initialAmount, interestRate);
        console.log("Returned Amount (Non-Test Mode): ", returnedAmountNonTestMode);

        // Assert that the returned value is as expected
        assertEq(returnedAmountNonTestMode, expectedAmountNonTestMode);
    }
}
