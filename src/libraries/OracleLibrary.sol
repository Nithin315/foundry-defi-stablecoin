//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {AggregatorV3Interface} from
    "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Nithin
 * @notice This librar is used to check chainlink Oracle for stale data
 * if a priceFeed is stale, the function reverts and render the DSCEngine Unusable - this is by design
 * we want the DSCEngine to freeze if prices become stale
 *
 * so if the chainlink explodes and you have a lot of money locked in contract too bad.
 *
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getTimeOut(AggregatorV3Interface) public pure returns (uint256) {
        return TIMEOUT;
    }
}
