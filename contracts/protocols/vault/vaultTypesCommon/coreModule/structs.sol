// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Structs {
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
        uint256 actualDebtAmt;
        uint256 actualColAmt;
    }

    struct AbsorbMemoryVariables {
        uint256 debtAbsorbed;
        uint256 colAbsorbed;
        int256 startingTick;
        uint256 mostSigBit;
    }

    struct Tokens {
        address token0;
        address token1;
    }

    struct ConstantViews {
        address liquidity;
        address factory;
        address operateImplementation;
        address adminImplementation;
        address secondaryImplementation;
        address deployer; // address which deploys oracle
        address supply; // either liquidity layer or DEX protocol
        address borrow; // either liquidity layer or DEX protocol
        Tokens supplyToken; // if smart collateral then address of token0 & token1 else just supply token address at token0 and token1 as empty
        Tokens borrowToken; // if smart debt then address of token0 & token1 else just borrow token address at token0 and token1 as empty
        uint256 vaultId;
        uint256 vaultType;
        bytes32 supplyExchangePriceSlot; // if smart collateral then slot is from DEX protocol else from liquidity layer
        bytes32 borrowExchangePriceSlot; // if smart debt then slot is from DEX protocol else from liquidity layer
        bytes32 userSupplySlot; // if smart collateral then slot is from DEX protocol else from liquidity layer
        bytes32 userBorrowSlot; // if smart debt then slot is from DEX protocol else from liquidity layer
    }

    struct RebalanceMemoryVariables {
        uint256 liqSupplyExPrice;
        uint256 liqBorrowExPrice;
        uint256 vaultSupplyExPrice;
        uint256 vaultBorrowExPrice;
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 totalSupplyVault;
        uint256 totalBorrowVault;
        uint256 initialEth;
    }
}
