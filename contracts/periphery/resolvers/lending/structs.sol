// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLendingFactory } from "../../../protocols/lending/interfaces/iLendingFactory.sol";
import { Structs as FluidLiquidityResolverStructs } from "../liquidity/structs.sol";

abstract contract Structs {
    struct FTokenDetails {
        address tokenAddress;
        bool eip2612Deposits;
        bool isNativeUnderlying;
        string name;
        string symbol;
        uint256 decimals;
        address asset;
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 convertToShares;
        uint256 convertToAssets;
        // Streaming bonus APR (`100` = 1%, Liquidity scale). Renamed from legacy `rewardsRate`; on-chain `1e12` → `÷ 1e10`.
        uint256 relativeModelRate;
        // Signed APR offset from FluidLendingStaticRateModel (`100` = 1%). Positive = on top of Liquidity;
        // negative = below. Zero when streaming is active or static is wired but not currently accruing.
        int256 staticModelRate;
        // true when a static rate model is wired on the fToken (even if the program has ended)
        bool isStaticRate;
        // true when a rewards/static program is currently accruing (`fToken.getData().rewardsActive_`).
        // After stop/natural end the model may stay wired (`isStaticRate` true) while this is false.
        bool rewardsActive;
        // Liquidity-layer supply APR (`100` = 1%, same as `LiquidityResolver.supplyRate`).
        uint256 liquidityRate;
        // Combined holder APR (`100` = 1%). Streaming: `liquidityRate + relativeModelRate`.
        // Static active: `max(0, liquidityRate + staticModelRate)`. Ended: `liquidityRate`.
        uint256 totalRate;
        // difference between fToken assets & actual deposit at Liquidity. (supplyAtLiquidity - totalAssets).
        // if negative, rewards must be funded to guarantee withdrawal is possible for all users. This happens
        // by executing rebalance().
        int256 rebalanceDifference;
        // liquidity related data such as supply amount, limits, expansion etc.
        FluidLiquidityResolverStructs.UserSupplyData liquidityUserSupplyData;
        // `ACCESS_TYPE()` on permissioned-stack fTokens (`0` = public/ungated, `1` = permissioned).
        // Defaults to `0` when the selector is missing (production / unknown fTokens).
        uint8 accessType;
    }

    struct UserPosition {
        uint256 fTokenShares;
        uint256 underlyingAssets;
        uint256 underlyingBalance;
        uint256 allowance;
    }

    struct FTokenDetailsUserPosition {
        FTokenDetails fTokenDetails;
        UserPosition userPosition;
    }
}
