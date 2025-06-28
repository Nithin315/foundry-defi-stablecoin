//SPDX-License-Identifier: MIT

pragma solidity *0.8.24;

import {Test} from "forge-std/Test.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLibrary.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract OracleTest is Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITAL_PRICE = 2000 ether;

    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITAL_PRICE);
    }

    function testTimeOut() public view {
        uint256 expectedTimeOut = 3 hours;
        assertEq(expectedTimeOut, OracleLib.getTimeOut(AggregatorV3Interface(address(aggregator))));
    }

    function testRevertOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    function testRevertOnBadAnswersInRound() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }
}
