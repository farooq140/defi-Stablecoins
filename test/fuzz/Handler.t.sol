// SPDX-License-Identifier: MIT
// handler is going to newrow down the way we call function 

pragma solidity  ^0.8.19;
import {Test,console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import{ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
// D:\dev\defi\foundry-defi-stableCoin-f24-v2\lib\openzeppelin-contracts\contracts\mocks\ERC20Mock.sol
contract Handler is Test{
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE=type(uint96).max;
    uint256 public timeMintIsCalled;
    address [] public usersWithCollateralDeposited;
    
     constructor( DSCEngine _dscEngine, DecentralizedStableCoin _dsc){
        dsce = _dscEngine;
        dsc = _dsc;
    address [] memory collateralTokens=dsce.getCollateralTokens();
    weth = ERC20Mock(collateralTokens[0]);
    wbtc = ERC20Mock(collateralTokens[1]);  
    }
   // redeem Collareral 
    function depositCollateral(uint256 collateralSeed , uint256 amountCollateral) public {
       ERC20Mock collateral=_getCollateralFromSeed(collateralSeed); 
       amountCollateral=bound(amountCollateral,1,MAX_DEPOSIT_SIZE);
       vm.startPrank(msg.sender);
       collateral.mint(msg.sender, amountCollateral);
       collateral.approve(address(dsce), amountCollateral);

        dsce.depositCollateral(address(collateral), amountCollateral);
          vm.stopPrank();
          //this would double push 
          usersWithCollateralDeposited.push(msg.sender); 
         
    }
    function redeemCollateral(uint256 collateralSeed , uint256 amountCollateral) public{
        ERC20Mock collateral=_getCollateralFromSeed(collateralSeed); 
        uint256 maxCollateralToRedeem=dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        console.log("maxCollateralToRedeem",maxCollateralToRedeem);
        console.log("amountCollateral",amountCollateral);
        amountCollateral=bound(amountCollateral,0,maxCollateralToRedeem);
        if(amountCollateral==0){
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }
    function mintDsc(uint256 amount,uint256 addressSeed) public{
        if(usersWithCollateralDeposited.length==0){
            return;
        }
        address sender=usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        // we should only mint dsc if amount is less then collateral

        (uint256 totalDscMinted, uint256 collateralValueInUsd)=dsce.getAccountInformation
        (sender);
        uint256 maxDscToMint=(collateralValueInUsd/2) - totalDscMinted;
        if(maxDscToMint<0){
            return;
        }
        // amount=bound(amount,1,MAX_DEPOSIT_SIZE);
        amount=bound(amount,0,maxDscToMint);
        if(amount ==0){
            return;
        }

        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
         
        timeMintIsCalled++;
    }
    //helper function 
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        
        if(collateralSeed%2==0){
            return weth;
        }
        return wbtc;
    }

}

