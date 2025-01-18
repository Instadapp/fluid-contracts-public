// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

interface ICenterPrice {

    // should return price token1 / token0 in 27 decimals. TODO: confirm that it's 27 decimals and not 18 decimals
    function centerPrice() external returns (uint);

}

contract MockDexCenterPrice is ICenterPrice {
    uint256 _price;

    function setPrice(uint256 price_) public {
        _price = price_;
    }

    function centerPrice() public returns(uint256) {
        return _price;
    }
}
