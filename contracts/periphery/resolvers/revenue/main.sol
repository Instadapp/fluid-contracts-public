// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { CalcsSimulatedTime } from "./calcsSimulatedTime.sol";
import { CalcsVaultSimulatedTime } from "./calcsVaultSimulatedTime.sol";

/// @notice Fluid Revenue resolver
contract FluidRevenueResolver {
    /// @notice address of the liquidity contract
    IFluidLiquidity public immutable LIQUIDITY;

    /// @dev address that is mapped to the chain native token
    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 internal constant X64 = 0xffffffffffffffff;
    // constants used for BigMath conversion from and to storage
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    struct TokenRevenue {
        address token;
        uint256 revenueAmount;
    }

    constructor(IFluidLiquidity liquidity_) {
        LIQUIDITY = IFluidLiquidity(liquidity_);
    }

    /// @notice address of contract that gets sent the revenue. Configurable by governance
    function getRevenueCollector() public view returns (address) {
        return address(uint160(LIQUIDITY.readFromStorage(bytes32(0))));
    }

    /// @notice gets the currently uncollected `revenueAmount_` for a `token_`.
    function getRevenue(address token_) public view returns (uint256 revenueAmount_) {
        uint256 exchangePricesAndConfig_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                token_
            )
        );
        if (exchangePricesAndConfig_ == 0) {
            // token is not configured at Liquidity -> revenue is 0
            return 0;
        }

        uint256 liquidityTokenBalance_ = token_ == _NATIVE_TOKEN_ADDRESS
            ? address(LIQUIDITY).balance
            : IERC20(token_).balanceOf(address(LIQUIDITY));

        uint256 totalAmounts_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
                token_
            )
        );

        return LiquidityCalcs.calcRevenue(totalAmounts_, exchangePricesAndConfig_, liquidityTokenBalance_);
    }

    /// @notice gets the currently uncollected revenues for all listed tokens at Liquidity
    function getRevenues() public view returns (TokenRevenue[] memory tokenRevenues_) {
        uint256 length_ = LIQUIDITY.readFromStorage(bytes32(LiquiditySlotsLink.LIQUIDITY_LISTED_TOKENS_ARRAY_SLOT));

        tokenRevenues_ = new TokenRevenue[](length_);

        uint256 startingSlotForArrayElements_ = uint256(
            keccak256(abi.encode(LiquiditySlotsLink.LIQUIDITY_LISTED_TOKENS_ARRAY_SLOT))
        );

        for (uint256 i; i < length_; i++) {
            tokenRevenues_[i].token = address(
                uint160(LIQUIDITY.readFromStorage(bytes32(startingSlotForArrayElements_ + i)))
            );
            tokenRevenues_[i].revenueAmount = getRevenue(tokenRevenues_[i].token);
        }
    }

    /// @notice gets the `revenueAmount_` for a token given its' totalAmounts and exchangePricesAndConfig from stacked
    /// uint256 storage slots and the balance of the Fluid liquidity contract for the token.
    /// @dev exposed for advanced revenue calculations
    /// @param totalAmounts_ total amounts packed uint256 read from storage
    /// @param exchangePricesAndConfig_ exchange prices and config packed uint256 read from storage
    /// @param liquidityTokenBalance_   current balance of Liquidity contract (IERC20(token_).balanceOf(address(this)))
    /// @return revenueAmount_ collectable revenue amount
    function calcRevenue(
        uint256 totalAmounts_,
        uint256 exchangePricesAndConfig_,
        uint256 liquidityTokenBalance_
    ) public view returns (uint256 revenueAmount_) {
        if (exchangePricesAndConfig_ == 0) {
            // token is not configured at Liquidity -> revenue is 0
            return 0;
        }
        return LiquidityCalcs.calcRevenue(totalAmounts_, exchangePricesAndConfig_, liquidityTokenBalance_);
    }

    /// @notice same as `calcRevenue`, but for a simulated `block.timestamp` set via `simulatedTimestamp_`.
    function calcRevenueSimulatedTime(
        uint256 totalAmounts_,
        uint256 exchangePricesAndConfig_,
        uint256 liquidityTokenBalance_,
        uint256 simulatedTimestamp_
    ) public pure returns (uint256 revenueAmount_) {
        if (exchangePricesAndConfig_ == 0) {
            // token is not configured at Liquidity -> revenue is 0
            return 0;
        }
        return
            CalcsSimulatedTime.calcRevenue(
                totalAmounts_,
                exchangePricesAndConfig_,
                liquidityTokenBalance_,
                simulatedTimestamp_
            );
    }

    /// @notice calculates interest (exchange prices) at Liquidity for a token given its' exchangePricesAndConfig from storage
    ///         for a simulated `block.timestamp` set via `simulatedTimestamp_`.
    /// @param exchangePricesAndConfig_ exchange prices and config packed uint256 read from storage
    /// @param simulatedTimestamp_ simulated block.timestamp
    /// @return supplyExchangePrice_ updated supplyExchangePrice
    /// @return borrowExchangePrice_ updated borrowExchangePrice
    function calcLiquidityExchangePricesSimulatedTime(
        uint256 exchangePricesAndConfig_,
        uint256 simulatedTimestamp_
    ) public pure returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        if (exchangePricesAndConfig_ == 0) {
            // token is not configured at Liquidity -> exchange prices are 0
            return (0, 0);
        }
        return CalcsSimulatedTime.calcExchangePrices(exchangePricesAndConfig_, simulatedTimestamp_);
    }

    /// @notice Calculates new vault exchange prices based on storage data for a simulated `block.timestamp` set via `simulatedTimestamp_`.
    /// @param vaultVariables2_ vaultVariables2 read from storage for the vault (VaultResolver.getRateRaw)
    /// @param vaultRates_ rates read from storage for the vault (VaultResolver.getVaultVariables2Raw)
    /// @param liquiditySupplyExchangePricesAndConfig_ exchange prices and config packed uint256 read from storage for supply token
    /// @param liquidityBorrowExchangePricesAndConfig_ exchange prices and config packed uint256 read from storage for borrow token
    /// @param simulatedTimestamp_ simulated block.timestamp
    /// @return liqSupplyExPrice_ latest liquidity's supply token supply exchange price
    /// @return liqBorrowExPrice_ latest liquidity's borrow token borrow exchange price
    /// @return vaultSupplyExPrice_ latest vault's supply token exchange price
    /// @return vaultBorrowExPrice_ latest vault's borrow token exchange price
    function calcVaultExchangePricesSimulatedTime(
        uint256 vaultVariables2_,
        uint256 vaultRates_,
        uint256 liquiditySupplyExchangePricesAndConfig_,
        uint256 liquidityBorrowExchangePricesAndConfig_,
        uint256 simulatedTimestamp_
    )
        public
        pure
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        if (liquiditySupplyExchangePricesAndConfig_ == 0 || liquidityBorrowExchangePricesAndConfig_ == 0) {
            // token is not configured at Liquidity -> exchange prices are 0
            return (0, 0, 0, 0);
        }
        return
            CalcsVaultSimulatedTime.updateExchangePrices(
                vaultVariables2_,
                vaultRates_,
                liquiditySupplyExchangePricesAndConfig_,
                liquidityBorrowExchangePricesAndConfig_,
                simulatedTimestamp_
            );
    }

    /// @notice returns the `totalSupply_` and `totalBorrow_` at Liquidity at a certain point in time given the stacked uint256
    ///         storage data for total amounts and exchange prices and config.
    function calcLiquidityTotalAmountsSimulatedTime(
        uint256 totalAmounts_,
        uint256 exchangePricesAndConfig_,
        uint256 simulatedTimestamp_
    )
        public
        pure
        returns (uint256 totalSupply_, uint256 totalBorrow_, uint256 supplyExchangePrice_, uint256 borrowExchangePrice_)
    {
        if (exchangePricesAndConfig_ == 0) {
            // token is not configured at Liquidity -> amounts are 0
            return (0, 0, 0, 0);
        }

        (supplyExchangePrice_, borrowExchangePrice_) = CalcsSimulatedTime.calcExchangePrices(
            exchangePricesAndConfig_,
            simulatedTimestamp_
        );

        totalSupply_ = CalcsSimulatedTime.getTotalSupply(totalAmounts_, supplyExchangePrice_);
        totalBorrow_ = CalcsSimulatedTime.getTotalBorrow(totalAmounts_, borrowExchangePrice_);
    }

    /// @notice returns the `supply_` and `borrow_` for a user (protocol) at Liquidity at a certain point in time
    ///          given the stacked uint256 storage data for total amounts and exchange prices and config.
    function calcLiquidityUserAmountsSimulatedTime(
        uint256 userSupplyData_,
        uint256 userBorrowData_,
        uint256 liquiditySupplyExchangePricesAndConfig_,
        uint256 liquidityBorrowExchangePricesAndConfig_,
        uint256 simulatedTimestamp_
    )
        public
        pure
        returns (uint256 supply_, uint256 borrow_, uint256 supplyExchangePrice_, uint256 borrowExchangePrice_)
    {
        if (liquiditySupplyExchangePricesAndConfig_ == 0 || liquidityBorrowExchangePricesAndConfig_ == 0) {
            // token is not configured at Liquidity -> amounts are 0
            return (0, 0, 0, 0);
        }

        (supplyExchangePrice_, ) = CalcsSimulatedTime.calcExchangePrices(
            liquiditySupplyExchangePricesAndConfig_,
            simulatedTimestamp_
        );

        (, borrowExchangePrice_) = CalcsSimulatedTime.calcExchangePrices(
            liquidityBorrowExchangePricesAndConfig_,
            simulatedTimestamp_
        );

        if (userSupplyData_ > 0) {
            // if userSupplyData_ == 0 -> user not configured yet for token at Liquidity

            bool modeWithInterest_ = userSupplyData_ & 1 == 1;
            supply_ = BigMathMinified.fromBigNumber(
                (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

            if (modeWithInterest_) {
                // convert raw amounts to normal for withInterest mode
                supply_ = (supply_ * supplyExchangePrice_) / 1e12;
            }
        }

        if (userBorrowData_ > 0) {
            // if userBorrowData_ == 0 -> user not configured yet for token at Liquidity

            bool modeWithInterest_ = userBorrowData_ & 1 == 1;
            borrow_ = BigMathMinified.fromBigNumber(
                (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

            if (modeWithInterest_) {
                // convert raw amounts to normal for withInterest mode
                borrow_ = (borrow_ * borrowExchangePrice_) / 1e12;
            }
        }
    }
}
