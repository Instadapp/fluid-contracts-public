//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IFluidVault } from "./iVault.sol";

interface IFluidVaultT1_Not_For_Prod is IFluidVault {
    function operate(
        uint256 nftId_, // if 0 then new position
        int256 newCol_, // if negative then withdraw
        int256 newDebt_, // if negative then payback
        address to_, // address at which the borrow & withdraw amount should go to. If address(0) then it'll go to msg.sender
        uint256 vaultVariables_
    )
        external
        payable
        returns (
            uint256, // nftId_
            int256, // final supply amount. if - then withdraw
            int256, // final borrow amount. if - then payback
            uint256
        );

    function liquidate(
        uint256 debtAmt_,
        uint256 colPerUnitDebt_, // min collateral needed per unit of debt in 1e18
        address to_,
        bool absorb_
    ) external payable returns (uint actualDebtAmt_, uint actualColAmt_);
}
