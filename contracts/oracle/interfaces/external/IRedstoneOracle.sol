// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IRedstoneOracle {
    /// @notice Get the `exchangeRate_` between the underlying asset and the peg asset
    // @dev custom Redstone adapter for Instadapp implementation
    function getExchangeRate() external view returns (uint256 exchangeRate_);

    /**
     * @notice Returns the number of decimals for the price feed
     * @dev By default, RedStone uses 8 decimals for data feeds
     * @return decimals The number of decimals in the price feed values
     */
    // see https://github.com/redstone-finance/redstone-oracles-monorepo/blob/main/packages/on-chain-relayer/contracts/price-feeds/PriceFeedBase.sol#L51C12-L51C20
    function decimals() external view returns (uint8);
}
