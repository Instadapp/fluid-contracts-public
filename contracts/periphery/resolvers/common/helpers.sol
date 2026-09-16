//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

import { IFluidOracle } from "../../../oracleV2/interfaces/iFluidOracle.sol";

interface IZtakingPool {
    function balance(address token_, address staker_) external view returns (uint256);
}

abstract contract ResolverHelpers {
    // -------------------------------------- ONLY MAINNET RELEVANT ----------------------------------------
    address private constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address private constant WEETHS = 0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88;
    IZtakingPool private constant ZIRCUIT = IZtakingPool(0xF047ab4c75cebf0eB9ed34Ae2c186f3611aEAfa6);

    // -----------------------------------------------------------------------------------------------------

    /// @notice Returns the Liquidity Layers balance of the given token currently re-hypothecated or otherwise sitting externally.
    /// @param token_ The address of the token to check.
    /// @param liquidity_ The address of the Liquidity layer.
    /// @return balanceOf_ The total balance of the contract re-hypothecated assets.
    function _getLiquidityExternalBalances(
        address token_,
        address liquidity_
    ) internal view returns (uint256 balanceOf_) {
        if (block.chainid != 1) {
            return 0; // no rehypo except on mainnet
        }

        if (token_ == WEETH) {
            balanceOf_ += ZIRCUIT.balance(WEETH, liquidity_);
        } else if (token_ == WEETHS) {
            balanceOf_ += ZIRCUIT.balance(WEETHS, liquidity_);
        }
    }

    /// @dev Fetches oracle prices for resolver/UI reads. Falls back to `*Raw` getters when guarded getters revert (e.g. L2 sequencer grace today).
    function _fetchOraclePrices(
        address oracle_
    ) internal view returns (uint256 oraclePriceOperate_, uint256 oraclePriceLiquidate_) {
        if (oracle_ == address(0)) {
            return (0, 0);
        }

        try IFluidOracle(oracle_).getExchangeRateOperate() returns (uint256 exchangeRate_) {
            oraclePriceOperate_ = exchangeRate_;
            try IFluidOracle(oracle_).getExchangeRateLiquidate() returns (uint256 liquidateRate_) {
                oraclePriceLiquidate_ = liquidateRate_;
            } catch {
                oraclePriceLiquidate_ = exchangeRate_;
            }
            return (oraclePriceOperate_, oraclePriceLiquidate_);
        } catch {}

        try IFluidOracle(oracle_).getExchangeRateOperateRaw() returns (uint256 exchangeRate_) {
            oraclePriceOperate_ = exchangeRate_;
            try IFluidOracle(oracle_).getExchangeRateLiquidateRaw() returns (uint256 liquidateRate_) {
                oraclePriceLiquidate_ = liquidateRate_;
            } catch {
                oraclePriceLiquidate_ = exchangeRate_;
            }
            return (oraclePriceOperate_, oraclePriceLiquidate_);
        } catch {}

        try IFluidOracle(oracle_).getExchangeRate() returns (uint256 exchangeRate_) {
            return (exchangeRate_, exchangeRate_);
        } catch {}

        return (0, 0);
    }
}
