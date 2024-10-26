// SPDX-License-Identifier: MIT

// // Invariants:
// // The total supply od DSC should less than the total supply of the collateral
// // Getter view function should never rever<- evergreen invarient
// // protocol must never be insolvent / undercollateralized

// // users cant create stablecoins with a bad health factor
// // a user should only be able to be liquidated if they have a bad health factor

// pragma solidity  ^0.8.19;

// // import "hardhat/console.sol";
// import {Test,console} from "forge-std/Test.sol";
// import{console} from "forge-std/console.sol";
// // D:\dev\defi\foundry-defi-stableCoin-f24-v2\lib\forge-std\src\console.sol
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// contract OpenInvariantsTest is StdInvariant ,Test {
//     DeployDSC deployer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         (,,weth,wbtc,)=config.activeNetworkConfig();

//         targetContract(address(dsce));

//     }
//       function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         //get the value of all the protocal
//         //compare to all the debt dsc
//         uint256 totalSupply=dsc.totalSupply();
//         uint256 totalWethDeposited=IERC20(weth).balanceOf(address(dsce));
//         uint256 totalWbtcDeposited=IERC20(wbtc).balanceOf(address(dsce));

//          uint256 wethValue=dsce.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue=dsce.getUsdValue(wbtc, totalWbtcDeposited);

//           assert(wethValue+wbtcValue>=totalSupply);
//       }
// }
