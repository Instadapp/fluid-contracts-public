// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Helpers } from "./helpers.sol";
import { ErrorTypes } from "../../errorTypes.sol";

/// @dev Fluid vault protocol helper methods. Mostly used for `operate()` and `liquidate()` methods of CoreModule.
abstract contract HelpersLiquidate is Helpers {
    /// note admin module is also calling this function self call
    /// @dev updating exchange price on storage. Only need to update on storage when changing supply or borrow magnifier
    function updateExchangePricesOnStorage()
        public
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        (liqSupplyExPrice_, liqBorrowExPrice_, vaultSupplyExPrice_, vaultBorrowExPrice_) = updateExchangePrices(
            vaultVariables2
        );

        if (
            liqSupplyExPrice_ > X64 || liqBorrowExPrice_ > X64 || vaultSupplyExPrice_ > X64 || vaultBorrowExPrice_ > X64
        ) {
            revert FluidVaultError(ErrorTypes.Vault__ExchangePriceOverFlow);
        }

        // Updating in storage
        rates =
            liqSupplyExPrice_ |
            (liqBorrowExPrice_ << 64) |
            (vaultSupplyExPrice_ << 128) |
            (vaultBorrowExPrice_ << 192);

        vaultVariables2 =
            (vaultVariables2 & 0xfffffffffffffffffffffffff800000003ffffffffffffffffffffffffffffff) |
            (block.timestamp << 122);

        emit LogUpdateExchangePrice(vaultSupplyExPrice_, vaultBorrowExPrice_);
    }

    constructor(ConstantViews memory constants_) Helpers(constants_) {}
}
