// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Variables {
    /***********************************|
    |         Storage Variables         |
    |__________________________________*/

    /// note: in all variables. For tick >= 0 are represented with bit as 1, tick < 0 are represented with bit as 0
    /// note: read all the variables through storageRead.sol

    /// note: vaultVariables contains vault variables which need regular updates through transactions
    /// First 1 bit => 0 => re-entrancy. If 0 then allow transaction to go, else throw.
    /// Next 1 bit => 1 => Is the current active branch liquidated? If true then check the branch's minima tick before creating a new position
    /// If the new tick is greater than minima tick then initialize a new branch, make that as current branch & do proper linking
    /// Next 1 bit => 2 => sign of topmost tick (0 -> negative; 1 -> positive)
    /// Next 19 bits => 3-21 => absolute value of topmost tick
    /// Next 30 bits => 22-51 => current branch ID
    /// Next 30 bits => 52-81 => total branch ID
    /// Next 64 bits => 82-145 => Total supply
    /// Next 64 bits => 146-209 => Total borrow
    /// Next 32 bits => 210-241 => Total positions
    uint256 internal vaultVariables;

    /// note: vaultVariables2 contains variables which do not update on every transaction. So mainly admin/auth set amount
    /// First 16 bits => 0-15 => supply rate magnifier; 10000 = 1x (Here 16 bits should be more than enough)
    /// Next 16 bits => 16-31 => borrow rate magnifier; 10000 = 1x (Here 16 bits should be more than enough)
    /// Next 10 bits => 32-41 => collateral factor. 800 = 0.8 = 80% (max precision of 0.1%)
    /// Next 10 bits => 42-51 => liquidation Threshold. 900 = 0.9 = 90% (max precision of 0.1%)
    /// Next 10 bits => 52-61 => liquidation Max Limit. 950 = 0.95 = 95% (max precision of 0.1%) (above this 100% liquidation can happen)
    /// Next 10 bits => 62-71 => withdraw gap. 100 = 0.1 = 10%. (max precision of 0.1%) (max 7 bits can also suffice for the requirement here of 0.1% to 10%). Needed to save some limits on withdrawals so liquidate can work seamlessly.
    /// Next 10 bits => 72-81 => liquidation penalty. 100 = 0.01 = 1%. (max precision of 0.01%) (max liquidation penantly can be 10.23%). Applies when tick is in between liquidation Threshold & liquidation Max Limit.
    /// Next 10 bits => 82-91 => borrow fee. 100 = 0.01 = 1%. (max precision of 0.01%) (max borrow fee can be 10.23%). Fees on borrow.
    /// Next 4  bits => 92-95 => empty
    /// Next 160 bits => 96-255 => Oracle address
    uint256 internal vaultVariables2;

    /// note: stores absorbed liquidity
    /// First 128 bits raw debt amount
    /// last 128 bits raw col amount
    uint256 internal absorbedLiquidity;

    /// position index => position data uint
    /// if the entire variable is 0 (meaning not initialized) at the start that means no position at all
    /// First 1 bit => 0 => position type (0 => borrow position; 1 => supply position)
    /// Next 1 bit => 1 => sign of user's tick (0 => negative; 1 => positive)
    /// Next 19 bits => 2-20 => absolute value of user's tick
    /// Next 24 bits => 21-44 => user's tick's id
    /// Below we are storing user's collateral & not debt, because the position can also be only collateral with no tick but it can never be only debt
    /// Next 64 bits => 45-108 => user's supply amount. Debt will be calculated through supply & ratio.
    /// Next 64 bits => 109-172 => user's dust debt amount. User's net debt = total debt - dust amount. Total debt is calculated through supply & ratio
    /// User won't pay any extra interest on dust debt & hence we will not show it as a debt on UI. For user's there's no dust.
    mapping(uint256 => uint256) internal positionData;

    /// Tick has debt only keeps data of non liquidated positions. liquidated tick's data stays in branch itself
    /// tick parent => uint (represents bool for 256 children)
    /// parent of (i)th tick:-
    /// if (i>=0) (i / 256);
    /// else ((i + 1) / 256) - 1
    /// first bit of the variable is the smallest tick & last bit is the biggest tick of that slot
    mapping(int256 => uint256) internal tickHasDebt;

    /// mapping tickId => tickData
    /// Tick related data. Total debt & other things
    /// First bit => 0 => If 1 then liquidated else not liquidated
    /// Next 24 bits => 1-24 => Total IDs. ID should start from 1.
    /// If not liquidated:
    /// Next 64 bits => 25-88 => raw debt
    /// If liquidated
    /// The below 3 things are of last ID. This is to be updated when user creates a new position
    /// Next 1 bit => 25 => Is 100% liquidated? If this is 1 meaning it was above max tick when it got liquidated (100% liquidated)
    /// Next 30 bits => 26-55 => branch ID where this tick got liquidated
    /// Next 50 bits => 56-105 => debt factor 50 bits (35 bits coefficient | 15 bits expansion)
    mapping(int256 => uint256) internal tickData;

    /// tick id => previous tick id liquidation data. ID starts from 1
    /// One tick ID contains 3 IDs of 80 bits in it, holding liquidation data of previously active but liquidated ticks
    /// 81 bits data below
    /// #### First 85 bits ####
    /// 1st bit => 0 => Is 100% liquidated? If this is 1 meaning it was above max tick when it got liquidated
    /// Next 30 bits => 1-30 => branch ID where this tick got liquidated
    /// Next 50 bits => 31-80 => debt factor 50 bits (35 bits coefficient | 15 bits expansion)
    /// #### Second 85 bits ####
    /// 85th bit => 85 => Is 100% liquidated? If this is 1 meaning it was above max tick when it got liquidated
    /// Next 30 bits => 86-115 => branch ID where this tick got liquidated
    /// Next 50 bits => 116-165 => debt factor 50 bits (35 bits coefficient | 15 bits expansion)
    /// #### Third 85 bits ####
    /// 170th bit => 170 => Is 100% liquidated? If this is 1 meaning it was above max tick when it got liquidated
    /// Next 30 bits => 171-200 => branch ID where this tick got liquidated
    /// Next 50 bits => 201-250 => debt factor 50 bits (35 bits coefficient | 15 bits expansion)
    mapping(int256 => mapping(uint256 => uint256)) internal tickId;

    /// mapping branchId => branchData
    /// First 2 bits => 0-1 => if 0 then not liquidated, if 1 then liquidated, if 2 then merged, if 3 then closed
    /// merged means the branch is merged into it's base branch
    /// closed means all the users are 100% liquidated
    /// Next 1 bit => 2 => minima tick sign of this branch. Will only be there if any liquidation happened.
    /// Next 19 bits => 3-21 => minima tick of this branch. Will only be there if any liquidation happened.
    /// Next 30 bits => 22-51 => Partials of minima tick of branch this is connected to. 0 if master branch.
    /// Next 64 bits => 52-115 Debt liquidity at this branch. Similar to last's top tick data. Remaining debt will move here from tickData after first liquidation
    /// If not merged
    /// Next 50 bits => 116-165 => Debt factor or of this branch. (35 bits coefficient | 15 bits expansion)
    /// If merged
    /// Next 50 bits => 116-165 => Connection/adjustment debt factor of this branch with the next branch.
    /// If closed
    /// Next 50 bits => 116-165 => Debt factor as 0. As all the user's positions are now fully gone
    /// following values are present always again (merged / not merged / closed)
    /// Next 30 bits => 166-195 => Branch's ID with which this branch is connected. If 0 then that means this is the master branch
    /// Next 1 bit => 196 => sign of minima tick of branch this is connected to. 0 if master branch.
    /// Next 19 bits => 197-215 => minima tick of branch this is connected to. 0 if master branch.
    mapping(uint256 => uint256) internal branchData;

    /// Exchange prices are in 1e12
    /// First 64 bits => 0-63 => Liquidity's collateral token supply exchange price
    /// First 64 bits => 64-127 => Liquidity's debt token borrow exchange price
    /// First 64 bits => 128-191 => Vault's collateral token supply exchange price
    /// First 64 bits => 192-255 => Vault's debt token borrow exchange price
    uint256 internal rates;

    /// address of rebalancer
    address internal rebalancer;

    uint256 internal absorbedDustDebt;
}
