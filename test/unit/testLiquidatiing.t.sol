// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployJatEngine} from "../../script/DeployJatEngine.s.sol";
import {JatStableCoin} from "../../src/JatStableCoin.sol";
import {JatEngine} from "../../src/JatEngine.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract TestJatEngine is Test {
    JatEngine jatEngine;
    JatStableCoin jatCoin;
    DeployJatEngine.Config config;
    DeployJatEngine deployerEngine;
    address borrower = makeAddr("borrower");
    address liquidator = makeAddr("liquidator");

    function setUp() public {
        deployerEngine = new DeployJatEngine();
        (jatCoin, jatEngine, config) = deployerEngine.run();

        // Mint some JatStableCoin to the liquidator for testing
        jatCoin.mint(liquidator, 1000 * 1e18);

        // Mint some collateral tokens to the borrower
        ERC20Mock(config.weth).mint(borrower, 100 * 1e18);
        ERC20Mock(config.wbtc).mint(borrower, 1 * 1e18);
    }

    function testLiquidate() public {
        console.log("Running testLiquidate...");

        // Borrower deposits collateral
        vm.startPrank(borrower);
        ERC20Mock(config.weth).approve(address(jatEngine), 100 * 1e18);
        jatEngine.depositCollateral(config.weth, 100 * 1e18, borrower);

        // Borrower borrows JatStableCoin
        uint256 amountToBorrow = 50 * 1e18; // 50 JatStableCoin
        jatEngine.borrowJatCoin(amountToBorrow, config.weth);
        vm.stopPrank();

        // Simulate a drop in collateral value
        MockV3Aggregator(config.wethUsdPriceFeed).updateAnswer(2000 * 1e18); // Drop ETH price to $2000

        // Check health factor of the borrower
        uint256 healthFactor = jatEngine.getHealthFactor(borrower);
        console.log("Health Factor after price drop: ", healthFactor);
        assert(healthFactor < 1e18); // Ensure health factor is below 1

        // Liquidator performs liquidation
        vm.startPrank(liquidator);
        jatCoin.approve(address(jatEngine), amountToBorrow);
        jatEngine.liquidate(borrower, 1, amountToBorrow);
        vm.stopPrank();

        // Check the borrower's debt and collateral after liquidation
        uint256 remainingDebt = jatEngine.getUserTotalJatCoinedBorrowedWithInterest(borrower);
        uint256 remainingCollateral = jatEngine.getUserCollateralAmount(borrower, config.weth);
        console.log("Remaining Debt: ", remainingDebt);
        console.log("Remaining Collateral: ", remainingCollateral);

        // Check the liquidator's received collateral
        uint256 liquidatorCollateral = ERC20Mock(config.weth).balanceOf(liquidator);
        console.log("Liquidator's Collateral: ", liquidatorCollateral);

        // Assertions
        assertEq(remainingDebt, 0); // Debt should be fully repaid
        assertEq(liquidatorCollateral, 55 * 1e18); // Liquidator should receive collateral with bonus
    }
}
