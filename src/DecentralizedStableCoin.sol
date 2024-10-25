// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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
pragma solidity ^0.8.19;
import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
* @title Decentralized Stable Coin
* @Author: Farooq Ahmed
* collateral:Exogenous (Eth, Btc)
* Minting : Algorithmic
* Relative Stability: Pegged to Usd
* This contact is to be Governed By DSC Engine .This contract is just the ERC20 implementation of our stableCoin System. 
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {

    error DecentralizedStableCoin__MustBeGreaterThenZero();
    error DecentralizedStableCoin__BurnAmountExceedBalnce();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentrilizedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeGreaterThenZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedBalnce();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeGreaterThenZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
