// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {JatStableCoin} from "./JatStableCoin.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {UD60x18, ud} from "../lib/prb-math/src/UD60x18.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract JatEngine is ReentrancyGuard, Ownable {
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
    error TokenNotSupported(string tokenName);
    error JatEngine__AllowanceNotEqualToAmountToDeposit();
    error UserAddressInvalid(address user);
    error BalanceRetrievalFailed(address user, address tokenAddress);

    JatStableCoin jatStableCoin;
    mapping(address => address) private collateralAddressToPriceFeedAddress;

    struct BorrowDetailsWithInterest {
        BorrowDetails borrowDetails;
        uint256 totalDebtWithInterest;
        uint256 accumulatedInterest;
    }

    struct BorrowDetails {
        uint256 id;
        address collateralAddress;
        uint256 amountOfJatCoinBorrowed;
        uint256 borrowTime;
    }

    mapping(address => mapping(uint256 => BorrowDetails)) private userBorrowDetails;
    mapping(address => uint256) private userBorrowCount;
    mapping(address => mapping(address => uint256)) private userToCollateralAdressToAmount;
    address[] private listOfCollateralAddresses;
    uint256 private constant LIQUIDATION_THRESHOLD = 80;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    // uint256 private constant SECONDS_IN_A_YEAR = 365;
    // uint256 private constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;

    uint256 constant COMPOUNDING_PERIODS_PER_YEAR = 1;
    uint96 public constant UINT96_MAX = type(uint96).max;
    bool public isTestMode = true;
    uint256 private interestRate;

    event JatCoinMinted(
        address indexed borrower, uint256 indexed borrowId, uint256 amount, address collateralAddress, uint256 timestamp
    );

    event CollateralDeposited(address indexed user, address collateralAddress, uint256 amount, uint256 timestamp);

    event JatCoinRepaid(
        address indexed user, uint256 indexed borrowId, uint256 amount, address collateralAddress, uint256 timestamp
    );

    event Liquidation(
        address indexed borrower,
        uint256 indexed borrowId,
        uint256 repayAmount,
        uint256 collateralSeized,
        address indexed liquidator,
        uint256 timestamp
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

    function setTestMode(bool _isTestMode) external onlyOwner {
        isTestMode = _isTestMode;
    }

    function depositAndBorrow(address _collateralAddress, uint256 _amountToDeposit, uint256 _amountOfJatCoinToBorrow)
        public
        IsAllowedCollateralAddress(_collateralAddress)
        NumberMustBeMoreThanZero(_amountOfJatCoinToBorrow)
        NumberMustBeMoreThanZero(_amountToDeposit)
    {
        uint256 amountOfJatCoinToBorrowInUsd =
            _convertCollateralValueToUsd(_collateralAddress, _amountOfJatCoinToBorrow);
        depositCollateral(_collateralAddress, _amountToDeposit, msg.sender);
        borrowJatCoin(amountOfJatCoinToBorrowInUsd, _collateralAddress);
    }

    function depositCollateral(address _collateralAddress, uint256 _amountToDeposit, address _addressOfWhoIsDepositing)
        public
        nonReentrant
        NumberMustBeMoreThanZero(_amountToDeposit)
        IsAllowedCollateralAddress(_collateralAddress)
    {
        userToCollateralAdressToAmount[_addressOfWhoIsDepositing][_collateralAddress] += _amountToDeposit;

        uint256 allowance = IERC20(_collateralAddress).allowance(_addressOfWhoIsDepositing, address(this));
        if (allowance < _amountToDeposit) {
            revert JatEngine__AllowanceNotEqualToAmountToDeposit();
        }

        emit CollateralDeposited(_addressOfWhoIsDepositing, _collateralAddress, _amountToDeposit, block.timestamp);

        bool success =
            IERC20(_collateralAddress).transferFrom(_addressOfWhoIsDepositing, address(this), _amountToDeposit);

        if (!success) {
            revert JatEngine__TransferNotSuccessful();
        }

        IERC20(_collateralAddress).approve(address(this), 0);
    }

    function borrowJatCoin(uint256 _amountOfJatCoinToBorrow, address _collateralAddress)
        public
        nonReentrant
        NumberMustBeMoreThanZero(_amountOfJatCoinToBorrow)
    {
        _mintJatCoin(_amountOfJatCoinToBorrow, _collateralAddress);
    }

    function _mintJatCoin(uint256 _amountOfJatCoinToMint, address _collateralAddress) private {
        uint256 borrowId = userBorrowCount[msg.sender] + 1;
        userBorrowCount[msg.sender] = borrowId;

        BorrowDetails memory borrowDetails = BorrowDetails({
            id: borrowId,
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

    function repayJatCoin(uint256 borrowId, uint256 amountInUsdAndJat)
        public
        nonReentrant
        NumberMustBeMoreThanZero(amountInUsdAndJat)
    {
        BorrowDetails storage borrowDetails = userBorrowDetails[msg.sender][borrowId];
        address collateralAddress = borrowDetails.collateralAddress;

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
            borrowDetails.amountOfJatCoinBorrowed = 0;
        } else {
            borrowDetails.amountOfJatCoinBorrowed = totalDebtWithInterest - amountInUsdAndJat;
        }
        bool success = IERC20(collateralAddress).transfer(msg.sender, amountInCollateral);
        if (!success) {
            revert JatEngine__TransferNotSuccessful();
        }
        success = jatStableCoin.transferFrom(msg.sender, address(this), amountInUsdAndJat);
        if (!success) {
            revert JatEngine__TransferNotSuccessful();
        }

        jatStableCoin.burn(amountInUsdAndJat);
        jatStableCoin.approve(address(this), 0);

        emit JatCoinRepaid(msg.sender, borrowId, amountInUsdAndJat, collateralAddress, block.timestamp);
    }

    function liquidate(address borrower, uint256 borrowId, uint256 repayAmount) public nonReentrant {
        uint256 healthFactor = _getHealthFactor(borrower);
        if (healthFactor >= MIN_HEALTH_FACTOR) {
            revert HealthFactorNotBelowThreshold(healthFactor);
        }

        BorrowDetails storage borrowDetails = userBorrowDetails[borrower][borrowId];
        address collateralAddress = borrowDetails.collateralAddress;
        uint256 totalDebtWithInterest =
            calculateCompoundInterest(borrowDetails.borrowTime, borrowDetails.amountOfJatCoinBorrowed, interestRate);

        if (repayAmount > totalDebtWithInterest) {
            revert RepayAmountExceedsTotalDebt(repayAmount, totalDebtWithInterest);
        }

        uint256 liquidationBonus = 10;
        uint256 collateralAmountToSeize = _convertUsdValueToCollateral(
            collateralAddress, (repayAmount * (LIQUIDATION_PRECISION + liquidationBonus)) / LIQUIDATION_PRECISION
        );

        uint256 availableCollateral = userToCollateralAdressToAmount[borrower][collateralAddress];
        if (collateralAmountToSeize > availableCollateral) {
            revert CollateralAmountExceedsAvailable(collateralAmountToSeize, availableCollateral);
        }

        borrowDetails.amountOfJatCoinBorrowed -= repayAmount;
        userToCollateralAdressToAmount[borrower][collateralAddress] -= collateralAmountToSeize;

        bool collateralTransferSuccess = IERC20(collateralAddress).transfer(msg.sender, collateralAmountToSeize);
        if (!collateralTransferSuccess) {
            revert CollateralTransferFailed();
        }

        bool jatTransferSuccess = jatStableCoin.transferFrom(msg.sender, address(this), repayAmount);
        if (!jatTransferSuccess) {
            revert JatStableCoinTransferFailed();
        }

        jatStableCoin.burn(repayAmount);

        emit Liquidation(borrower, borrowId, repayAmount, collateralAmountToSeize, msg.sender, block.timestamp);
    }

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

    function _getUserDetails(address user)
        private
        view
        returns (uint256 totalCollateralInUsd, uint256 totalJatCoinTheUserHas)
    {
        uint256 collateralValueInUsd = _getUserTotalCollateralValueInUsd(user);
        uint256 totalJatCoinTheUser = _getUserTotalJatCoinedBorrowedWithInterest(user);
        return (collateralValueInUsd, totalJatCoinTheUser);
    }

    function _getUserTotalJatCoinedBorrowedWithInterest(address _user) private view returns (uint256) {
        uint256 totalBorrowedWithInterest = 0;
        uint256 borrowCount = userBorrowCount[_user];
        for (uint256 i = 1; i <= borrowCount; i++) {
            if (userBorrowDetails[_user][i].amountOfJatCoinBorrowed > 0) {
                totalBorrowedWithInterest += calculateCompoundInterest(
                    userBorrowDetails[_user][i].borrowTime,
                    userBorrowDetails[_user][i].amountOfJatCoinBorrowed,
                    interestRate
                );
            }
        }
        return totalBorrowedWithInterest;
    }

    function getUserAllBorrowDetails(address _user) external view returns (BorrowDetailsWithInterest[] memory) {
        uint256 borrowCount = userBorrowCount[_user];
        BorrowDetailsWithInterest[] memory borrowDetailsArray = new BorrowDetailsWithInterest[](borrowCount);

        for (uint256 i = 1; i <= borrowCount; i++) {
            BorrowDetails memory borrowDetails = userBorrowDetails[_user][i];
            if (borrowDetails.amountOfJatCoinBorrowed > 0) {
                uint256 totalDebtWithInterest = calculateCompoundInterest(
                    borrowDetails.borrowTime, borrowDetails.amountOfJatCoinBorrowed, interestRate
                );
                uint256 accumulatedInterest = totalDebtWithInterest - borrowDetails.amountOfJatCoinBorrowed;

                borrowDetailsArray[i - 1] = BorrowDetailsWithInterest({
                    borrowDetails: borrowDetails,
                    totalDebtWithInterest: totalDebtWithInterest,
                    accumulatedInterest: accumulatedInterest
                });
            }
        }

        return borrowDetailsArray;
    }

    function calculateCompoundInterest(uint256 startTime, uint256 principal, uint256 _interestRate)
        public
        view
        returns (uint256)
    {
        if (startTime > block.timestamp) {
            revert JatEngine__StartTimeCannotBeLessThanCurrentTime();
        }

        uint256 timeInSeconds = block.timestamp - startTime;
        uint256 secondsInPeriod = isTestMode ? 365 : 365 * 24 * 60 * 60; // Use 365 seconds for test mode

        UD60x18 principalUD = UD60x18.wrap(principal);
        UD60x18 rateUD = UD60x18.wrap(_interestRate * 1e16);
        UD60x18 oneUD = UD60x18.wrap(1e18);

        UD60x18 timeInYearsUD = UD60x18.wrap(timeInSeconds).div(UD60x18.wrap(secondsInPeriod));

        UD60x18 ratePerPeriodUD = rateUD.div(UD60x18.wrap(1e18));

        UD60x18 compoundFactorUD = oneUD.add(ratePerPeriodUD);

        UD60x18 compoundFactorPowUD = compoundFactorUD.pow(timeInYearsUD);

        UD60x18 totalAmountUD = principalUD.mul(compoundFactorPowUD);

        uint256 totalAmount = totalAmountUD.unwrap();

        // Log the calculation details
        console.log("Principal:", principal);
        console.log("Interest Rate:", _interestRate);
        console.log("Time in Seconds:", timeInSeconds);
        console.log("Total Amount:", totalAmount);

        return totalAmount;
    }

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

    function _convertUsdValueToCollateral(address _collateralAddress, uint256 _amountOfUsd)
        private
        view
        NumberMustBeMoreThanZero(_amountOfUsd)
        returns (uint256)
    {
        address priceFeedAddressOfCollateral = collateralAddressToPriceFeedAddress[_collateralAddress];

        (uint256 price, uint8 decimals) = _getPriceAndDecimalsFromFeed(priceFeedAddressOfCollateral);

        return (_amountOfUsd * (10 ** uint256(decimals))) / price;
    }

    function _getPriceAndDecimalsFromFeed(address _priceFeedAddress) private view returns (uint256, uint8) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();

        uint8 decimals = priceFeed.decimals();
        return (uint256(price), decimals);
    }

    function setInterestRate(uint256 _interestRate) public onlyOwner {
        interestRate = _interestRate;
    }

    // Getter functions
    function setUserCollateralAmount(address _user, address _collateralAddress, uint256 _amount) public {
        userToCollateralAdressToAmount[_user][_collateralAddress] = _amount;
    }

    function getTotalAmountBorrowed(address user) external view returns (uint256) {
        uint256 totalBorrowed = 0;
        uint256 borrowCount = userBorrowCount[user];
        for (uint256 i = 1; i <= borrowCount + 2; i++) {
            uint256 amountBorrowed = userBorrowDetails[user][i].amountOfJatCoinBorrowed;
            if (amountBorrowed > 0) {
                totalBorrowed += amountBorrowed;
            }
        }
        return totalBorrowed;
    }

    function getUserAccumulatedInterest(address _user) external view returns (uint256) {
        uint256 totalInterest = 0;
        uint256 borrowCount = userBorrowCount[_user];
        for (uint256 i = 1; i <= borrowCount; i++) {
            BorrowDetails memory borrow = userBorrowDetails[_user][i];
            if (borrow.amountOfJatCoinBorrowed > 0) {
                uint256 totalDebtWithInterest =
                    calculateCompoundInterest(borrow.borrowTime, borrow.amountOfJatCoinBorrowed, interestRate);
                uint256 principal = borrow.amountOfJatCoinBorrowed;
                totalInterest += (totalDebtWithInterest - principal);
            }
        }
        return totalInterest;
    }

    function getUserBorrowDetails(address _user, uint256 _borrowId)
        external
        view
        returns (BorrowDetailsWithInterest memory)
    {
        BorrowDetails memory borrowDetails = userBorrowDetails[_user][_borrowId];
        if (borrowDetails.amountOfJatCoinBorrowed == 0) {
            revert JatEngine__NoBorrowDetailsFound();
        }

        uint256 totalDebtWithInterest =
            calculateCompoundInterest(borrowDetails.borrowTime, borrowDetails.amountOfJatCoinBorrowed, interestRate);

        uint256 accumulatedInterest = totalDebtWithInterest - borrowDetails.amountOfJatCoinBorrowed;

        BorrowDetailsWithInterest memory detailsWithInterest = BorrowDetailsWithInterest({
            borrowDetails: borrowDetails,
            totalDebtWithInterest: totalDebtWithInterest,
            accumulatedInterest: accumulatedInterest
        });

        return detailsWithInterest;
    }

    function getCollateralAddresses() external view returns (address[] memory) {
        return listOfCollateralAddresses;
    }

    function getERC20Balance(address user, string memory tokenName) external view returns (uint256) {
        address tokenAddress;
        if (keccak256(abi.encodePacked(tokenName)) == keccak256(abi.encodePacked("WETH"))) {
            tokenAddress = listOfCollateralAddresses[0];
        } else if (keccak256(abi.encodePacked(tokenName)) == keccak256(abi.encodePacked("WBTC"))) {
            tokenAddress = listOfCollateralAddresses[1];
        } else {
            revert TokenNotSupported(tokenName);
        }

        if (user == address(0)) {
            revert UserAddressInvalid(user);
        }

        return ERC20Mock(tokenAddress).balanceOf(user);
    }

    function getCollateralAddressByName(string memory name) public view returns (address) {
        if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("WETH"))) {
            return listOfCollateralAddresses[0];
        } else if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("WBTC"))) {
            return listOfCollateralAddresses[1];
        } else {
            revert("Collateral type not supported");
        }
    }

    function getTotalCollateralValueOfUser(address user, bool inDollar) public view returns (uint256) {
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < listOfCollateralAddresses.length; i++) {
            uint256 amount = userToCollateralAdressToAmount[user][listOfCollateralAddresses[i]];
            if (amount > 0) {
                if (inDollar) {
                    totalCollateralValue += _convertCollateralValueToUsd(listOfCollateralAddresses[i], amount);
                } else {
                    totalCollateralValue += amount;
                }
            }
        }
        return totalCollateralValue;
    }

    function getCollateralValueOfUserByType(address user, string memory name, bool inDollar)
        public
        view
        returns (uint256)
    {
        address collateralAddress = getCollateralAddressByName(name);
        uint256 amount = userToCollateralAdressToAmount[user][collateralAddress];
        if (amount <= 0) {
            return 0;
        }
        if (inDollar) {
            return _convertCollateralValueToUsd(collateralAddress, amount);
        } else {
            return amount;
        }
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

    function getContractAddress() public view returns (address) {
        return address(this);
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
        view
        returns (uint256)
    {
        return _convertCollateralValueToUsd(_collateralAddress, _amountOfCollateralToConvertToUsd);
    }

    function setUserCollateral(address user, address collateral, uint256 amount) external {
        userToCollateralAdressToAmount[user][collateral] = amount;
    }

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

    function getJatCoinAddress() public view returns (address) {
        return address(jatStableCoin);
    }

    function getUserTotalJatCoinBorrowedWithInterest(address _user) public view returns (uint256) {
        return _getUserTotalJatCoinedBorrowedWithInterest(_user);
    }
}
