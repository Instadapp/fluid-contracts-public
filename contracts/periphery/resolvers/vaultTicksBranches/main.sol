// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { TickMath } from "../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";
import { IFluidVault } from "../../../protocols/vault/interfaces/iVault.sol";
import { IFluidVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";

import { Structs } from "./structs.sol";
import { Variables } from "./variables.sol";

/// @notice Fluid Vault protocol ticks & branches resolver for all vault types.
contract FluidVaultTicksBranchesResolver is Variables, Structs {
    /// @notice thrown if an input param address is zero
    error FluidVaultTicksBranchesResolver__AddressZero();

    /// @notice constructor sets the immutable vault resolver address
    constructor(IFluidVaultResolver vaultResolver_) Variables(vaultResolver_) {
        if (address(vaultResolver_) == address(0)) {
            revert FluidVaultTicksBranchesResolver__AddressZero();
        }
    }

    function getTicksDebt(
        address vault_,
        int fromTick_,
        uint totalTicks_
    ) public view returns (TickDebt[] memory ticksDebt_, int toTick_) {
        int topTick_ = _tickHelper(((VAULT_RESOLVER.getVaultVariablesRaw(vault_) >> 2) & X20));

        fromTick_ = topTick_ < fromTick_ ? topTick_ : fromTick_;
        if (fromTick_ > type(int).min) {
            // if fromTick_ == tpye(int).min means top tick is not set, meaning no positions exist
            int startMapId_ = fromTick_ < 0 ? ((fromTick_ + 1) / 256) - 1 : fromTick_ / 256;
            // Removing all other after fromTick
            uint tickHasDebt_;
            {
                uint tickHasDebtRaw_ = VAULT_RESOLVER.getTickHasDebtRaw(vault_, startMapId_);

                uint bitsToRemove_ = uint(-fromTick_ + (startMapId_ * 256 + 255));
                tickHasDebt_ = (tickHasDebtRaw_ << bitsToRemove_) >> bitsToRemove_;
            }

            // Adding 1 here as toTick_ is inclusive in the data so if totalTicks_ = 400 then it'll only check 400
            toTick_ = fromTick_ - int(totalTicks_) + 1;

            uint count_ = _countTicksWithDebt(vault_, toTick_, startMapId_, tickHasDebt_);

            (, , uint vaultSupplyExchangePrice_, uint vaultBorrowExchangePrice_) = IFluidVault(vault_)
                .updateExchangePrices(VAULT_RESOLVER.getVaultVariables2Raw(vault_));

            ticksDebt_ = _populateTicksDebt(
                vault_,
                toTick_,
                startMapId_,
                tickHasDebt_,
                count_,
                vaultSupplyExchangePrice_,
                vaultBorrowExchangePrice_
            );
        }
    }

    function getMultipleVaultsTicksDebt(
        address[] memory vaults_,
        int[] memory fromTicks_,
        uint[] memory totalTicks_
    ) public view returns (VaultsTickDebt[] memory vaultsTickDebt_) {
        uint length_ = vaults_.length;

        vaultsTickDebt_ = new VaultsTickDebt[](length_);
        for (uint i = 0; i < length_; i++) {
            (vaultsTickDebt_[i].tickDebt, vaultsTickDebt_[i].toTick) = getTicksDebt(
                vaults_[i],
                fromTicks_[i],
                totalTicks_[i]
            );
            vaultsTickDebt_[i].vaultAddress = vaults_[i];
            vaultsTickDebt_[i].vaultId = IFluidVaultT1(vaults_[i]).VAULT_ID();
        }
    }

    function getVaultsTicksDebt(
        address[] memory vaults_,
        uint[] memory totalTicks_
    ) public view returns (VaultsTickDebt[] memory vaultsTickDebt_) {
        uint length_ = vaults_.length;

        vaultsTickDebt_ = new VaultsTickDebt[](length_);
        for (uint i = 0; i < length_; i++) {
            (vaultsTickDebt_[i].tickDebt, vaultsTickDebt_[i].toTick) = getTicksDebt(
                vaults_[i],
                type(int).max,
                totalTicks_[i]
            );
            vaultsTickDebt_[i].vaultAddress = vaults_[i];
            vaultsTickDebt_[i].vaultId = IFluidVaultT1(vaults_[i]).VAULT_ID();
        }
    }

    function getAllVaultsTicksDebt(uint totalTicks_) public view returns (VaultsTickDebt[] memory vaultsTickDebt_) {
        address[] memory vaults_ = VAULT_RESOLVER.getAllVaultsAddresses();
        uint length_ = vaults_.length;

        uint[] memory totalTicksArray_ = new uint[](length_);
        for (uint i = 0; i < length_; i++) totalTicksArray_[i] = totalTicks_;

        return getVaultsTicksDebt(vaults_, totalTicksArray_);
    }

    function getBranchesDebt(
        address vault_,
        uint fromBranchId_,
        uint toBranchId_
    ) public view returns (BranchDebt[] memory branchesDebt_) {
        uint vaultVariables_ = VAULT_RESOLVER.getVaultVariablesRaw(vault_);
        uint totalBranch_ = (vaultVariables_ >> 52) & X30;
        toBranchId_ = (toBranchId_ == 0 ? 1 : toBranchId_);
        fromBranchId_ = (totalBranch_ < fromBranchId_ ? totalBranch_ : fromBranchId_);

        require(fromBranchId_ >= toBranchId_, "fromBranchId_ must be greater than or equal to toBranchId_");

        branchesDebt_ = new BranchDebt[](fromBranchId_ - toBranchId_ + 1);

        uint index_;

        for (uint i = fromBranchId_; i >= toBranchId_; i--) {
            branchesDebt_[index_++] = _getBranchDebt(vault_, vaultVariables_, i);
        }
    }

    function getMultipleVaultsBranchesDebt(
        address[] memory vaults_,
        uint[] memory fromBranchIds_,
        uint[] memory toBranchIds_
    ) external view returns (BranchesDebt[] memory branchesDebt_) {
        uint length_ = vaults_.length;

        branchesDebt_ = new BranchesDebt[](length_);
        for (uint i = 0; i < length_; i++) {
            branchesDebt_[i].branchDebt = getBranchesDebt(vaults_[i], fromBranchIds_[i], toBranchIds_[i]);
            branchesDebt_[i].vaultAddress = vaults_[i];
            branchesDebt_[i].vaultId = IFluidVaultT1(vaults_[i]).VAULT_ID();
        }
    }

    function getVaultsBranchesDebt(address[] memory vaults_) public view returns (BranchesDebt[] memory branchesDebt_) {
        uint length_ = vaults_.length;

        branchesDebt_ = new BranchesDebt[](length_);
        for (uint i = 0; i < length_; i++) {
            branchesDebt_[i].branchDebt = getBranchesDebt(vaults_[i], type(uint).max, 0);
            branchesDebt_[i].vaultAddress = vaults_[i];
            branchesDebt_[i].vaultId = IFluidVaultT1(vaults_[i]).VAULT_ID();
        }
    }

    function getAllVaultsBranchesDebt() external view returns (BranchesDebt[] memory) {
        return getVaultsBranchesDebt(VAULT_RESOLVER.getAllVaultsAddresses());
    }

    function _populateTicksDebt(
        address vault_,
        int toTick_,
        int mapId_,
        uint tickHasDebt_,
        uint count_,
        uint vaultSupplyExchangePrice_,
        uint vaultBorrowExchangePrice_
    ) internal view returns (TickDebt[] memory ticksDebt_) {
        ticksDebt_ = new TickDebt[](count_);

        count_ = 0; // reuse var for loop index counter
        int nextTick_;
        uint tickExistingRawDebt_;
        uint ratio_;
        uint collateralRaw_;

        while (true) {
            while (tickHasDebt_ > 0) {
                {
                    uint msb_ = BigMathMinified.mostSignificantBit(tickHasDebt_);
                    // removing next tick from tickHasDebt
                    tickHasDebt_ = (tickHasDebt_ << (257 - msb_)) >> (257 - msb_);
                    nextTick_ = mapId_ * 256 + int(msb_) - 1;
                }
                if (nextTick_ < toTick_) {
                    return ticksDebt_;
                }
                tickExistingRawDebt_ = (VAULT_RESOLVER.getTickDataRaw(vault_, nextTick_) >> 25) & X64;
                tickExistingRawDebt_ = (tickExistingRawDebt_ >> 8) << (tickExistingRawDebt_ & X8);
                ratio_ = TickMath.getRatioAtTick(nextTick_);
                collateralRaw_ = (tickExistingRawDebt_ * (1 << 96)) / ratio_;
                ticksDebt_[count_++] = TickDebt({
                    debtRaw: tickExistingRawDebt_,
                    collateralRaw: collateralRaw_,
                    debtNormal: (tickExistingRawDebt_ * vaultBorrowExchangePrice_) / 1e12,
                    collateralNormal: (collateralRaw_ * vaultSupplyExchangePrice_) / 1e12,
                    ratio: ratio_,
                    tick: nextTick_
                });
            }

            if (--mapId_ == -129) {
                break;
            }

            tickHasDebt_ = VAULT_RESOLVER.getTickHasDebtRaw(vault_, mapId_);
        }
    }

    function _tickHelper(uint tickRaw_) internal pure returns (int tick) {
        require(tickRaw_ < X20, "invalid-number");
        if (tickRaw_ > 0) {
            tick = tickRaw_ & 1 == 1 ? int((tickRaw_ >> 1) & X19) : -int((tickRaw_ >> 1) & X19);
        } else {
            tick = type(int).min;
        }
    }

    function _countTicksWithDebt(
        address vault_,
        int toTick_,
        int mapId_,
        uint tickHasDebt_
    ) internal view returns (uint count_) {
        uint msb_;
        int nextTick_;
        while (true) {
            while (tickHasDebt_ > 0) {
                msb_ = BigMathMinified.mostSignificantBit(tickHasDebt_);
                // removing next tick from tickHasDebt
                tickHasDebt_ = (tickHasDebt_ << (257 - msb_)) >> (257 - msb_);
                nextTick_ = mapId_ * 256 + int(msb_ - 1);
                if (nextTick_ < toTick_) {
                    return count_;
                }
                count_++;
            }

            if (--mapId_ == -129) {
                break;
            }
            tickHasDebt_ = VAULT_RESOLVER.getTickHasDebtRaw(vault_, mapId_);
        }
        return count_;
    }

    function _getBranchDebt(
        address vault_,
        uint vaultVariables_,
        uint branchId_
    ) internal view returns (BranchDebt memory) {
        uint currentBranchData_ = VAULT_RESOLVER.getBranchDataRaw(vault_, branchId_);

        int minimaTick_ = _tickHelper((currentBranchData_ >> 2) & X20);
        uint status_ = currentBranchData_ & 3;

        if (status_ == 0) {
            // not liquidated status == 0
            // only current branch can be non-liquidated branch
            return _getActiveBranchDebt(vaultVariables_, currentBranchData_, branchId_, status_);
        } else if (status_ == 1) {
            // liquidated status == 1
            return _getLiquidatedBranchDebt(vault_, currentBranchData_, branchId_, status_, minimaTick_);
        } else {
            // merged status == 2
            // absorbed status == 3
            return _getClosedOrMergedBranchDebt(currentBranchData_, branchId_, status_);
        }
    }

    function _getActiveBranchDebt(
        uint vaultVariables_,
        uint currentBranchData_,
        uint branchId_,
        uint status_
    ) internal pure returns (BranchDebt memory branchDebt_) {
        int topTick_ = _tickHelper((vaultVariables_ >> 2) & X20);

        uint ratio_ = topTick_ > type(int).min ? TickMath.getRatioAtTick(topTick_) : 0;

        branchDebt_ = BranchDebt({
            debtRaw: 0,
            collateralRaw: 0,
            debtNormal: 0,
            collateralNormal: 0,
            branchId: branchId_,
            status: status_, // active status
            tick: topTick_, // as branch is not liquidated, just returning topTick for now, as whenever liquidation starts it'll start from topTick
            partials: 0,
            ratio: ratio_,
            debtFactor: (currentBranchData_ >> 116) & X50,
            baseBranchId: ((currentBranchData_ >> 166) & X30),
            baseBranchTick: _tickHelper((currentBranchData_ >> 196) & X20) // if == type(int).min, then current branch is master branch
        });
    }

    function _getClosedOrMergedBranchDebt(
        uint currentBranchData_,
        uint branchId_,
        uint status_
    ) internal pure returns (BranchDebt memory branchDebt_) {
        int baseBranchTick_ = _tickHelper((currentBranchData_ >> 196) & X20);
        uint ratio_ = baseBranchTick_ > type(int).min ? TickMath.getRatioAtTick(baseBranchTick_) : 0;

        branchDebt_ = BranchDebt({
            debtRaw: 0,
            collateralRaw: 0,
            debtNormal: 0,
            collateralNormal: 0,
            branchId: branchId_,
            status: status_,
            tick: baseBranchTick_, // as branch is merged/closed, so adding baseBranchTick_ as this is where it went out of existance
            partials: 0,
            ratio: ratio_,
            debtFactor: (currentBranchData_ >> 116) & X50,
            baseBranchId: ((currentBranchData_ >> 166) & X30),
            baseBranchTick: baseBranchTick_ // if == type(int).min, then current branch is master branch
        });
    }

    function _getLiquidatedBranchDebt(
        address vault_,
        uint currentBranchData_,
        uint branchId_,
        uint status_,
        int minimaTick_
    ) internal view returns (BranchDebt memory branchDebt_) {
        uint debtLiquidity_ = BigMathMinified.fromBigNumber((currentBranchData_ >> 52) & X64, 8, X8);
        (uint collateralRaw_, uint ratio_) = _getCollateralRaw(currentBranchData_, debtLiquidity_, minimaTick_);

        (, , uint256 vaultSupplyExchangePrice_, uint256 vaultBorrowExchangePrice_) = IFluidVault(vault_)
            .updateExchangePrices(VAULT_RESOLVER.getVaultVariables2Raw(vault_));

        branchDebt_ = BranchDebt({
            debtRaw: debtLiquidity_,
            collateralRaw: collateralRaw_,
            debtNormal: (debtLiquidity_ * vaultBorrowExchangePrice_) / 1e12,
            collateralNormal: (collateralRaw_ * vaultSupplyExchangePrice_) / 1e12,
            branchId: branchId_,
            status: status_,
            tick: minimaTick_, // as branch is merged/closed, so adding baseBranchTick_ as this is where it went out of existance
            partials: 0,
            ratio: ratio_,
            debtFactor: (currentBranchData_ >> 116) & X50,
            baseBranchId: ((currentBranchData_ >> 166) & X30),
            baseBranchTick: _tickHelper((currentBranchData_ >> 196) & X20) // if == type(int).min, then current branch is master branch,
        });
    }

    function _getCollateralRaw(
        uint currentBranchData_,
        uint debtLiquidity_,
        int minimaTick_
    ) internal pure returns (uint collateralRaw_, uint ratio_) {
        ratio_ = TickMath.getRatioAtTick(int24(minimaTick_));
        uint ratioOneLess_ = (ratio_ * 10000) / 10015;
        uint length_ = ratio_ - ratioOneLess_;
        uint partials_ = (currentBranchData_ >> 22) & X30;
        uint currentRatio_ = ratioOneLess_ + ((length_ * partials_) / X30);
        collateralRaw_ = (debtLiquidity_ * TickMath.ZERO_TICK_SCALED_RATIO) / currentRatio_;
    }
}
