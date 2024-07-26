// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.18;

// import {Script} from "forge-std/Script.sol";
// import {JatEngine} from "../src/JatEngine.sol";
// import {JatStableCoin} from "../src/JatStableCoin.sol";
// import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
// import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
// import {console} from "forge-std/console.sol";

// contract HelperConfig is Script {
//     struct NetworkConfig {
//         address WethUsdPriceFeed;
//         address WbtcUsdPriceFeed;
//         address weth;
//         address wbtc;
//         uint256 deployerKey;
//         uint256 interestRate;
//     }

//     uint8 public constant DECIMALS = 8;
//     int256 public constant ETH_USD_PRICE = 1000e8;
//     int256 public constant BTC_USD_PRICE = 1000e8;
//     uint256 public constant DEFAULT_ANVIL = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
//     uint256 public constant INTEREST_RATE = 5;

//     NetworkConfig public activeNetworkConfig;

//     constructor() {
//         uint256 chainId;
//         assembly {
//             chainId := chainid()
//         }
//         if (chainId == 11155111) {
//             activeNetworkConfig = getSepoliaEthConfig();
//         } else {
//             activeNetworkConfig = getOrCreateAnvilEthConfig();
//         }
//     }

//     function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
//         return NetworkConfig({
//             WethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
//             WbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
//             weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
//             wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
//             deployerKey: vm.envUint("PRIVATE_KEY"),
//             interestRate: INTEREST_RATE
//         });
//     }

//     function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
//         if (activeNetworkConfig.WethUsdPriceFeed != address(0)) {
//             return activeNetworkConfig;
//         }
//         vm.startBroadcast();
//         MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
//         MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);

//         ERC20Mock wethMock = new ERC20Mock("wETH", "WETH", msg.sender, 20000e8);
//         console.log("this is the collateral address for wethMock", address(wethMock));

//         ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
//         console.log("this is the address for wbtc mock", address(wbtcMock));

//         console.log("This is the WETH mock address inside of the helper config", address(ethUsdPriceFeed));
//         vm.stopBroadcast();

//         return NetworkConfig({
//             WethUsdPriceFeed: address(ethUsdPriceFeed),
//             WbtcUsdPriceFeed: address(btcUsdPriceFeed),
//             weth: address(wethMock),
//             wbtc: address(wbtcMock),
//             deployerKey: DEFAULT_ANVIL,
//             interestRate: INTEREST_RATE
//         });
//     }

//     function getDeployerKey() public view returns (uint256) {
//         uint256 chainId;
//         assembly {
//             chainId := chainid()
//         }
//         if (chainId == 11155111) {
//             return vm.envUint("PRIVATE_KEY");
//         } else {
//             return DEFAULT_ANVIL;
//         }
//     }

//     function getActiveNetworkConfig()
//         public
//         view
//         returns (
//             address WethUsdPriceFeed,
//             address WbtcUsdPriceFeed,
//             address weth,
//             address wbtc,
//             uint256 deployerKey,
//             uint256 interestRate
//         )
//     {
//         NetworkConfig memory config = activeNetworkConfig;
//         return (
//             config.WethUsdPriceFeed,
//             config.WbtcUsdPriceFeed,
//             config.weth,
//             config.wbtc,
//             config.deployerKey,
//             config.interestRate
//         );
//     }
// }
