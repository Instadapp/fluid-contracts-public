// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Structs {
    struct TickDebt {
        uint256 debtRaw;
        uint256 collateralRaw;
        uint256 debtNormal; // debtRaw * exchange price
        uint256 collateralNormal; // collateralRaw * exchange price
        uint256 ratio;
        int256 tick;
    }

    struct VaultsTickDebt {
        TickDebt[] tickDebt;
        int toTick;
        address vaultAddress;
        uint256 vaultId;
    }

    struct BranchDebt {
        uint256 debtRaw;
        uint256 collateralRaw;
        uint256 debtNormal; // debtRaw * exchange price
        uint256 collateralNormal; // collateralRaw * exchange price
        uint256 branchId;
        uint256 status; // if 0 then not liquidated, if 1 then liquidated, if 2 then merged, if 3 then closed
        int256 tick;
        uint256 partials;
        uint256 ratio;
        uint debtFactor; // debt factor or connection factor
        uint baseBranchId;
        int baseBranchTick;
    }

    struct BranchesDebt {
        BranchDebt[] branchDebt;
        address vaultAddress;
        uint256 vaultId;
    }
}
