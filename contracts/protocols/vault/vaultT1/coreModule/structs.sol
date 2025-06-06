// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Structs {
    // structs are used to mitigate Stack too deep errors

    struct OperateMemoryVars {
        // ## User's position before update ##
        uint oldColRaw;
        uint oldNetDebtRaw; // total debt - dust debt
        int oldTick;
        // ## User's position after update ##
        uint colRaw;
        uint debtRaw;
        uint dustDebtRaw;
        int tick;
        uint tickId;
        // others
        uint256 vaultVariables2;
        uint256 branchId;
        int256 topTick;
        uint liquidityExPrice;
        uint supplyExPrice;
        uint borrowExPrice;
        uint branchData;
        // user's supply slot data in liquidity
        uint userSupplyLiquidityData;
    }

    struct BranchData {
        uint id;
        uint data;
        uint ratio;
        uint debtFactor;
        int minimaTick;
        uint baseBranchData;
    }

    struct TickData {
        int tick;
        uint data;
        uint ratio;
        uint ratioOneLess;
        uint length;
        uint currentRatio; // current tick is ratio with partials.
        uint partials;
    }

    // note: All the below token amounts are in raw form.
    struct CurrentLiquidity {
        uint256 debtRemaining; // Debt remaining to liquidate
        uint256 debt; // Current liquidatable debt before reaching next check point
        uint256 col; // Calculate using debt & ratioCurrent
        uint256 colPerDebt; // How much collateral to liquidate per unit of Debt
        uint256 totalDebtLiq; // Total debt liquidated till now
        uint256 totalColLiq; // Total collateral liquidated till now
        int tick; // Current tick to liquidate
        uint ratio; // Current ratio to liquidate
        uint tickStatus; // if 1 then it's a perfect tick, if 2 that means it's a liquidated tick
        int refTick; // ref tick to liquidate
        uint refRatio; // ratio at ref tick
        uint refTickStatus; // if 1 then it's a perfect tick, if 2 that means it's a liquidated tick, if 3 that means it's a liquidation threshold
    }

    struct TickHasDebt {
        int tick; // current tick
        int nextTick; // next tick with liquidity
        int mapId; // mapping ID of tickHasDebt
        uint bitsToRemove; // liquidity to remove till tick_ so we can search for next tick
        uint tickHasDebt; // getting tickHasDebt_ from tickHasDebt[mapId_]
        uint mostSigBit; // most significant bit in tickHasDebt_ to get the next tick
    }

    struct LiquidateMemoryVars {
        uint256 vaultVariables2;
        int liquidationTick;
        int maxTick;
        uint256 supplyExPrice;
        uint256 borrowExPrice;
    }

    struct AbsorbMemoryVariables {
        uint256 debtAbsorbed;
        uint256 colAbsorbed;
        int256 startingTick;
        uint256 mostSigBit;
    }

    struct ConstantViews {
        address liquidity;
        address factory;
        address adminImplementation;
        address secondaryImplementation;
        address supplyToken;
        address borrowToken;
        uint8 supplyDecimals;
        uint8 borrowDecimals;
        uint vaultId;
        bytes32 liquiditySupplyExchangePriceSlot;
        bytes32 liquidityBorrowExchangePriceSlot;
        bytes32 liquidityUserSupplySlot;
        bytes32 liquidityUserBorrowSlot;
    }

    struct RebalanceMemoryVariables {
        uint256 liqSupplyExPrice;
        uint256 liqBorrowExPrice;
        uint256 vaultSupplyExPrice;
        uint256 vaultBorrowExPrice;
    }
}
