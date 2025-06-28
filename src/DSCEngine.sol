//SPDX-License-Identifier: MIT

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

pragma solidity ^0.8.24;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLibrary.sol";

/**
 * @title DSCEngine
 * @author Nithin
 *
 * The system is designed to be as minimal as possible, and have a token maintain a 1 token = $1 PEG.
 * This Stable coin has properties:
 * Algorithemically stable
 * Dollar pegged
 * Exogeneous collateral
 *
 * It is similar to DAI which has no governence and has no fee and was only backed by the WETH and WBTC
 *
 * The DSCEngine should always be "Overcollateralized" and should not be <= value of all DSC
 *
 * @notice This contract is core DSC System. It handles all the logic like mining, and redeming DSC, as well as depositing collateral
 * @notice This contract is loosely based on MakerDAO DSS (DAI) system.
 *
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      Erros                                                       /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error DSCEngine__NeedsMoreThanZero(); //error if the collateral amount is less than than or equals to zero
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMustBeEqual(); //Error if the Token Address length and proce Feed lenght is not equl in the mapoing s_price feed means the token is not available or can be used
    error DSCEngine__TokenNotAllowed(); //Error If the token is can not be used or valid checked in the modifier if s_price feed has no such token mapped then the token is not allowed as collarteral
    error DSCEngine__TransactionFailed(); // Erro or revert if the transaction has been failed
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactrIsOk();
    error DSCEngine__HealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      State Variables                                             /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATE_BONUS = 10;

    mapping(address token => address priceFeed) public s_priceFeed; //Maps the address of token to the address of the proce feeds
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; //Maps the user addres to internal mapping od token address and amount
    mapping(address user => uint256 amountOfDscMinted) public s_dscMinted; //Maps the user to amount of DSC minted so we can know how much DSC was minted by a particular user
    address[] private s_collateralTokens; // Array to store the collateralTokens

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      Events                                                      /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event CollateralDeposited(address indexed user, address token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address tokenCollateralAddress,
        uint256 collateralAmount
    );
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      Modifiers                                                   /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier mustBeMoreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isTokenAllowed(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      Functions                                                   /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMustBeEqual();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                    External Functions                                            /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param collateralAmount Amount of collateral getting deposited
     * @param amountDSCToMint The amount of DSC to Mint
     * @notice The Function is used for depositing the collateral and mint the DSC
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 collateralAmount,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDSC(amountDSCToMint);
    }

    /**
     * @notice follow CEI - checks, effects, interactions
     * @param tokenCollateralAddress is the address of the collateral provided like WBTC or WETH
     * @param collateralAmount it is the amount of the collateral depositing
     * @notice This function is used for the depositnig the collateram ammount and type of collateral the user would like to use
     */
    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        mustBeMoreThanZero(collateralAmount)
        isTokenAllowed(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
    }

    function redeemForDSC() external {}

    function burnDSC(uint256 amount) public mustBeMoreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 collateralAmount, uint256 dscAmount)
        external
        mustBeMoreThanZero(collateralAmount)
        isTokenAllowed(tokenCollateralAddress)
    {
        burnDSC(dscAmount);
        redeemCollateral(tokenCollateralAddress, collateralAmount);
    }

    //CEI
    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        mustBeMoreThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice It Follows CEI: Checks, Effects, Interactions
     * @param amountOfDscToMint the amount of DSC to mint
     * @notice The amount of Dsc must be bellow the minimum Threshold
     * @notice This function mints the DSC tokens
     */
    function mintDSC(uint256 amountOfDscToMint) public mustBeMoreThanZero(amountOfDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountOfDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountOfDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice You can partially liquidate a user.
     * @notice You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
     * to work.
     * @notice A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
     * anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        mustBeMoreThanZero(debtToCover)
        nonReentrant
    {
        uint256 statrtingUserHealthFactor = _healthFactor(user);
        if (statrtingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactrIsOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonus = (tokenAmountFromDebtCovered * LIQUIDATE_BONUS) / LIQUIDATION_PRECISION;
        uint256 totaltCollateralRedeem = tokenAmountFromDebtCovered + bonus;

        _redeemCollateral(user, msg.sender, collateral, totaltCollateralRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= statrtingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                 Private & Internal view Functions                                /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 collateralAmount)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= collateralAmount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, collateralAmount);

        bool success = IERC20(tokenCollateralAddress).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
    }

    /**
     * @param user takes in the user parameter
     * @return totalDscMinted it returns the total DSC minted by the user
     * @return collateralValueInUsd it returns the collateral value in usd which is deposited by the user
     * @notice this function is used for Getting the Account Information of the user and returns the total Dsc minted
     * by the user and collateral value by checking the s_dscMinted mapping which takes the addrss of user and
     * maps to the amount of DSC minted
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralInformation(user);
    }

    /**
     *
     * @param user takes in the user
     * @notice it checks for the healthFactor it uses the function _getAccountInformation which returns 2 parameters
     * and stores them in the totalDScMINTED and collateralValueInUsd
     * @notice collateralAdjustedForThreshold stores the value of the collateral in usd and multiplies with 50
     * liquidation threshold and divides with 100 (2000 * 50) = 100000 / 100 = 1000
     * now we take the collateralAdjustedForThreshold and multiply it with Precision 1e18 and divide it with total DSC Minted
     * so 1000 * 1e18 / 900 (total dsc minted for example by the user) = 1.111 *1e18 it is > 1e18 so it passes
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max; // Health factor is "infinite" if no debt
        }

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     *
     * @param user It takes the user parameter
     * @notice The funciton is used for reverting the transaction if the health is less the the minimum health = 1
     * it reverts using DSCEngine__BreaksHealthFactor and shows the user health factor
     * the user health factor stores the _healtFactor returned from the user and it is used for the calculations
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                 public & external view Functions                                 /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     *
     * @param user It takes the user as parameter one
     * @notice getAccountCollateralInformation Function is used for the getting the information of collateral of the
     * user it uses loop to go through the array s_collateralTokens and maps and it is stord in the token
     * and it maps to s_collateralDeposited we are providing the user and token address so we can get the amount
     * and it returns totalCollateralValueInUsd after adding the getUsdValue function
     */
    function getAccountCollateralInformation(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     *
     * @param token token is taken for the what type of collateral is taken
     * @param amount how much amountis deposited
     * @notice it uses the Aggregator Interface to get the prioce feed of the token
     * and the price is rounded and it returns the ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    // function getRevertIfHealthFactorIsBroken(address user) external view returns(){
    //     return _revertIfHealthFactorIsBroken(user);
    // }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
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

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeed[token];
    }
}
