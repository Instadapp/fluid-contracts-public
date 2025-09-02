// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IRLPPrice {
    struct Price {
        uint256 price;
        uint256 timestamp;
    }

    function lastPrice() external view returns (Price memory price);
}
