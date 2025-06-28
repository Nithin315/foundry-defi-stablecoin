//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEnginge is Test {
    event CollateralRedeemed(address indexed from, address indexed to, address token, uint256 amount);

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig public helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;

    //Liquidation
    address public liqudator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      constructor Price                                            /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDosntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMustBeEqual.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      Test Price                                                  /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /* 
    *@notice This is test is for the get usd value function to check whetehr it works perfectly or not 
    *
    * 
    * 
    */
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      Test Deposit Collateral                                      /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /* 
    *@notice This test is used for testing tif the collateral is zero the function should revert we take the
    *USER address and prank him and we send in the ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    *where AMOUNT_COLLATERAL = 10 ether and it is expected to revert as the depositCollateral takes in the 
    *weth as the token collateral address and collateral ammount as 0 so the function reverts and we stop prank
    */
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfUnApprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Ran", "Ran", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testRevertIfDepositCollateralTransactionFails() public {}

    modifier depositCollateralAndMint() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        _;
    }

    function testCanDepositAndMintDsc() public depositCollateralAndMint {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    //////////////////////
    //    MintDSC TEST  //
    //////////////////////

    function testMintDscAmountIsNotZero() public {
        vm.startPrank(USER);
        uint256 amountOfDscToMint = 0;
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDSC(amountOfDscToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintingWithoutCollateral() public {
        vm.startPrank(USER);

        // No collateral deposited!
        uint256 amountOfDscToMint = 100;

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        engine.mintDSC(amountOfDscToMint);

        vm.stopPrank();
    }

    function testRevertsIfMintingAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositCollateral {
        vm.prank(USER);
        engine.mintDSC(AMOUNT_TO_MINT);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    //////////////////////
    //    Burn DSC TEST  //
    //////////////////////

    function testIfBurnDscIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    function testCanNotBurnMoreThenUserHas() public {
        vm.startPrank(USER);
        vm.expectRevert();
        engine.burnDSC(1);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositCollateralAndMint {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDSC(AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                      Test redeem Collateral                                      /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testredeemCollateralAmountIsNotZero() public {
        vm.startPrank(USER);
        uint256 collateralAmmount = 0;
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(USER, collateralAmmount);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositCollateral {
        vm.startPrank(USER);
        uint256 beforeRedeem = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(beforeRedeem, AMOUNT_COLLATERAL);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 afterRedeem = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(afterRedeem, 0);
    }

    function testEmitsCollateralRedeemWithCorrectArgs() public depositCollateral {
        vm.expectEmit(true, true, true, true, address(engine));
        console2.log("FROM", USER);
        console2.log("TO", USER);
        console2.log("TOKEN", weth);
        console2.log("AMOUNT", AMOUNT_COLLATERAL);

        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                       redeem Collateral For DSC                                   /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        uint256 collateralAmount = 0;
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForDSC(weth, collateralAmount, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRevertIfTokenIsNotAllowed() public {
        vm.startPrank(USER);
        ERC20Mock newToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.redeemCollateralForDSC(address(newToken), AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanRedeemCollateralForDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                       Health Factor                                              /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testReportsHealthFactorProperly() public depositCollateralAndMint {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healtFactor = engine.getHealthFactor(USER);

        assertEq(expectedHealthFactor, healtFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositCollateralAndMint {
        int256 ethUsdNewPriceFeed = 18e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdNewPriceFeed);

        uint256 userHealthFactor = engine.getHealthFactor(USER);

        assert(userHealthFactor == 0.9 ether);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////                                        Liqudation Test                                           /////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testRevertIfLiquidatedebtToCoverIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsOk() public depositCollateralAndMint {
        ERC20Mock(weth).mint(liqudator, collateralToCover);

        vm.startPrank(liqudator);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactrIsOk.selector);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);

        ERC20Mock(weth).mint(liqudator, collateralToCover);

        vm.startPrank(liqudator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDSC(weth, collateralToCover, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = engine.getAccountInformation(liqudator);
        assertEq(liquidatorDscMinted, AMOUNT_TO_MINT);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = engine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }
}
