// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { FluidOracle } from "../fluidOracle.sol";
import { PegOracleImpl } from "../implementations/pegOracleImpl.sol";

/// @title Peg oracle that returns price for pegged assets
/// @notice  This contract is used to get the exchange rate between pegged assets like sUSDE / USDC or USDE / USDC.
///          Price is adjusted for token decimals and optionally a IERC4626 source feed can be set (e.g. for sUSDE or sUSDS).
contract PegOracle is FluidOracle, PegOracleImpl {
    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        uint8 colTokenDecimals_,
        uint8 debtTokenDecimals_,
        IERC4626 erc4626Feed_
    ) PegOracleImpl(colTokenDecimals_, debtTokenDecimals_, erc4626Feed_) FluidOracle(infoName_, targetDecimals_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        return _getPegExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        return _getPegExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        return _getPegExchangeRate();
    }
}
