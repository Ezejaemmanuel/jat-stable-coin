// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployJatEngine} from "../../script/DeployJatEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {JatStableCoin} from "../../src/JatStableCoin.sol";
import {JatEngine} from "../../src/JatEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract TestJatEngine is Test {
    JatEngine jatEngine;
    JatStableCoin jatCoin;
    HelperConfig config;
    ERC20Mock erc20Mock;

    address JATIQUE = makeAddr("jatique");

    function setUp() public {
        DeployJatEngine deployerEngine = new DeployJatEngine();
        (jatCoin, jatEngine, config) = deployerEngine.run();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = config.activeNetworkConfig();
        // (ethUsdPriceFeedAddress, btcUsdPriceFeedAddress, weth, wbtc,) = config.activeNetworkConfig();
        erc20Mock = ERC20Mock(weth);
    }

    function testingIfTheDepositFunctionIsWorkingProperly() public {
        int256 ethUsdPrice = config.ETH_USD_PRICE();
        uint256 amountOfWethToDeposit = 1e18;
        uint256 decimal = config.DECIMALS();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = config.activeNetworkConfig();
        vm.startPrank(JATIQUE);

        // Mint WETH to JATIQUE
        erc20Mock.mint(JATIQUE, amountOfWethToDeposit);
        uint256 balanceBefore = erc20Mock.balanceOf(JATIQUE);
        // console.log("This is the WETH balance of the user before", balanceBefore);

        // Assert balance before deposit
        assert(balanceBefore == amountOfWethToDeposit);

        uint256 initialAmount = jatEngine.getUserCollateralAmount(JATIQUE, weth);
        // console.log("This is the initial amount of the collateral before deposit", initialAmount);

        // Approve and deposit collateral
        erc20Mock.approve(address(jatEngine), amountOfWethToDeposit);
        jatEngine.depositCollateral(weth, amountOfWethToDeposit, JATIQUE);

        uint256 balanceAfter = erc20Mock.balanceOf(JATIQUE);
        // console.log("This is the balance of WETH of the user after", balanceAfter);

        // Assert balance after deposit
        assert(balanceAfter == balanceBefore - amountOfWethToDeposit);

        uint256 amountAfterDeposit = jatEngine.getUserCollateralAmount(JATIQUE, weth);
        // console.log("This is the amount after the deposit", amountAfterDeposit);

        // Assert amount after deposit
        assert(amountAfterDeposit == initialAmount + amountOfWethToDeposit);

        vm.stopPrank();
    }

    function testIfTheBorrowMechanismIsWorkingProperly() public {
        uint256 amountOfWethToDeposit = 1000e18;

        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey,
            uint256 interestRate
        ) = config.activeNetworkConfig();

        vm.startPrank(JATIQUE);

        // Log initial values
        uint256 initialBorrowCount = jatEngine.getUserBorrowCount(JATIQUE);
        console.log("Initial borrow count:", initialBorrowCount);

        JatEngine.BorrowDetails memory initialBorrowDetails = jatEngine.getUserBorrowDetails(JATIQUE, 1);
        console.log("Initial amount of JatCoin borrowed:", initialBorrowDetails.amountOfJatCoinBorrowed);

        uint256 initialJatCoinBalance = jatCoin.balanceOf(JATIQUE);
        console.log("Initial JatCoin balance of the user:", initialJatCoinBalance);

        // Expect revert and perform borrow operation
        // vm.expectRevert(abi.encodeWithSelector(JatEngine.JatEngine__HealthFactorIsNotMaintained.selector));
        erc20Mock.mint(JATIQUE, amountOfWethToDeposit);
        uint256 balanceBefore = erc20Mock.balanceOf(JATIQUE);
        // console.log("This is the WETH balance of the user before", balanceBefore);

        // Assert balance before deposit

        uint256 initialAmount = jatEngine.getUserCollateralAmount(JATIQUE, weth);
        // console.log("This is the initial amount of the collateral before deposit", initialAmount);

        // Approve and deposit collateral
        erc20Mock.approve(address(jatEngine), amountOfWethToDeposit);
        jatEngine.depositCollateral(weth, amountOfWethToDeposit, JATIQUE);

        uint256 balanceAfter = erc20Mock.balanceOf(JATIQUE);
        // console.log("This is the balance of WETH of the user after", balanceAfter);

        // Assert balance after deposit

        uint256 amountAfterDeposit = jatEngine.getUserCollateralAmount(JATIQUE, weth);
        // console.log("This is the amount after the deposit", amountAfterDeposit);

        // Assert amount after deposit
        jatEngine.borrowJatCoin(10, weth);

        // Log updated values
        uint256 updatedBorrowCount = jatEngine.getUserBorrowCount(JATIQUE);
        console.log("Updated borrow count:", updatedBorrowCount);

        JatEngine.BorrowDetails memory updatedBorrowDetails = jatEngine.getUserBorrowDetails(JATIQUE, 1);
        console.log("Updated amount of JatCoin borrowed:", updatedBorrowDetails.amountOfJatCoinBorrowed);

        uint256 updatedJatCoinBalance = jatCoin.balanceOf(JATIQUE);
        console.log("Updated JatCoin balance of the user:", updatedJatCoinBalance);

        vm.stopPrank();

        // Perform comparisons
        // assert(updatedBorrowCount == initialBorrowCount + 1);
        // assert(updatedBorrowDetails.amountOfJatCoinBorrowed > initialBorrowDetails.amountOfJatCoinBorrowed);
        // assert(updatedJatCoinBalance > initialJatCoinBalance);
    }

    function testRepaymentFunction() public {
        uint256 amountOfWethToDeposit = 10e18;
        uint256 amountToBorrow = 1000;
        uint256 amountToRepay = 300;

        (,, address weth,,,) = config.activeNetworkConfig();
        erc20Mock = ERC20Mock(weth);

        vm.startPrank(JATIQUE);
        // Mint WETH to JATIQUE and log initial balance
        erc20Mock.mint(JATIQUE, amountOfWethToDeposit);
        uint256 initialWethBalance = erc20Mock.balanceOf(JATIQUE);
        console.log("Initial WETH Balance:", initialWethBalance);

        // Deposit WETH as collateral and log balance after deposit
        erc20Mock.approve(address(jatEngine), amountOfWethToDeposit);
        console.log("WETH Approved for Deposit:", amountOfWethToDeposit);

        jatEngine.depositCollateral(weth, amountOfWethToDeposit, JATIQUE);
        uint256 wethBalanceAfterDeposit = erc20Mock.balanceOf(JATIQUE);
        console.log("WETH Balance After Deposit:", wethBalanceAfterDeposit);

        // Borrow JatCoin and log details
        jatEngine.borrowJatCoin(amountToBorrow, weth);
        uint256 jatCoinBalanceAfterBorrow = jatCoin.balanceOf(JATIQUE);
        console.log("JatCoin Balance After Borrow:", jatCoinBalanceAfterBorrow);

        JatEngine.BorrowDetails memory borrowDetailsAfterBorrow = jatEngine.getUserBorrowDetails(JATIQUE, 1);
        console.log("Borrow Details After Borrow: Amount Borrowed:", borrowDetailsAfterBorrow.amountOfJatCoinBorrowed);

        // Log initial collateral amount
        uint256 initialCollateralAmount = jatEngine.getUserCollateralAmount(JATIQUE, weth);
        console.log("Initial Collateral Amount:", initialCollateralAmount);

        // Perform repayment and log details
        jatCoin.approve(address(jatEngine), amountToRepay);
        console.log("JatCoin Approved for Repayment:", amountToRepay);
        erc20Mock.approve(address(jatEngine), 10e18);

        jatEngine.repayMent(1, amountToRepay);
        uint256 jatCoinBalanceAfterRepay = jatCoin.balanceOf(JATIQUE);
        console.log("JatCoin Balance After Repayment:", jatCoinBalanceAfterRepay);

        JatEngine.BorrowDetails memory borrowDetailsAfterRepay = jatEngine.getUserBorrowDetails(JATIQUE, 1);
        console.log("Borrow Details After Repayment: Amount Borrowed:", borrowDetailsAfterRepay.amountOfJatCoinBorrowed);

        uint256 collateralAmountAfterRepay = jatEngine.getUserCollateralAmount(JATIQUE, weth);
        console.log("Collateral Amount After Repayment:", collateralAmountAfterRepay);

        vm.stopPrank();

        // Assertions
        assert(wethBalanceAfterDeposit == initialWethBalance - amountOfWethToDeposit);
        console.log("Assertion 1 Passed: WETH Balance After Deposit is Correct");

        assert(jatCoinBalanceAfterBorrow == amountToBorrow);
        console.log("Assertion 2 Passed: JatCoin Balance After Borrow is Correct");

        assert(borrowDetailsAfterBorrow.amountOfJatCoinBorrowed == amountToBorrow);
        console.log("Assertion 3 Passed: Borrow Details After Borrow are Correct");

        assert(jatCoinBalanceAfterRepay == jatCoinBalanceAfterBorrow - amountToRepay);
        console.log("Assertion 4 Passed: JatCoin Balance After Repayment is Correct");

        assert(borrowDetailsAfterRepay.amountOfJatCoinBorrowed == amountToBorrow - amountToRepay);
        console.log("Assertion 5 Passed: Borrow Details After Repayment are Correct");

        assert(
            collateralAmountAfterRepay
                == initialCollateralAmount - jatEngine.convertUsdValueToCollateral(weth, amountToRepay)
        );
        console.log("Assertion 6 Passed: Collateral Amount After Repayment is Correct");
    }

    function testIfTheBurnFunctionalityWork() public {}
}
