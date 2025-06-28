//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;

    address USER = makeAddr("user");

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testRevertIfMintAmountIsZero() public {
        uint256 amount = 0;

        vm.startPrank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(address(this), amount);
        vm.stopPrank();
    }

    function testCanMintOnlyOwner() public {
        uint256 amount = 10;

        vm.startPrank(USER);
        vm.expectRevert();
        dsc.mint(USER, amount);
        vm.stopPrank();
    }

    function testCanMint() public {
        uint256 amount = 10;

        vm.startPrank(dsc.owner());
        dsc.mint(address(this), amount);
        assertEq(amount, dsc.balanceOf(address(this)));
        vm.stopPrank();
    }

    function testRevertIfMintToZeroAddress() public {
        uint256 amount = 100;

        vm.startPrank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__CanNotMintToZeroAddress.selector);
        dsc.mint(address(0), amount);
        vm.stopPrank();
    }

    function testRevertBurnIfAmountIsLessThanZero() public {
        uint256 amount = 0;

        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(amount);
        vm.stopPrank();
    }

    function testBurnOnlyOwner() public {
        uint256 amount = 10;

        vm.startPrank(USER);
        vm.expectRevert();
        dsc.burn(amount);
        vm.stopPrank();
    }

    function testBurnRevertIfBalanceLessThanAmount() public {
        uint256 amount = 200;

        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(amount);
        vm.stopPrank();
    }

    function testCanBurn() public {
        uint256 amount = 50;
        uint256 expectedUserBalance = 50;

        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        dsc.burn(amount);
        assertEq(expectedUserBalance, dsc.balanceOf(address(this)));
        vm.stopPrank();
    }
}
