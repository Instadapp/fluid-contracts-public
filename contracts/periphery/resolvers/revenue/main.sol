// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { CalcRevenueSimulatedTime } from "./calcRevenueSimulatedTime.sol";

/// @notice Fluid Revenue resolver
contract FluidRevenueResolver {
    /// @notice address of the liquidity contract
    IFluidLiquidity public immutable LIQUIDITY;

    /// @dev address that is mapped to the chain native token
    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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
            CalcRevenueSimulatedTime.calcRevenue(
                totalAmounts_,
                exchangePricesAndConfig_,
                liquidityTokenBalance_,
                simulatedTimestamp_
            );
    }
}
