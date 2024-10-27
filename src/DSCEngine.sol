// SPDX-License-Identifier: SEE LICENSE IN LICENSE
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

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author  Farooq Ahmed
 * The syste3m is design to be as minimum as possible  and have the token maintain $1==1DSC peg
 * The stabloe coin has  the properties:
 * -Exogenous Collateral
 * -Doller Pegged
 * -Algorithmic Stable
 * It is similar to DAI had no goveranace no fee and was only backed by WETH & WBTC
 * Our DSC system should always be "overcollateralized" AT NO POINT ,should the value of the collateral be less than the value of the DSC
 * @notice This contract is the core of the DSC system.It handle all the logic for minting and redeeming DSC as well as depositing and withdrawing collateral
 * @notice This contract is very loosly based on MAKERDAO DSS (DAI) system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    //   Errors   //
    ///////////////////
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedsAddressesLengthMustBeSame();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__TransferFromFailed();
    error DSCEngine__MintFailed();
    /////////////////////////
    //// State Variable   //
    //////////////////////////

    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant PRECISIONS = 10 ether;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds; //token to price Feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; //user to token to amount
    mapping(address user => uint256 amountDscMinted) private s_DscMinted; //user to amount
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable _i_dsc;

    /////////////////////////
    // //// Event   /////
    //////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralReedemed(
        address indexed token, uint256 amount, address indexed redeemFrom, address indexed redeemTo
    );
    ///////////////////
    ////   Modifier   //
    ///////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }
    ///////////////////
    //   Functions   //
    ///////////////////

    ///////////////////
    //   Constuctor   //
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedsAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsAddressesLengthMustBeSame();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        _i_dsc = DecentralizedStableCoin(dscAddress);
    }
    ///////////////////////////
    //   External Functions  //
    ///////////////////////////
    /*
    *@pram tokenCollateralAddress The address of the token to deposit as collateral
    *@pram amountCollateral The amount of the collateral  to deposit
    *@pram amountDscToMint The amount of Decentralized Stable Coin to mint
    * @notice This function will deposit collateral and mint dse in one transaction
    */

    function depositCollaterAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
    /**
     * @notice follow CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the collateral  to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    /*
    *@pram tokenCollateralAddress The collareral address to redeem
    *@pram amountCollateral The amount of the collateral to redeem
    *@pram amountDscToBurn The amount of   DSC to burn
    * @notice This function will redeem underline collateral and burn DSC in one transaction    
     */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeem collateral() already checks if health factor is broken
    }
    //in order to redeem collateral
    // 1. they must have healthfactor above 1 after they pull out

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /**
     * @notice follow CEI
     * @param amountDscToMint The amount of Decentralized Stable Coin to mint
     * @notice they must have more  collateral value  than the minimum thershold
     */

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        // if they minted too muh Dsc they should revert
        _revertIfHealthFactorIsBroken(msg.sender);
        bool mint = _i_dsc.mint(msg.sender, amountDscToMint);
        if (mint != true) {
            revert DSCEngine__MintFailed();
        }
    }
    /**
     * @notice follow CEI
     * @param amount The amount of Decentralized Stable Coin to burn
     */
    //do we need to check if it breaks

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        uint256 divisor = getDivisor();
        // Replace with actual logic to get the divisor
        require(divisor != 0, "Divisor cannot be zero");
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getDivisor() public view returns (uint256) {
        return 1;
    }

    //if 75 backinmg to 50 DSC
    //then liquidator will take $75 backing and pay off/ burn  50 DSC
    //If someone is almost undercollateralized, we will pay you to liquidate them
    /*
    *@pram collateral  The erc20 collateral address  to liquidate from the user
    *@pram user The user who has broken the health factor the health factor is below MIN_HEALTH_FACTOR
    *@pram debtToCover The amount of DSC to cover you want to burn to imporve the health factor
    * @notice you can partially liquidate a user 
    *@notice you will get thew liquidation bonus for taking user funds
    *@notice this function will assumes that the protocal is 200% overcollateralized in orde for this to work
    *@notice If it is less collateralized, the liquidator will lose money this is bug 
    * follows CEI
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        //check the health factor of user
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //we want to burn DSC bebt
        //and we want to take collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        //we need to burn Dsc
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
    ///////////////////////////////////////////
    //   Private &Internal view Functions  //
    //////////////////////////////////////////

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
    /**
     * @dev low level internal function , do not call  unless  the function calliing it  is checking for the healthbeing boken
     *
     *
     * @param amountDscToBurn The amount of Decentralized Stable Coin to burn
     */

    function _burnDsc(uint256 amountDscToBurn, address onTheBehalfOf, address dscFrom) private {
        s_DscMinted[onTheBehalfOf] -= amountDscToBurn;
        bool success = _i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralReedemed(tokenCollateralAddress, amountCollateral, from, to);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    /**
     * returns how close to the liquidation user is
     * if user goes below 1, they are liquidated
     */

    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral Value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
        // return CollateralValueInUsd/totalDscMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check if the health factor(do they have enough Eth)\
        // 2. Revert if they don't
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////////////
    //   Public &External view Functions  //
    //////////////////////////////////////////
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /*
    *@param tokenCollateralAddress The ERC20 token Address of the collateral you are depositing amountCollateral     The amount to be deposited as collateral
    *@param amountDscToMint The amount of Decentralized Stable Coin to mint
    */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
    // function getTokenAmountFromUsd(address token ,uint256 usdAmountInWei) public view returns(uint256){
    //     AggregatorV3Interface priceFeed=AggregatorV3Interface(s_priceFeeds[token]);
    //     (,int256 price,,,)=priceFeed.latestRoundData();
    //     // return ((usdAmountInWei*PRECISION)/ (uint256(price)*ADDITIONAL_FEED_PRECISION));
    //      return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    // }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getDsc() external view returns (address) {
        return address(_i_dsc);
    }
}
