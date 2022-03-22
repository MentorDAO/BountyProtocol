//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";

// import {DataTypes} from './libraries/DataTypes.sol';
import "./interfaces/ICase.sol";
import "./libraries/DataTypes.sol";
import "./abstract/Rules.sol";
import "./abstract/CommonYJ.sol";

/**
 * Case Contract
 */
contract Case is ICase, CommonYJ{

    //--- Storage

    // Contract name
    string public name;
    // Contract symbol
    string public symbol;
    //Jurisdiction
    address private _jurisdiction;
    //Rule(s)


    //--- Events


    //--- Functions
    
    // constructor(address jurisdiction) {
    constructor(string memory name_, string memory symbol_, address hub, address jurisdiction) CommonYJ(hub){
        //TODO: Validate HUB's Role
        //TODO: Validate Jurisdiction's Role
        require(jurisdiction != address(0), "INVALID JURISDICTION");

        _jurisdiction = jurisdiction;
        name = name_;
        symbol = symbol_;
    }

}