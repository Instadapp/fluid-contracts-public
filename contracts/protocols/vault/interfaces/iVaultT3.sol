//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IFluidVault } from "./iVault.sol";

interface IFluidVaultT3 is IFluidVault {
    function operate(
        uint nftId_,
        int newCol_,
        int newDebtToken0_,
        int newDebtToken1_,
        int debtSharesMinMax_,
        address to_
    )
        external
        payable
        returns (
            uint256, // nftId_
            int256, // final supply amount. if - then withdraw
            int256 // final borrow amount. if - then payback
        );

    function operatePerfect(
        uint nftId_,
        int newCol_,
        int perfectDebtShares_,
        int debtToken0MinMax_,
        int debtToken1MinMax_,
        address to_
    )
        external
        payable
        returns (
            uint256, // nftId_
            int256[] memory r_
        );

    function liquidate(
        uint256 token0DebtAmt_,
        uint256 token1DebtAmt_,
        uint256 debtSharesMin_,
        uint256 colPerUnitDebt_,
        address to_,
        bool absorb_
    ) external payable returns (uint256 actualDebtShares_, uint256 actualCol_);

    function liquidatePerfect(
        uint256 debtShares_,
        uint256 token0DebtAmtPerUnitShares_,
        uint256 token1DebtAmtPerUnitShares_,
        uint256 colPerUnitDebt_,
        address to_,
        bool absorb_
    )
        external
        payable
        returns (uint256 actualDebtShares_, uint256 token0Debt_, uint256 token1Debt_, uint256 actualCol_);
}
