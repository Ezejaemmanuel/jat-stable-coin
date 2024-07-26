// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

// This is considered an Exogenous, , Anchored (pegged), Crypto Collateralized low volitility coin

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

/*
 * @title JatStableCoin
 * @author Emmanuel Ezeja
 * Collateral: Exogenous (Eth and BTC) using wETH and wBTC
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stable coin
 */

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract JatStableCoin is ERC20Burnable, Ownable {
    error JatStableCoin__InSufficientBalance(uint256 balance, address addressOfUser);
    error JatStableCoin__MustBeMoreThanZero();
    error JatStableCoin__NoZeroAddress();

    constructor() ERC20("JatStableCoin", "Jat") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balanceOfTheBurner = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert JatStableCoin__MustBeMoreThanZero();
        }
        if (_amount > balanceOfTheBurner) {
            revert JatStableCoin__InSufficientBalance(balanceOfTheBurner, msg.sender);
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external returns (bool) {
        if (_to == address(0)) {
            revert JatStableCoin__NoZeroAddress();
        }
        if (_amount <= 0) {
            revert JatStableCoin__MustBeMoreThanZero();
        }
        super._mint(_to, _amount);
        return true;
    }
}
