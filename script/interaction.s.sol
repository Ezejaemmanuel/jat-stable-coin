// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "../lib/foundry-devops/src/DevOpsTools.sol";
import {JatEngine} from "../src/JatEngine.sol";
import {JatStableCoin} from "../src/JatStableCoin.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract SimulateDepositsAndBorrowings is Script {
    address JATIQUE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address jatStableCoinAddress;
    address jatEngineAddress;

    function run() external {
        console.log("Starting run function");

        jatEngineAddress = DevOpsTools.get_most_recent_deployment("JatEngine", block.chainid);
        console.log("jatEngineAddress retrieved:", jatEngineAddress);

        jatStableCoinAddress = DevOpsTools.get_most_recent_deployment("JatStableCoin", block.chainid);
        console.log("jatStableCoinAddress retrieved:", jatStableCoinAddress);

        JatEngine jatEngine = JatEngine(jatEngineAddress);
        console.log("JatEngine contract instance created");

        // Get the collateral addresses from the getter functions
        console.log("Attempting to get collateral addresses");
        // address[] memory collateralAddresses = jatEngine.getCollateralAddresses();
        address[] memory collateralAddresses = new address[](2);
        collateralAddresses[0] = 0x238213078DbD09f2D15F4c14c02300FA1b2A81BB;
        collateralAddresses[1] = 0xd85BdcdaE4db1FAEB8eF93331525FE68D7C8B3f0;
        console.log("Collateral addresses retrieved:", collateralAddresses.length);

        require(collateralAddresses.length >= 2, "Not enough collateral addresses");
        console.log("Passed collateral addresses length check");

        uint256 depositAmount;

        for (uint256 i = 0; i < 2; i++) {
            address collateralAddress = collateralAddresses[i];
            console.log("Collateral address", i + 1, ":", collateralAddress);

            ERC20Mock collateralToken = ERC20Mock(collateralAddress);
            console.log("ERC20Mock instance created for collateral address", collateralAddress);

            // Simulate 10 deposits
            for (uint256 j = 0; j < 10; j++) {
                uint256 r = 1 + j;
                depositAmount = 1e18 * r;
                console.log("Deposit amount for iteration", j, ":", depositAmount);

                vm.startBroadcast();
                console.log("Minting", depositAmount, "tokens to", JATIQUE);
                collateralToken.mint(JATIQUE, depositAmount);

                console.log("Approving", depositAmount, "tokens to JatEngine");
                collateralToken.approve(address(jatEngine), depositAmount);

                console.log("Depositing collateral");
                jatEngine.depositCollateral(collateralAddress, depositAmount, JATIQUE);
                vm.stopBroadcast();

                console.log("Deposited", depositAmount, "of collateral", i + 1);
            }

            // Simulate 10 borrowings with larger values in dollars
            for (uint256 k = 1; k <= 10; k++) {
                uint256 borrowAmount = k * 1000; // Unique borrow amount
                console.log("Borrow amount for iteration", k, ":", borrowAmount);

                vm.startBroadcast();
                console.log("Borrowing JatCoin");
                jatEngine.borrowJatCoin(borrowAmount, collateralAddress);
                vm.stopBroadcast();

                console.log("Borrowed", borrowAmount, "of JatCoin using collateral", i + 1);
            }

            // Simulate 5 more borrowings with larger values in dollars
            for (uint256 l = 1; l <= 5; l++) {
                uint256 borrowAmount = l * 2000; // Unique borrow amount
                console.log("Additional borrow amount for iteration", l, ":", borrowAmount);

                vm.startBroadcast();
                console.log("Borrowing more JatCoin");
                jatEngine.borrowJatCoin(borrowAmount, collateralAddress);
                vm.stopBroadcast();

                console.log("Borrowed", borrowAmount, "of JatCoin using collateral", i + 1);
            }

            // Simulate 5 repayJatCoins with normal dollar values
            for (uint256 m = 1; m <= 5; m++) {
                uint256 repayJatCoinAmount = m * 500; // Unique repayJatCoin amount in dollars
                console.log("repayJatCoin amount for iteration", m, ":", repayJatCoinAmount);

                vm.startBroadcast();
                console.log("Approving JatStableCoin repayJatCoin");
                JatStableCoin(jatStableCoinAddress).approve(address(jatEngine), repayJatCoinAmount);

                console.log("Repaying JatCoin");
                jatEngine.repayJatCoin(1, repayJatCoinAmount);
                vm.stopBroadcast();

                console.log("Repaid", repayJatCoinAmount, "of JatCoin using collateral", i + 1);
            }
        }

        console.log("Run function completed");
    }
}

