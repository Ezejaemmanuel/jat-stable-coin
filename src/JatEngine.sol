// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
// This is considered an Exogenous, , Anchored (pegged), Crypto Collateralized low volitility coin

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {JatStableCoin} from "./JatStableCoin.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {UD60x18, ud} from "../lib/prb-math/src/UD60x18.sol";

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

/**
 * @title JatEngine
 * @dev This contract acts as a middleman between the user and the JatStableCoin. It is responsible for deploying, burning, and minting JAT tokens.
 * @author Ezeja Emmanuel Chibuike
 * @notice This contract manages the interaction with the JatStableCoin, including minting and burning operations.
 */
contract JatEngine is ReentrancyGuard, Ownable {
    // using UD60x18 for UD60x18;

    ////////////////////

    ////////errors///////
    ///////////////////
    error JatEngine__TheyAreNotOfTheSameLength();
    error JatEngine__AmountIsLessThanZero();
    error JatEngine__CollateralAddressIsNotAllowed();
    error JatEngine__TransferNotSuccessful();
    error JatEngine__HealthFactorIsNotMaintained();
    error JatEngine__StartTimeCannotBeLessThanCurrentTime();
    error JatEngine__MintingNotSuccessful();
    error JatEngine__NoBorrowDetailsFound();
    error JatEngine__AmountToPayExceedsTotalDebtWithInterest();
    error JatEngine__BurnNotSuccessful();
    error JatEngine__AmountInCollateralIsMoreThanAvailable();
    error HealthFactorNotBelowThreshold(uint256 healthFactor);
    error RepayAmountExceedsTotalDebt(uint256 repayAmount, uint256 totalDebt);
    error CollateralAmountExceedsAvailable(uint256 collateralToSeize, uint256 availableCollateral);
    error CollateralTransferFailed();
    error JatStableCoinTransferFailed();

    JatStableCoin jatStableCoin;
    mapping(address collateralAddress => address addressOfCollateralPriceFee) private
        collateralAddressToPriceFeedAddress;

    struct BorrowDetails {
        address collateralAddress;
        uint256 amountOfJatCoinBorrowed;
        uint256 borrowTime;
    }

    mapping(address user => mapping(uint256 id => BorrowDetails)) private userBorrowDetails;
    mapping(address user => uint256 id) private userBorrowCount;
    mapping(address user => mapping(address collateralAddress => uint256 amount)) private userToCollateralAdressToAmount;
    // mapping(address user => uint256 amountOfJatCoin) private userToAmountOfJatCoin;
    address[] private listOfCollateralAddresses;
    uint256 private constant LIQUIDATION_THRESHOLD = 80;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;
    uint256 constant COMPOUNDING_PERIODS_PER_YEAR = 1;
    uint96 public constant UINT96_MAX = type(uint96).max;

    uint256 private interestRate;

    event JatCoinMinted(
        address indexed borrower, uint256 indexed borrowId, uint256 amount, address collateralAddress, uint256 timestamp
    );

    modifier NumberMustBeMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert JatEngine__AmountIsLessThanZero();
        }
        _;
    }

    modifier IsAllowedCollateralAddress(address collateralAddress) {
        if (collateralAddressToPriceFeedAddress[collateralAddress] == address(0)) {
            revert JatEngine__CollateralAddressIsNotAllowed();
        }

        _;
    }

    constructor(
        address _jatStableCoinAddress,
        address[] memory _collateralAddresses,
        address[] memory _addressOfCollateralPriceFee,
        uint256 _interestRate,
        address _initialOwner
    ) Ownable(_initialOwner) {
        console.log("this is the timestamp inside of the actual smart contract", block.timestamp);

        interestRate = _interestRate;
        jatStableCoin = JatStableCoin(_jatStableCoinAddress);
        if (_collateralAddresses.length != _addressOfCollateralPriceFee.length) {
            revert JatEngine__TheyAreNotOfTheSameLength();
        }
        for (uint256 i = 0; i < _collateralAddresses.length; i++) {
            collateralAddressToPriceFeedAddress[_collateralAddresses[i]] = _addressOfCollateralPriceFee[i];
        }
        listOfCollateralAddresses = _collateralAddresses;
    }

    /**
     * @dev Deposits collateral and allows borrowing against it.
     * This function accepts the collateral address and performs necessary checks and operations.
     */
    function depositAndBorrow(address _collateralAddress, uint256 _amountToDeposit, uint256 _amountOfJatCoinToBorrow)
        public
    {
        depositCollateral(_collateralAddress, _amountToDeposit, msg.sender);
        borrowJatCoin(_amountOfJatCoinToBorrow, _collateralAddress);
    }
    //unit tested

    function depositCollateral(address _collateralAddress, uint256 _amountToDeposit, address _addressOfWhoIsDepositing)
        public
        nonReentrant
        NumberMustBeMoreThanZero(_amountToDeposit)
        IsAllowedCollateralAddress(_collateralAddress)
    {
        userToCollateralAdressToAmount[_addressOfWhoIsDepositing][_collateralAddress] += _amountToDeposit;
        bool success =
            IERC20(_collateralAddress).transferFrom(_addressOfWhoIsDepositing, address(this), _amountToDeposit);
        if (!success) {
            revert JatEngine__TransferNotSuccessful();
        }
    }

    function borrowJatCoin(uint256 _amountOfJatCoinToBorrow, address _collateralAddress)
        public
        nonReentrant
        NumberMustBeMoreThanZero(_amountOfJatCoinToBorrow)
    {
        _mintJatCoin(_amountOfJatCoinToBorrow, _collateralAddress);
    }

    function _mintJatCoin(uint256 _amountOfJatCoinToMint, address _collateralAddress) private {
        uint256 borrowId;
        if (userBorrowCount[msg.sender] == 0) {
            borrowId = userBorrowCount[msg.sender] = 1;
        } else {
            borrowId = userBorrowCount[msg.sender]++;
        }
        BorrowDetails memory borrowDetails = BorrowDetails({
            collateralAddress: _collateralAddress,
            amountOfJatCoinBorrowed: _amountOfJatCoinToMint,
            borrowTime: block.timestamp
        });
        userBorrowDetails[msg.sender][borrowId] = borrowDetails;
        emit JatCoinMinted(msg.sender, borrowId, _amountOfJatCoinToMint, _collateralAddress, block.timestamp);
        _ensureHealthFactorIsNotBroken(msg.sender);
        bool success = jatStableCoin.mint(msg.sender, _amountOfJatCoinToMint);
        if (!success) {
            revert JatEngine__MintingNotSuccessful();
        }
    }
    //the repayment logic would have two major parts...the part that deals with the use being given back his collateral and making the proper reductions ... and then reducing the
    //the users debt for that particular borrowdetails and then transfering the users jatcoin for that dept back to jatEngine and then the jatToken buring it ......

    function repayMent(uint256 borrowId, uint256 amountInUsdAndJat)
        public
        nonReentrant
        NumberMustBeMoreThanZero(amountInUsdAndJat)
    {
        BorrowDetails storage borrowDetails = userBorrowDetails[msg.sender][borrowId];
        address collateralAddress = borrowDetails.collateralAddress;

        // Ensure borrowId exists
        if (borrowDetails.amountOfJatCoinBorrowed <= 0) {
            revert JatEngine__NoBorrowDetailsFound();
        }

        uint256 totalDebtWithInterest =
            calculateCompoundInterest(borrowDetails.borrowTime, borrowDetails.amountOfJatCoinBorrowed, interestRate);

        if (amountInUsdAndJat > totalDebtWithInterest) {
            revert JatEngine__AmountToPayExceedsTotalDebtWithInterest();
        }

        uint256 amountInCollateral = _convertUsdValueToCollateral(collateralAddress, amountInUsdAndJat);
        userToCollateralAdressToAmount[msg.sender][collateralAddress] -= amountInCollateral;
        if (userToCollateralAdressToAmount[msg.sender][collateralAddress] < 0) {
            revert JatEngine__AmountInCollateralIsMoreThanAvailable();
        }

        if (amountInUsdAndJat == totalDebtWithInterest) {
            // Clear the borrow details as the debt is fully repaid
            borrowDetails.amountOfJatCoinBorrowed = 0;
        } else {
            // Reduce the borrowed amount by the repayment amount
            borrowDetails.amountOfJatCoinBorrowed = totalDebtWithInterest - amountInUsdAndJat;
        }
        console.log("this is the inside code amount in collateral ", amountInCollateral);
        bool success = IERC20(collateralAddress).transferFrom(address(this), msg.sender, amountInCollateral);
        if (!success) {
            revert JatEngine__TransferNotSuccessful();
        }
        console.log("this is the insdie of the code amount in usd and jat", amountInUsdAndJat);
        success = jatStableCoin.transferFrom(msg.sender, address(this), amountInUsdAndJat);
        if (!success) {
            revert JatEngine__TransferNotSuccessful();
        }

        // Burn the repaid amount of JatStableCoin
        jatStableCoin.burn(amountInUsdAndJat);

        // Ensure health factor is still maintained after repayment
        _ensureHealthFactorIsNotBroken(msg.sender);
    }

    function liquidate(address borrower, uint256 borrowId, uint256 repayAmount) public nonReentrant {
        // Ensure the health factor is below the threshold for liquidation
        uint256 healthFactor = _getHealthFactor(borrower);
        if (healthFactor >= MIN_HEALTH_FACTOR) {
            revert HealthFactorNotBelowThreshold(healthFactor);
        }

        BorrowDetails storage borrowDetails = userBorrowDetails[borrower][borrowId];
        address collateralAddress = borrowDetails.collateralAddress;
        uint256 totalDebtWithInterest =
            calculateCompoundInterest(borrowDetails.borrowTime, borrowDetails.amountOfJatCoinBorrowed, interestRate);

        // Ensure the repay amount is not greater than the borrower's debt
        if (repayAmount > totalDebtWithInterest) {
            revert RepayAmountExceedsTotalDebt(repayAmount, totalDebtWithInterest);
        }

        // Calculate the collateral to be seized based on the liquidation penalty
        uint256 liquidationBonus = 10; // Set the liquidation bonus percentage (e.g., 10%)
        uint256 collateralAmountToSeize = _convertUsdValueToCollateral(
            collateralAddress, (repayAmount * (LIQUIDATION_PRECISION + liquidationBonus)) / LIQUIDATION_PRECISION
        );

        // Ensure the collateral to be seized does not exceed the available collateral
        uint256 availableCollateral = userToCollateralAdressToAmount[borrower][collateralAddress];
        if (collateralAmountToSeize > availableCollateral) {
            revert CollateralAmountExceedsAvailable(collateralAmountToSeize, availableCollateral);
        }

        // Update the borrower's debt and collateral
        borrowDetails.amountOfJatCoinBorrowed -= repayAmount;
        userToCollateralAdressToAmount[borrower][collateralAddress] -= collateralAmountToSeize;

        // Transfer the collateral to the liquidator
        bool collateralTransferSuccess = IERC20(collateralAddress).transfer(msg.sender, collateralAmountToSeize);
        if (!collateralTransferSuccess) {
            revert CollateralTransferFailed();
        }

        // Transfer the repaid JatStableCoin from the liquidator to the contract
        bool jatTransferSuccess = jatStableCoin.transferFrom(msg.sender, address(this), repayAmount);
        if (!jatTransferSuccess) {
            revert JatStableCoinTransferFailed();
        }

        // Burn the repaid JatStableCoin
        jatStableCoin.burn(repayAmount);

        // Emit an event for the liquidation
        emit Liquidation(borrower, borrowId, repayAmount, collateralAmountToSeize, msg.sender);
    }

    // This event should be added to your events section
    event Liquidation(
        address indexed borrower,
        uint256 indexed borrowId,
        uint256 repayAmount,
        uint256 collateralSeized,
        address indexed liquidator
    );

    function _ensureHealthFactorIsNotBroken(address user) private view {
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert JatEngine__HealthFactorIsNotMaintained();
        }
    }

    function _getHealthFactor(address user) private view returns (uint256) {
        (uint256 totalCollateralValueInUsd, uint256 totalJatCoinOfTheUser) = _getUserDetails(user);
        if (totalJatCoinOfTheUser == 0) {
            return UINT96_MAX;
        }
        uint256 adjusstedTotalCollateralInUsd =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (adjusstedTotalCollateralInUsd * PRECISION) / totalJatCoinOfTheUser;
    }
    //unit tested

    function _getUserDetails(address user)
        private
        view
        returns (uint256 totalCollateralInUsd, uint256 totalJatCoinTheUserHas)
    {
        uint256 collateralValueInUsd = _getUserTotalCollateralValueInUsd(user); // Renamed variable
        uint256 totalJatCoinTheUser = _getUserTotalJatCoinedBorrowedWithInterest(user);
        return (collateralValueInUsd, totalJatCoinTheUser); // Updated variable name here
    }
    //unit tested

    function _getUserTotalJatCoinedBorrowedWithInterest(address _user) private view returns (uint256) {
        uint256 totalBorrowedWithInterest = 0;
        uint256 borrowCount = userBorrowCount[_user];
        for (uint256 i = 1; i <= borrowCount; i++) {
            //   BorrowDetails memory borrow = userBorrowDetails[_user][i];
            totalBorrowedWithInterest += calculateCompoundInterest(
                userBorrowDetails[_user][i].borrowTime,
                userBorrowDetails[_user][i].amountOfJatCoinBorrowed,
                interestRate
            );

            // totalBorrowed += userBorrowDetails[_user][i].amountOfJatCoinBorrowed;
        }
        return totalBorrowedWithInterest;
    }

    //unit tested
    function calculateCompoundInterest(uint256 startTime, uint256 principal, uint256 _interestRate)
        public
        view
        returns (uint256)
    {
        // console.log("Calculating compound interest...");
        if (startTime > block.timestamp) {
            revert JatEngine__StartTimeCannotBeLessThanCurrentTime();
        }

        // Calculate time in seconds since interest start time
        // console.log("this is thte block.timestamp", block.timestamp);
        // console.log("this is the startTime", startTime);
        uint256 timeInSeconds = block.timestamp - startTime;
        // console.log("Time in seconds: %s", timeInSeconds);

        // Convert inputs to UD60x18 format
        UD60x18 principalUD = UD60x18.wrap(principal);
        // console.log("this is the interest rate", _interestRate);
        UD60x18 rateUD = UD60x18.wrap(_interestRate * 1e16); // Convert percentage to 18 decimal format (e.g., 5% -> 0.05)
        UD60x18 oneUD = UD60x18.wrap(1e18);

        // console.log("Principal: %s", principalUD.unwrap());
        // console.log("Rate: %s", rateUD.unwrap());
        // console.log("One: %s", oneUD.unwrap());

        // Calculate time in years
        UD60x18 timeInYearsUD = UD60x18.wrap(timeInSeconds).div(UD60x18.wrap(365 * 24 * 60 * 60)); // Dividing by 365 days in seconds
        // console.log("Time in years: %s", timeInYearsUD.unwrap());

        // Calculate the interest rate per period
        UD60x18 ratePerPeriodUD = rateUD.div(UD60x18.wrap(1e18));
        // console.log("Rate per period: %s", ratePerPeriodUD.unwrap());

        // Calculate compound factor (1 + rate)
        UD60x18 compoundFactorUD = oneUD.add(ratePerPeriodUD);
        // console.log("Compound factor: %s", compoundFactorUD.unwrap());

        // Calculate compound factor ^ time
        UD60x18 compoundFactorPowUD = compoundFactorUD.pow(timeInYearsUD);
        // console.log("Compound factor ^ time: %s", compoundFactorPowUD.unwrap());

        // Calculate total amount
        UD60x18 totalAmountUD = principalUD.mul(compoundFactorPowUD);
        // console.log("Total amount (UD60x18): %s", totalAmountUD.unwrap());

        // Convert back to uint256 and return
        uint256 totalAmount = totalAmountUD.unwrap();
        // console.log("Total amount (uint256): %s", totalAmount);

        return totalAmount;
    }

    //unit tested

    function _getUserTotalCollateralValueInUsd(address _user) private view returns (uint256) {
        uint256 totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < listOfCollateralAddresses.length; i++) {
            address collateralAddress = listOfCollateralAddresses[i];
            uint256 amount = userToCollateralAdressToAmount[_user][collateralAddress];
            if (amount > 0) {
                totalCollateralValueInUsd += _convertCollateralValueToUsd(collateralAddress, amount);
            }
        }
        return totalCollateralValueInUsd;
    }

    // uint tested
    function _convertCollateralValueToUsd(address _collateralAddress, uint256 _amountOfCollateralToConvertToUsd)
        private
        view
        NumberMustBeMoreThanZero(_amountOfCollateralToConvertToUsd)
        returns (uint256)
    {
        address priceFeedAddressOfCollateral = collateralAddressToPriceFeedAddress[_collateralAddress];

        (uint256 price, uint8 decimals) = _getPriceAndDecimalsFromFeed(priceFeedAddressOfCollateral);

        return (_amountOfCollateralToConvertToUsd * price) / (10 ** uint256(decimals));
    }
    // uint tested

    function _convertUsdValueToCollateral(address _collateralAddress, uint256 _amountOfUsd)
        private
        view
        NumberMustBeMoreThanZero(_amountOfUsd)
        returns (uint256)
    {
        address priceFeedAddressOfCollateral = collateralAddressToPriceFeedAddress[_collateralAddress];

        (uint256 price, uint8 decimals) = _getPriceAndDecimalsFromFeed(priceFeedAddressOfCollateral);

        // Convert USD to the amount of collateral with proper precision
        return (_amountOfUsd * (10 ** uint256(decimals))) / price;
    }

    /// unit tested 100%
    function _getPriceAndDecimalsFromFeed(address _priceFeedAddress) private view returns (uint256, uint8) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();

        uint8 decimals = priceFeed.decimals();
        return (uint256(price), decimals);
    }
    /////unit tested 100%

    function setInterestRate(uint256 _interestRate) public onlyOwner {
        interestRate = _interestRate;
    }

    // Getter functions
    function setUserCollateralAmount(address _user, address _collateralAddress, uint256 _amount) public {
        userToCollateralAdressToAmount[_user][_collateralAddress] = _amount;
    }

    function getInterestRate() external view returns (uint256) {
        return interestRate;
    }

    function getJatStableCoinAddress() external view returns (address) {
        return address(jatStableCoin);
    }

    function getCollateralPriceFeedAddress(address _collateralAddress) external view returns (address) {
        return collateralAddressToPriceFeedAddress[_collateralAddress];
    }

    function checkEnsureHealthFactorIsNotBroken(address user) external view {
        _ensureHealthFactorIsNotBroken(user);
    }

    function getUserBorrowDetails(address _user, uint256 _borrowId) external view returns (BorrowDetails memory) {
        return userBorrowDetails[_user][_borrowId];
    }

    function setUserBorrowDetails(address user, uint256 id, BorrowDetails memory details) public {
        userBorrowDetails[user][id] = details;
    }

    function getUserCollateralAmount(address _user, address _collateralAddress) external view returns (uint256) {
        return userToCollateralAdressToAmount[_user][_collateralAddress];
    }

    function getListOfCollateralAddresses() external view returns (address[] memory) {
        return listOfCollateralAddresses;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getSecondsPerYear() external pure returns (uint256) {
        return SECONDS_IN_A_YEAR;
    }

    function getUserTotalCollateralValueInUsd(address _user) public view returns (uint256) {
        return _getUserTotalCollateralValueInUsd(_user);
    }

    function getUserTotalJatCoinedBorrowedWithInterest(address _user) public view returns (uint256) {
        return _getUserTotalJatCoinedBorrowedWithInterest(_user);
    }

    function getUserDetails(address _user) public view returns (uint256, uint256) {
        return _getUserDetails(_user);
    }

    function getHealthFactor(address _user) public view returns (uint256) {
        return _getHealthFactor(_user);
    }

    function getPriceAndDecimalsFromFeed(address _priceFeedAddress) public view returns (uint256, uint8) {
        return _getPriceAndDecimalsFromFeed(_priceFeedAddress);
    }

    function setUserToCollateralAmount(address user, address collateralAddress, uint256 amount) public {
        userToCollateralAdressToAmount[user][collateralAddress] = amount;
    }

    function getUserBorrowCount(address user) public view returns (uint256) {
        return userBorrowCount[user];
    }

    function getUserToCollateralAmount(address user, address collateralAddress) public view returns (uint256) {
        return userToCollateralAdressToAmount[user][collateralAddress];
    }

    function convertCollateralValueToUsd(address _collateralAddress, uint256 _amountOfCollateralToConvertToUsd)
        public
        returns (uint256)
    {
        return _convertCollateralValueToUsd(_collateralAddress, _amountOfCollateralToConvertToUsd);
    }
    // Function to set collateral amounts for testing

    function setUserCollateral(address user, address collateral, uint256 amount) external {
        userToCollateralAdressToAmount[user][collateral] = amount;
    }

    // Function to get collateral amounts (for testing and validation)
    function getUserCollateral(address user, address collateral) external view returns (uint256) {
        return userToCollateralAdressToAmount[user][collateral];
    }

    function convertUsdValueToCollateral(address _collateralAddress, uint256 _amountOfUsd)
        public
        view
        returns (uint256)
    {
        return _convertUsdValueToCollateral(_collateralAddress, _amountOfUsd);
    }

    function getUserTotalJatCoinBorrowedWithInterest(address _user) public view returns (uint256) {
        return _getUserTotalJatCoinedBorrowedWithInterest(_user);
    }

    function setUserDetails(address _user) external {
        uint256 borrowCount = userBorrowCount[_user];
        for (uint256 i = 0; i < 5; i++) {
            // Ensure we do not exceed the length of listOfCollateralAddresses
            address collateralAddress = listOfCollateralAddresses[i % listOfCollateralAddresses.length];

            // Set userToCollateralAdressToAmount
            uint256 collateralAmount = (i + 1) * 1e18; // Example amount, you can adjust as needed
            userToCollateralAdressToAmount[_user][collateralAddress] = collateralAmount;

            // Set userBorrowDetails
            BorrowDetails memory borrowDetails = BorrowDetails({
                collateralAddress: collateralAddress,
                amountOfJatCoinBorrowed: (i + 1) * 1e18, // Example amount, you can adjust as needed
                borrowTime: block.timestamp - (i * 1 days) // Example borrow time, each borrow one day apart
            });

            // Increment the borrowCount and set borrow details
            userBorrowCount[_user] = borrowCount + i + 1;
            userBorrowDetails[_user][borrowCount + i + 1] = borrowDetails;

            emit JatCoinMinted(
                _user,
                borrowCount + i + 1,
                borrowDetails.amountOfJatCoinBorrowed,
                collateralAddress,
                borrowDetails.borrowTime
            );
        }
    }
}
