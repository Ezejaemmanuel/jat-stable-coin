// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployJatEngine} from "../../script/DeployJatEngine.s.sol";
import {JatStableCoin} from "../../src/JatStableCoin.sol";
import {JatEngine} from "../../src/JatEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract TestJatEngine is Test {
    JatEngine jatEngine;
    JatStableCoin jatCoin;
    DeployJatEngine.Config config;
    ERC20Mock erc20Mock;
    DeployJatEngine deployerEngine;

    address JATIQUE = makeAddr("jatique");

    function setUp() public {
        deployerEngine = new DeployJatEngine();
        (jatCoin, jatEngine, config) = deployerEngine.run();

        erc20Mock = ERC20Mock(config.weth);
    }

    function testingIfTheDepositFunctionIsWorkingProperly() public {
        int256 ethUsdPrice = deployerEngine.ETH_USD_PRICE();
        uint256 amountOfWethToDeposit = 1;
        uint8 decimal = deployerEngine.DECIMALS();

        vm.startPrank(JATIQUE);

        // Mint WETH to JATIQUE
        erc20Mock.mint(JATIQUE, amountOfWethToDeposit);
        uint256 balanceBefore = erc20Mock.balanceOf(JATIQUE);
        console.log("This is the WETH balance of the user before", balanceBefore);

        // Assert balance before deposit
        assert(balanceBefore == amountOfWethToDeposit);

        uint256 initialAmount = jatEngine.getUserCollateralAmount(JATIQUE, address(erc20Mock));
        console.log("This is the initial amount of the collateral before deposit", initialAmount);

        // Approve and deposit collateral
        erc20Mock.approve(address(jatEngine), amountOfWethToDeposit);
        jatEngine.depositCollateral(address(erc20Mock), amountOfWethToDeposit, JATIQUE);

        uint256 balanceAfter = erc20Mock.balanceOf(JATIQUE);
        console.log("This is the balance of WETH of the user after", balanceAfter);

        // Assert balance after deposit
        assert(balanceAfter == balanceBefore - amountOfWethToDeposit);

        uint256 amountAfterDeposit = jatEngine.getUserCollateralAmount(JATIQUE, address(erc20Mock));
        console.log("This is the amount after the deposit", amountAfterDeposit);

        // Assert amount after deposit
        assert(amountAfterDeposit == initialAmount + amountOfWethToDeposit);

        vm.stopPrank();
    }

    function testIfTheBorrowMechanismIsWorkingProperly() public {
        uint256 amountOfWethToDeposit = 1000e18;

        vm.startPrank(JATIQUE);

        // Log initial values
        uint256 initialBorrowCount = jatEngine.getUserBorrowCount(JATIQUE);
        console.log("Initial borrow count:", initialBorrowCount);

        // Mint WETH to JATIQUE
        erc20Mock.mint(JATIQUE, amountOfWethToDeposit);
        uint256 balanceBefore = erc20Mock.balanceOf(JATIQUE);
        console.log("This is the WETH balance of the user before", balanceBefore);

        // Assert balance before deposit
        assert(balanceBefore == amountOfWethToDeposit);

        uint256 initialAmount = jatEngine.getUserCollateralAmount(JATIQUE, address(erc20Mock));
        console.log("This is the initial amount of the collateral before deposit", initialAmount);

        // Approve and deposit collateral
        erc20Mock.approve(address(jatEngine), amountOfWethToDeposit);
        jatEngine.depositCollateral(address(erc20Mock), amountOfWethToDeposit, JATIQUE);

        uint256 balanceAfter = erc20Mock.balanceOf(JATIQUE);
        console.log("This is the balance of WETH of the user after", balanceAfter);

        // Assert balance after deposit
        assert(balanceAfter == balanceBefore - amountOfWethToDeposit);

        uint256 amountAfterDeposit = jatEngine.getUserCollateralAmount(JATIQUE, address(erc20Mock));
        console.log("This is the amount after the deposit", amountAfterDeposit);

        // Assert amount after deposit
        assert(amountAfterDeposit == initialAmount + amountOfWethToDeposit);

        // Borrow JatCoin
        uint256 amountToBorrow = 10;
        jatEngine.borrowJatCoin(amountToBorrow, address(erc20Mock));

        // Log updated values
        uint256 updatedBorrowCount = jatEngine.getUserBorrowCount(JATIQUE);
        console.log("Updated borrow count:", updatedBorrowCount);

        JatEngine.BorrowDetailsWithInterest memory updatedBorrowDetailsWithInterest =
            jatEngine.getUserBorrowDetails(JATIQUE, 1);
        JatEngine.BorrowDetails memory updatedBorrowDetails = updatedBorrowDetailsWithInterest.borrowDetails;
        console.log("Updated amount of JatCoin borrowed:", updatedBorrowDetails.amountOfJatCoinBorrowed);

        uint256 updatedJatCoinBalance = jatCoin.balanceOf(JATIQUE);
        console.log("Updated JatCoin balance of the user:", updatedJatCoinBalance);

        vm.stopPrank();

        // Perform comparisons
        assert(updatedBorrowCount == initialBorrowCount + 1);
        assert(updatedBorrowDetails.amountOfJatCoinBorrowed == amountToBorrow);
        assert(updatedJatCoinBalance == amountToBorrow);
    }

    function testrepayJatCoinFunction() public {
        uint256 amountOfWethToDeposit = 10e18;
        uint256 amountToBorrow = 1000;
        uint256 amountToRepay = 300;

        vm.startPrank(JATIQUE);
        // Mint WETH to JATIQUE and log initial balance
        erc20Mock.mint(JATIQUE, amountOfWethToDeposit);
        uint256 initialWethBalance = erc20Mock.balanceOf(JATIQUE);
        console.log("Initial WETH Balance:", initialWethBalance);

        // Deposit WETH as collateral and log balance after deposit
        erc20Mock.approve(address(jatEngine), amountOfWethToDeposit);
        console.log("WETH Approved for Deposit:", amountOfWethToDeposit);

        jatEngine.depositCollateral(address(erc20Mock), amountOfWethToDeposit, JATIQUE);
        uint256 wethBalanceAfterDeposit = erc20Mock.balanceOf(JATIQUE);
        console.log("WETH Balance After Deposit:", wethBalanceAfterDeposit);

        // Borrow JatCoin and log details
        jatEngine.borrowJatCoin(amountToBorrow, address(erc20Mock));
        uint256 jatCoinBalanceAfterBorrow = jatCoin.balanceOf(JATIQUE);
        console.log("JatCoin Balance After Borrow:", jatCoinBalanceAfterBorrow);

        JatEngine.BorrowDetailsWithInterest memory borrowDetailsWithInterestAfterBorrow =
            jatEngine.getUserBorrowDetails(JATIQUE, 1);
        JatEngine.BorrowDetails memory borrowDetailsAfterBorrow = borrowDetailsWithInterestAfterBorrow.borrowDetails;
        console.log("Borrow Details After Borrow: Amount Borrowed:", borrowDetailsAfterBorrow.amountOfJatCoinBorrowed);

        // Log initial collateral amount
        uint256 initialCollateralAmount = jatEngine.getUserCollateralAmount(JATIQUE, address(erc20Mock));
        console.log("Initial Collateral Amount:", initialCollateralAmount);

        // Perform repayJatCoin and log details
        jatCoin.approve(address(jatEngine), amountToRepay);
        console.log("JatCoin Approved for repayJatCoin:", amountToRepay);
        erc20Mock.approve(address(jatEngine), 10e18);

        jatEngine.repayJatCoin(1, amountToRepay);
        uint256 jatCoinBalanceAfterRepay = jatCoin.balanceOf(JATIQUE);
        console.log("JatCoin Balance After repayJatCoin:", jatCoinBalanceAfterRepay);

        JatEngine.BorrowDetailsWithInterest memory borrowDetailsWithInterestAfterRepay =
            jatEngine.getUserBorrowDetails(JATIQUE, 1);
        JatEngine.BorrowDetails memory borrowDetailsAfterRepay = borrowDetailsWithInterestAfterRepay.borrowDetails;
        console.log(
            "Borrow Details After repayJatCoin: Amount Borrowed:", borrowDetailsAfterRepay.amountOfJatCoinBorrowed
        );

        uint256 collateralAmountAfterRepay = jatEngine.getUserCollateralAmount(JATIQUE, address(erc20Mock));
        console.log("Collateral Amount After repayJatCoin:", collateralAmountAfterRepay);

        vm.stopPrank();

        // Assertions
        assert(wethBalanceAfterDeposit == initialWethBalance - amountOfWethToDeposit);
        console.log("Assertion 1 Passed: WETH Balance After Deposit is Correct");

        assert(jatCoinBalanceAfterBorrow == amountToBorrow);
        console.log("Assertion 2 Passed: JatCoin Balance After Borrow is Correct");

        assert(borrowDetailsAfterBorrow.amountOfJatCoinBorrowed == amountToBorrow);
        console.log("Assertion 3 Passed: Borrow Details After Borrow are Correct");

        assert(jatCoinBalanceAfterRepay == jatCoinBalanceAfterBorrow - amountToRepay);
        console.log("Assertion 4 Passed: JatCoin Balance After repayJatCoin is Correct");

        assert(borrowDetailsAfterRepay.amountOfJatCoinBorrowed == amountToBorrow - amountToRepay);
        console.log("Assertion 5 Passed: Borrow Details After repayJatCoin are Correct");

        assert(
            collateralAmountAfterRepay
                == initialCollateralAmount - jatEngine.convertUsdValueToCollateral(address(erc20Mock), amountToRepay)
        );
        console.log("Assertion 6 Passed: Collateral Amount After repayJatCoin is Correct");
    }

    // function testIfTheBurnFunctionalityWork() public {
    //     uint256 amountOfWethToDeposit = 10e18;
    //     uint256 amountToBorrow = 1000;
    //     uint256 amountToRepay = 300;

    //     vm.startPrank(JATIQUE);
    //     // Mint WETH to JATIQUE and log initial balance
    //     erc20Mock.mint(JATIQUE, amountOfWethToDeposit);
    //     uint256 initialWethBalance = erc20Mock.balanceOf(JATIQUE);
    //     console.log("Initial WETH Balance:", initialWethBalance);

    //     // Deposit WETH as collateral and log balance after deposit
    //     erc20Mock.approve(address(jatEngine), amountOfWethToDeposit);
    //     console.log("WETH Approved for Deposit:", amountOfWethToDeposit);

    //     jatEngine.depositCollateral(address(erc20Mock), amountOfWethToDeposit, JATIQUE);
    //     uint256 wethBalanceAfterDeposit = erc20Mock.balanceOf(JATIQUE);
    //     console.log("WETH Balance After Deposit:", wethBalanceAfterDeposit);

    //     // Borrow JatCoin and log details
    //     jatEngine.borrowJatCoin(amountToBorrow, address(erc20Mock));
    //     uint256 jatCoinBalanceAfterBorrow = jatCoin.balanceOf(JATIQUE);
    //     console.log("JatCoin Balance After Borrow:", jatCoinBalanceAfterBorrow);

    //     JatEngine.BorrowDetailsWithInterest memory borrowDetailsWithInterestAfterBorrow =
    //         jatEngine.getUserBorrowDetails(JATIQUE, 1);
    //     JatEngine.BorrowDetails memory borrowDetailsAfterBorrow = borrowDetailsWithInterestAfterBorrow.borrowDetails;
    //     console.log("Borrow Details After Borrow: Amount Borrowed:", borrowDetailsAfterBorrow.amountOfJatCoinBorrowed);

    //     // Log initial collateral amount
    //     uint256 initialCollateralAmount = jatEngine.getUserCollateralAmount(JATIQUE, address(erc20Mock));
    //     console.log("Initial Collateral Amount:", initialCollateralAmount);

    //     // Perform repayJatCoin and log details
    //     jatCoin.approve(address(jatEngine), amountToRepay);
    //     console.log("JatCoin Approved for repayJatCoin:", amountToRepay);
    //     erc20Mock.approve(address(jatEngine), 10e18);

    //     jatEngine.repayJatCoin(1, amountToRepay);
    //     uint256 jatCoinBalanceAfterRepay = jatCoin.balanceOf(JATIQUE);
    //     console.log("JatCoin Balance After repayJatCoin:", jatCoinBalanceAfterRepay);

    //     JatEngine.BorrowDetailsWithInterest memory borrowDetailsWithInterestAfterRepay =
    //         jatEngine.getUserBorrowDetails(JATIQUE, 1);
    //     JatEngine.BorrowDetails memory borrowDetailsAfterRepay = borrowDetailsWithInterestAfterRepay.borrowDetails;
    //     console.log("Borrow Details After repayJatCoin: Amount Borrowed:", borrowDetailsAfterRepay.amountOfJatCoinBorrowed);

    //     uint256 collateralAmountAfterRepay = jatEngine.getUserCollateralAmount(JATIQUE, address(erc20Mock));
    //     console.log("Collateral Amount After repayJatCoin:", collateralAmountAfterRepay);

    //     // Burn the remaining JatCoin
    //     uint256 amountToBurn = jatCoinBalanceAfterRepay;
    //     jatCoin.approve(address(jatEngine), amountToBurn);
    //     jatEngine.repayJatCoin(1, amountToBurn);

    //     uint256 jatCoinBalanceAfterBurn = jatCoin.balanceOf(JATIQUE);
    //     console.log("JatCoin Balance After Burn:", jatCoinBalanceAfterBurn);

    //     vm.stopPrank();

    //     // Assertions
    //     assert(jatCoinBalanceAfterBurn == 0);
    //     console.log("Assertion 1 Passed: JatCoin Balance After Burn is Correct");

    //     assert(borrowDetailsAfterRepay.amountOfJatCoinBorrowed == 0);
    //     console.log("Assertion 2 Passed: Borrow Details After Burn are Correct");

    //     assert(
    //         collateralAmountAfterRepay
    //             == initialCollateralAmount
    //                 - jatEngine.convertUsdValueToCollateral(address(erc20Mock), amountToRepay + amountToBurn)
    //     );
    //     console.log("Assertion 3 Passed: Collateral Amount After Burn is Correct");
    // }
}