// pragma solidity ^0.8.20;

// import {Script} from "forge-std/Script.sol";
// import {JatStableCoin} from "../src/JatStableCoin.sol";
// import {JatEngine} from "../src/JatEngine.sol";
// import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
// import {DevOpsTools} from "../lib/foundry-devops/src/DevOpsTools.sol";
// import {console} from "forge-std/console.sol";

// contract SimulateUserActions is Script {
//     address public constant WETH_ADDRESS = 0x238213078DbD09f2D15F4c14c02300FA1b2A81BB;
//     address public constant WBTC_ADDRESS = 0xd85BdcdaE4db1FAEB8eF93331525FE68D7C8B3f0;

//     function run() public {
//         uint256 deployerPrivateKey = vm.envUint("DEFAULT_ANVIL_KEY");

//         // Get the latest deployed JatEngine and JatStableCoin addresses
//         address jatEngineAddress = DevOpsTools.get_most_recent_deployment("JatEngine", block.chainid);
//         address jatStableCoinAddress = DevOpsTools.get_most_recent_deployment("JatStableCoin", block.chainid);

//         console.log("jatEngineAddress retrieved:", jatEngineAddress);
//         console.log("jatStableCoinAddress retrieved:", jatStableCoinAddress);

//         JatEngine jatEngine = JatEngine(jatEngineAddress);
//         JatStableCoin jatStableCoin = JatStableCoin(jatStableCoinAddress);

//         // Addresses for collateral tokens
//         address[] memory collateralAddresses = new address[](2);
//         collateralAddresses[0] = WETH_ADDRESS;
//         collateralAddresses[1] = WBTC_ADDRESS;

//         vm.startBroadcast();

//         address user = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Replace with the user address you want to test with

//         // Simulate deposits
//         for (uint256 i = 0; i < collateralAddresses.length; i++) {
//             ERC20Mock collateral = ERC20Mock(collateralAddresses[i]);
//             uint256 amountToMint = 1000e18; // Mint 1000 tokens for each collateral type

//             // Mint tokens to the user
//             collateral.mint(user, amountToMint);
//             console.log("Minted", amountToMint, "tokens to user for collateral", i);

//             // Approve and deposit collateral
//             vm.startPrank(user);
//             collateral.approve(jatEngineAddress, amountToMint);
//             jatEngine.depositCollateral(collateralAddresses[i], amountToMint, user);
//             console.log("Deposited", amountToMint, "tokens as collateral for user");
//             vm.stopPrank();
//         }

//         // Simulate borrowings
//         uint256 borrowAmount = 500e18; // Borrow 500 JatStableCoins each time
//         for (uint256 i = 0; i < 5; i++) {
//             vm.startPrank(user);
//             jatEngine.borrowJatCoin(borrowAmount, WETH_ADDRESS); // Assuming borrowing against WETH
//             console.log("Borrowed", borrowAmount, "JatStableCoins for user, iteration:", i);
//             vm.stopPrank();
//         }

//         // Simulate repayJatCoins
//         uint256 repayAmount = 200e18; // Repay 200 JatStableCoins each time
//         for (uint256 i = 0; i < 3; i++) {
//             vm.startPrank(user);
//             jatStableCoin.approve(jatEngineAddress, repayAmount);
//             jatEngine.repayJatCoin(1, repayAmount); // Assuming repaying the first borrow ID
//             console.log("Repaid", repayAmount, "JatStableCoins for user, iteration:", i);
//             vm.stopPrank();
//         }

//         vm.stopBroadcast();
//     }
// }
