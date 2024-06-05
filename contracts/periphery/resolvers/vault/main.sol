// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Helpers } from "./helpers.sol";
import { TickMath } from "../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { IFluidOracle } from "../../../oracle/fluidOracle.sol";
import { IFluidVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";
import { Structs as FluidLiquidityResolverStructs } from "../liquidity/structs.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";

interface TokenInterface {
    function balanceOf(address) external view returns (uint);
}

/// @notice Fluid Vault protocol resolver
/// Implements various view-only methods to give easy access to Vault protocol data.
contract FluidVaultResolver is Helpers {
    constructor(
        address factory_,
        address liquidity_,
        address liquidityResolver_
    ) Helpers(factory_, liquidity_, liquidityResolver_) {}

    function getVaultAddress(uint256 vaultId_) public view returns (address vault_) {
        // @dev based on https://ethereum.stackexchange.com/a/61413
        bytes memory data;
        if (vaultId_ == 0x00) {
            // nonce of smart contract always starts with 1. so, with nonce 0 there won't be any deployment
            return address(0);
        } else if (vaultId_ <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), address(FACTORY), uint8(vaultId_));
        } else if (vaultId_ <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), address(FACTORY), bytes1(0x81), uint8(vaultId_));
        } else if (vaultId_ <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), address(FACTORY), bytes1(0x82), uint16(vaultId_));
        } else if (vaultId_ <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), address(FACTORY), bytes1(0x83), uint24(vaultId_));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), address(FACTORY), bytes1(0x84), uint32(vaultId_));
        }

        return address(uint160(uint256(keccak256(data))));
    }

    function getVaultId(address vault_) public view returns (uint id_) {
        id_ = IFluidVaultT1(vault_).VAULT_ID();
    }

    function getTokenConfig(uint nftId_) public view returns (uint) {
        return FACTORY.readFromStorage(calculateStorageSlotUintMapping(3, nftId_));
    }

    function getVaultVariablesRaw(address vault_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(normalSlot(0));
    }

    function getVaultVariables2Raw(address vault_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(normalSlot(1));
    }

    function getAbsorbedLiquidityRaw(address vault_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(normalSlot(2));
    }

    function getPositionDataRaw(address vault_, uint positionId_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(calculateStorageSlotUintMapping(3, positionId_));
    }

    // if tick > 0 then key_ = tick / 256
    // if tick < 0 then key_ = (tick / 256) - 1
    function getTickHasDebtRaw(address vault_, int key_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(calculateStorageSlotIntMapping(4, key_));
    }

    function getTickDataRaw(address vault_, int tick_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(calculateStorageSlotIntMapping(5, tick_));
    }

    // TODO: Verify below
    // id_ = (realId_ / 3) + 1
    function getTickIdDataRaw(address vault_, int tick_, uint id_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(calculateDoubleIntUintMapping(6, tick_, id_));
    }

    function getBranchDataRaw(address vault_, uint branch_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(calculateStorageSlotUintMapping(7, branch_));
    }

    function getRateRaw(address vault_) public view returns (uint) {
        return IFluidVaultT1(vault_).readFromStorage(normalSlot(8));
    }

    function getRebalancer(address vault_) public view returns (address) {
        return address(uint160(IFluidVaultT1(vault_).readFromStorage(normalSlot(9))));
    }

    function getTotalVaults() public view returns (uint) {
        return FACTORY.totalVaults();
    }

    function getAllVaultsAddresses() public view returns (address[] memory vaults_) {
        uint totalVaults_ = getTotalVaults();
        vaults_ = new address[](totalVaults_);
        for (uint i = 0; i < totalVaults_; i++) {
            vaults_[i] = getVaultAddress((i + 1));
        }
    }

    function _getVaultConstants(address vault_) internal view returns (IFluidVaultT1.ConstantViews memory constants_) {
        constants_ = IFluidVaultT1(vault_).constantsView();
    }

    function _getVaultConfig(address vault_) internal view returns (Configs memory configs_) {
        uint vaultVariables2_ = getVaultVariables2Raw(vault_);
        configs_.supplyRateMagnifier = uint16(vaultVariables2_ & X16);
        configs_.borrowRateMagnifier = uint16((vaultVariables2_ >> 16) & X16);
        configs_.collateralFactor = (uint16((vaultVariables2_ >> 32) & X10)) * 10;
        configs_.liquidationThreshold = (uint16((vaultVariables2_ >> 42) & X10)) * 10;
        configs_.liquidationMaxLimit = (uint16((vaultVariables2_ >> 52) & X10) * 10);
        configs_.withdrawalGap = uint16((vaultVariables2_ >> 62) & X10) * 10;
        configs_.liquidationPenalty = uint16((vaultVariables2_ >> 72) & X10);
        configs_.borrowFee = uint16((vaultVariables2_ >> 82) & X10);
        configs_.oracle = address(uint160(vaultVariables2_ >> 96));
        if (configs_.oracle != address(0)) {
            try IFluidOracle(configs_.oracle).getExchangeRateOperate() returns (uint256 exchangeRate_) {
                configs_.oraclePriceOperate = exchangeRate_;
                configs_.oraclePriceLiquidate = IFluidOracle(configs_.oracle).getExchangeRateLiquidate();
            } catch {
                // deprecated backward compatible for older vaults oracles
                configs_.oraclePriceOperate = IFluidOracle(configs_.oracle).getExchangeRate();
                configs_.oraclePriceLiquidate = configs_.oraclePriceOperate;
            }
        }
        configs_.rebalancer = getRebalancer(vault_);
    }

    function _getExchangePricesAndRates(
        address vault_,
        Configs memory configs_,
        FluidLiquidityResolverStructs.OverallTokenData memory liquiditySupplytokenData_,
        FluidLiquidityResolverStructs.OverallTokenData memory liquidityBorrowtokenData_
    ) internal view returns (ExchangePricesAndRates memory exchangePricesAndRates_) {
        uint exchangePrices_ = getRateRaw(vault_);
        exchangePricesAndRates_.lastStoredLiquiditySupplyExchangePrice = exchangePrices_ & X64;
        exchangePricesAndRates_.lastStoredLiquidityBorrowExchangePrice = (exchangePrices_ >> 64) & X64;
        exchangePricesAndRates_.lastStoredVaultSupplyExchangePrice = (exchangePrices_ >> 128) & X64;
        exchangePricesAndRates_.lastStoredVaultBorrowExchangePrice = (exchangePrices_ >> 192) & X64;

        (
            exchangePricesAndRates_.liquiditySupplyExchangePrice,
            exchangePricesAndRates_.liquidityBorrowExchangePrice,
            exchangePricesAndRates_.vaultSupplyExchangePrice,
            exchangePricesAndRates_.vaultBorrowExchangePrice
        ) = IFluidVaultT1(vault_).updateExchangePrices(getVaultVariables2Raw(vault_));

        exchangePricesAndRates_.supplyRateLiquidity = liquiditySupplytokenData_.supplyRate;
        exchangePricesAndRates_.borrowRateLiquidity = liquidityBorrowtokenData_.borrowRate;
        exchangePricesAndRates_.supplyRateVault =
            (liquiditySupplytokenData_.supplyRate * configs_.supplyRateMagnifier) /
            10000;
        exchangePricesAndRates_.borrowRateVault =
            (liquidityBorrowtokenData_.borrowRate * configs_.borrowRateMagnifier) /
            10000;
        exchangePricesAndRates_.rewardsRate = configs_.supplyRateMagnifier > 10000
            ? configs_.supplyRateMagnifier - 10000
            : 0;
    }

    function _getTotalSupplyAndBorrow(
        address vault_,
        ExchangePricesAndRates memory exchangePricesAndRates_,
        IFluidVaultT1.ConstantViews memory constantsVariables_
    ) internal view returns (TotalSupplyAndBorrow memory totalSupplyAndBorrow_) {
        uint vaultVariables_ = getVaultVariablesRaw(vault_);
        uint absorbedLiquidity_ = getAbsorbedLiquidityRaw(vault_);
        uint totalSupplyLiquidity_ = LIQUIDITY.readFromStorage(constantsVariables_.liquidityUserSupplySlot);
        // extracting user's supply
        totalSupplyLiquidity_ = (totalSupplyLiquidity_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        // converting big number into normal number
        totalSupplyLiquidity_ = (totalSupplyLiquidity_ >> 8) << (totalSupplyLiquidity_ & X8);
        uint totalBorrowLiquidity_ = LIQUIDITY.readFromStorage(constantsVariables_.liquidityUserBorrowSlot);
        // extracting user's borrow
        totalBorrowLiquidity_ = (totalBorrowLiquidity_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        // converting big number into normal number
        totalBorrowLiquidity_ = (totalBorrowLiquidity_ >> 8) << (totalBorrowLiquidity_ & X8);

        totalSupplyAndBorrow_.totalSupplyVault = (vaultVariables_ >> 82) & X64;
        // Converting bignumber into normal number
        totalSupplyAndBorrow_.totalSupplyVault =
            (totalSupplyAndBorrow_.totalSupplyVault >> 8) <<
            (totalSupplyAndBorrow_.totalSupplyVault & X8);
        totalSupplyAndBorrow_.totalBorrowVault = (vaultVariables_ >> 146) & X64;
        // Converting bignumber into normal number
        totalSupplyAndBorrow_.totalBorrowVault =
            (totalSupplyAndBorrow_.totalBorrowVault >> 8) <<
            (totalSupplyAndBorrow_.totalBorrowVault & X8);

        totalSupplyAndBorrow_.totalSupplyLiquidity = totalSupplyLiquidity_;
        totalSupplyAndBorrow_.totalBorrowLiquidity = totalBorrowLiquidity_;

        totalSupplyAndBorrow_.absorbedBorrow = absorbedLiquidity_ & X128;
        totalSupplyAndBorrow_.absorbedSupply = absorbedLiquidity_ >> 128;

        // converting raw total supply & total borrow into normal amounts
        totalSupplyAndBorrow_.totalSupplyVault =
            (totalSupplyAndBorrow_.totalSupplyVault * exchangePricesAndRates_.vaultSupplyExchangePrice) /
            1e12;
        totalSupplyAndBorrow_.totalBorrowVault =
            (totalSupplyAndBorrow_.totalBorrowVault * exchangePricesAndRates_.vaultBorrowExchangePrice) /
            1e12;
        totalSupplyAndBorrow_.totalSupplyLiquidity =
            (totalSupplyAndBorrow_.totalSupplyLiquidity * exchangePricesAndRates_.liquiditySupplyExchangePrice) /
            1e12;
        totalSupplyAndBorrow_.totalBorrowLiquidity =
            (totalSupplyAndBorrow_.totalBorrowLiquidity * exchangePricesAndRates_.liquidityBorrowExchangePrice) /
            1e12;
        totalSupplyAndBorrow_.absorbedSupply =
            (totalSupplyAndBorrow_.absorbedSupply * exchangePricesAndRates_.vaultSupplyExchangePrice) /
            1e12;
        totalSupplyAndBorrow_.absorbedBorrow =
            (totalSupplyAndBorrow_.absorbedBorrow * exchangePricesAndRates_.vaultBorrowExchangePrice) /
            1e12;
    }

    function _getLimitsAndAvailability(
        TotalSupplyAndBorrow memory totalSupplyAndBorrow_,
        ExchangePricesAndRates memory exchangePricesAndRates_,
        IFluidVaultT1.ConstantViews memory constantsVariables_,
        Configs memory configs_,
        FluidLiquidityResolverStructs.UserBorrowData memory liquidityBorrowtokenData_
    ) internal view returns (LimitsAndAvailability memory limitsAndAvailability_) {
        // fetching user's supply slot data
        uint userSupplyLiquidityData_ = LIQUIDITY.readFromStorage(constantsVariables_.liquidityUserSupplySlot);
        if (userSupplyLiquidityData_ > 0) {
            // converting current user's supply from big number to normal
            uint userSupply_ = (userSupplyLiquidityData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
            userSupply_ = (userSupply_ >> 8) << (userSupply_ & X8);

            // fetching liquidity's withdrawal limit
            uint supplyLimitRaw_ = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(
                userSupplyLiquidityData_,
                userSupply_
            );

            limitsAndAvailability_.withdrawLimit =
                (supplyLimitRaw_ * exchangePricesAndRates_.liquiditySupplyExchangePrice) /
                1e12;

            limitsAndAvailability_.withdrawableUntilLimit = totalSupplyAndBorrow_.totalSupplyLiquidity >
                limitsAndAvailability_.withdrawLimit
                ? totalSupplyAndBorrow_.totalSupplyLiquidity - limitsAndAvailability_.withdrawLimit
                : 0;
            uint withdrawalGap_ = (totalSupplyAndBorrow_.totalSupplyLiquidity * configs_.withdrawalGap) / 1e4;
            limitsAndAvailability_.withdrawableUntilLimit = (limitsAndAvailability_.withdrawableUntilLimit >
                withdrawalGap_)
                ? (((limitsAndAvailability_.withdrawableUntilLimit - withdrawalGap_) * 999999) / 1000000)
                : 0;

            uint balanceOf_;
            if (constantsVariables_.supplyToken == NATIVE_TOKEN_ADDRESS) {
                balanceOf_ = address(LIQUIDITY).balance;
            } else {
                balanceOf_ = TokenInterface(constantsVariables_.supplyToken).balanceOf(address(LIQUIDITY));
            }
            limitsAndAvailability_.withdrawable = balanceOf_ > limitsAndAvailability_.withdrawableUntilLimit
                ? limitsAndAvailability_.withdrawableUntilLimit
                : balanceOf_;
        }

        uint userBorrowLiquidityData_ = LIQUIDITY.readFromStorage(constantsVariables_.liquidityUserBorrowSlot);
        if (userBorrowLiquidityData_ > 0) {
            // converting current user's supply from big number to normal
            uint userBorrow_ = (userBorrowLiquidityData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
            userBorrow_ = (userBorrow_ >> 8) << (userBorrow_ & X8);

            limitsAndAvailability_.borrowLimit = liquidityBorrowtokenData_.borrowLimit;
            limitsAndAvailability_.borrowLimitUtilization = liquidityBorrowtokenData_.borrowLimitUtilization;
            limitsAndAvailability_.borrowableUntilLimit =
                (liquidityBorrowtokenData_.borrowableUntilLimit * 999999) /
                1000000;

            uint balanceOf_;
            if (constantsVariables_.borrowToken == NATIVE_TOKEN_ADDRESS) {
                balanceOf_ = address(LIQUIDITY).balance;
            } else {
                balanceOf_ = TokenInterface(constantsVariables_.borrowToken).balanceOf(address(LIQUIDITY));
            }
            limitsAndAvailability_.borrowable = balanceOf_ > limitsAndAvailability_.borrowableUntilLimit
                ? limitsAndAvailability_.borrowableUntilLimit
                : balanceOf_;
        }

        limitsAndAvailability_.minimumBorrowing = (10001 * exchangePricesAndRates_.vaultBorrowExchangePrice) / 1e12;
    }

    function getVaultState(address vault_) public view returns (VaultState memory vaultState_) {
        uint vaultVariables_ = getVaultVariablesRaw(vault_);

        vaultState_.topTick = tickHelper(((vaultVariables_ >> 2) & X20));
        vaultState_.currentBranch = (vaultVariables_ >> 22) & X30;
        vaultState_.totalBranch = (vaultVariables_ >> 52) & X30;
        vaultState_.totalSupply = BigMathMinified.fromBigNumber((vaultVariables_ >> 82) & X64, 8, X8);
        vaultState_.totalBorrow = BigMathMinified.fromBigNumber((vaultVariables_ >> 146) & X64, 8, X8);
        vaultState_.totalPositions = (vaultVariables_ >> 210) & X32;

        uint currentBranchData_ = getBranchDataRaw(vault_, vaultState_.currentBranch);
        vaultState_.currentBranchState.status = currentBranchData_ & 3;
        vaultState_.currentBranchState.minimaTick = tickHelper(((currentBranchData_ >> 2) & X20));
        vaultState_.currentBranchState.debtFactor = (currentBranchData_ >> 116) & X50;
        vaultState_.currentBranchState.partials = (currentBranchData_ >> 22) & X30;
        vaultState_.currentBranchState.debtLiquidity = BigMathMinified.fromBigNumber(
            (currentBranchData_ >> 52) & X64,
            8,
            X8
        );
        vaultState_.currentBranchState.baseBranchId = (currentBranchData_ >> 166) & X30;
        vaultState_.currentBranchState.baseBranchMinima = tickHelper(((currentBranchData_ >> 196) & X20));
    }

    function getVaultEntireData(address vault_) public view returns (VaultEntireData memory vaultData_) {
        vaultData_.vault = vault_;
        vaultData_.constantVariables = _getVaultConstants(vault_);

        (
            FluidLiquidityResolverStructs.UserSupplyData memory liquidityUserSupplyData_,
            FluidLiquidityResolverStructs.OverallTokenData memory liquiditySupplyTokenData_
        ) = LIQUIDITY_RESOLVER.getUserSupplyData(vault_, vaultData_.constantVariables.supplyToken);

        (
            FluidLiquidityResolverStructs.UserBorrowData memory liquidityUserBorrowData_,
            FluidLiquidityResolverStructs.OverallTokenData memory liquidityBorrowTokenData_
        ) = LIQUIDITY_RESOLVER.getUserBorrowData(vault_, vaultData_.constantVariables.borrowToken);

        vaultData_.configs = _getVaultConfig(vault_);
        vaultData_.exchangePricesAndRates = _getExchangePricesAndRates(
            vault_,
            vaultData_.configs,
            liquiditySupplyTokenData_,
            liquidityBorrowTokenData_
        );
        vaultData_.totalSupplyAndBorrow = _getTotalSupplyAndBorrow(
            vault_,
            vaultData_.exchangePricesAndRates,
            vaultData_.constantVariables
        );
        vaultData_.limitsAndAvailability = _getLimitsAndAvailability(
            vaultData_.totalSupplyAndBorrow,
            vaultData_.exchangePricesAndRates,
            vaultData_.constantVariables,
            vaultData_.configs,
            liquidityUserBorrowData_
        );
        vaultData_.vaultState = getVaultState(vault_);

        vaultData_.liquidityUserSupplyData = liquidityUserSupplyData_;
        vaultData_.liquidityUserBorrowData = liquidityUserBorrowData_;
    }

    function getVaultsEntireData(
        address[] memory vaults_
    ) external view returns (VaultEntireData[] memory vaultsData_) {
        uint length_ = vaults_.length;
        vaultsData_ = new VaultEntireData[](length_);
        for (uint i = 0; i < length_; i++) {
            vaultsData_[i] = getVaultEntireData(vaults_[i]);
        }
    }

    function getVaultsEntireData() external view returns (VaultEntireData[] memory vaultsData_) {
        address[] memory vaults_ = getAllVaultsAddresses();
        uint length_ = vaults_.length;
        vaultsData_ = new VaultEntireData[](length_);
        for (uint i = 0; i < length_; i++) {
            vaultsData_[i] = getVaultEntireData(vaults_[i]);
        }
    }

    function positionByNftId(
        uint nftId_
    ) public view returns (UserPosition memory userPosition_, VaultEntireData memory vaultData_) {
        userPosition_.nftId = nftId_;
        address vault_ = vaultByNftId(nftId_);
        if (vault_ != address(0)) {
            uint positionData_ = getPositionDataRaw(vault_, nftId_);
            vaultData_ = getVaultEntireData(vault_);

            userPosition_.owner = FACTORY.ownerOf(nftId_);
            userPosition_.isSupplyPosition = (positionData_ & 1) == 1;
            userPosition_.supply = (positionData_ >> 45) & X64;
            // Converting big number into normal number
            userPosition_.supply = (userPosition_.supply >> 8) << (userPosition_.supply & X8);
            userPosition_.beforeSupply = userPosition_.supply;
            userPosition_.dustBorrow = (positionData_ >> 109) & X64;
            // Converting big number into normal number
            userPosition_.dustBorrow = (userPosition_.dustBorrow >> 8) << (userPosition_.dustBorrow & X8);
            userPosition_.beforeDustBorrow = userPosition_.dustBorrow;
            if (!userPosition_.isSupplyPosition) {
                userPosition_.tick = (positionData_ & 2) == 2
                    ? int((positionData_ >> 2) & X19)
                    : -int((positionData_ >> 2) & X19);
                userPosition_.tickId = (positionData_ >> 21) & X24;
                userPosition_.borrow =
                    (TickMath.getRatioAtTick(int24(userPosition_.tick)) * userPosition_.supply) >>
                    96;
                userPosition_.beforeBorrow = userPosition_.borrow - userPosition_.beforeDustBorrow;

                uint tickData_ = getTickDataRaw(vault_, userPosition_.tick);

                if (((tickData_ & 1) == 1) || (((tickData_ >> 1) & X24) > userPosition_.tickId)) {
                    // user got liquidated
                    userPosition_.isLiquidated = true;
                    (userPosition_.tick, userPosition_.borrow, userPosition_.supply, , ) = IFluidVaultT1(vault_)
                        .fetchLatestPosition(userPosition_.tick, userPosition_.tickId, userPosition_.borrow, tickData_);
                }

                if (userPosition_.borrow > userPosition_.dustBorrow) {
                    userPosition_.borrow = userPosition_.borrow - userPosition_.dustBorrow;
                } else {
                    // TODO: Make sure this is right. If borrow is less than dust debt then both gets 0
                    userPosition_.borrow = 0;
                    userPosition_.dustBorrow = 0;
                }
            }

            // converting raw amounts into normal
            userPosition_.beforeSupply =
                (userPosition_.beforeSupply * vaultData_.exchangePricesAndRates.vaultSupplyExchangePrice) /
                1e12;
            userPosition_.beforeBorrow =
                (userPosition_.beforeBorrow * vaultData_.exchangePricesAndRates.vaultBorrowExchangePrice) /
                1e12;
            userPosition_.beforeDustBorrow =
                (userPosition_.beforeDustBorrow * vaultData_.exchangePricesAndRates.vaultBorrowExchangePrice) /
                1e12;
            userPosition_.supply =
                (userPosition_.supply * vaultData_.exchangePricesAndRates.vaultSupplyExchangePrice) /
                1e12;
            userPosition_.borrow =
                (userPosition_.borrow * vaultData_.exchangePricesAndRates.vaultBorrowExchangePrice) /
                1e12;
            userPosition_.dustBorrow =
                (userPosition_.dustBorrow * vaultData_.exchangePricesAndRates.vaultBorrowExchangePrice) /
                1e12;
        }
    }

    function positionsNftIdOfUser(address user_) public view returns (uint[] memory nftIds_) {
        uint totalPositions_ = FACTORY.balanceOf(user_);
        nftIds_ = new uint[](totalPositions_);
        for (uint i; i < totalPositions_; i++) {
            nftIds_[i] = FACTORY.tokenOfOwnerByIndex(user_, i);
        }
    }

    function vaultByNftId(uint nftId_) public view returns (address vault_) {
        uint tokenConfig_ = getTokenConfig(nftId_);
        vault_ = FACTORY.getVaultAddress((tokenConfig_ >> 192) & X32);
    }

    function positionsByUser(
        address user_
    ) external view returns (UserPosition[] memory userPositions_, VaultEntireData[] memory vaultsData_) {
        uint[] memory nftIds_ = positionsNftIdOfUser(user_);
        uint length_ = nftIds_.length;
        userPositions_ = new UserPosition[](length_);
        vaultsData_ = new VaultEntireData[](length_);
        for (uint i = 0; i < length_; i++) {
            (userPositions_[i], vaultsData_[i]) = positionByNftId(nftIds_[i]);
        }
    }

    function totalPositions() external view returns (uint) {
        return FACTORY.totalSupply();
    }

    /// @dev fetches available liquidations
    /// @param vault_ address of vault for which to fetch
    /// @param tokenInAmt_ token in aka debt to payback, leave 0 to get max
    /// @return liquidationData_ liquidation related data. Check out structs.sol
    function getVaultLiquidation(
        address vault_,
        uint tokenInAmt_
    ) public returns (LiquidationStruct memory liquidationData_) {
        liquidationData_.vault = vault_;
        IFluidVaultT1.ConstantViews memory constants_ = _getVaultConstants(vault_);
        liquidationData_.tokenIn = constants_.borrowToken;
        liquidationData_.tokenOut = constants_.supplyToken;

        uint amtOut_;
        uint amtIn_;

        tokenInAmt_ = tokenInAmt_ == 0 ? X128 : tokenInAmt_;
        // running without absorb
        try IFluidVaultT1(vault_).liquidate(tokenInAmt_, 0, 0x000000000000000000000000000000000000dEaD, false) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidVaultT1.FluidLiquidateResult.selector) {
                    assembly {
                        amtOut_ := mload(add(lowLevelData_, 36))
                        amtIn_ := mload(add(lowLevelData_, 68))
                    }
                    liquidationData_.tokenOutAmtOne = amtOut_;
                    liquidationData_.tokenInAmtOne = amtIn_;
                } else {
                    // tokenInAmtOne & tokenOutAmtOne remains 0
                }
            }
        }

        // running with absorb
        try IFluidVaultT1(vault_).liquidate(tokenInAmt_, 0, 0x000000000000000000000000000000000000dEaD, true) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidVaultT1.FluidLiquidateResult.selector) {
                    assembly {
                        amtOut_ := mload(add(lowLevelData_, 36))
                        amtIn_ := mload(add(lowLevelData_, 68))
                    }
                    liquidationData_.tokenOutAmtTwo = amtOut_;
                    liquidationData_.tokenInAmtTwo = amtIn_;
                } else {
                    // tokenInAmtTwo & tokenOutAmtTwo remains 0
                }
            }
        }
    }

    function getMultipleVaultsLiquidation(
        address[] memory vaults_,
        uint[] memory tokensInAmt_
    ) external returns (LiquidationStruct[] memory liquidationsData_) {
        uint length_ = vaults_.length;
        liquidationsData_ = new LiquidationStruct[](length_);
        for (uint i = 0; i < length_; i++) {
            liquidationsData_[i] = getVaultLiquidation(vaults_[i], tokensInAmt_[i]);
        }
    }

    function getAllVaultsLiquidation() external returns (LiquidationStruct[] memory liquidationsData_) {
        address[] memory vaults_ = getAllVaultsAddresses();
        uint length_ = vaults_.length;

        liquidationsData_ = new LiquidationStruct[](length_);
        for (uint i = 0; i < length_; i++) {
            liquidationsData_[i] = getVaultLiquidation(vaults_[i], 0);
        }
    }

    function getVaultAbsorb(address vault_) public returns (AbsorbStruct memory absorbData_) {
        absorbData_.vault = vault_;
        uint absorbedLiquidity_ = getAbsorbedLiquidityRaw(vault_);
        try IFluidVaultT1(vault_).absorb() {
            // Handle successful execution
            uint newAbsorbedLiquidity_ = getAbsorbedLiquidityRaw(vault_);
            if (newAbsorbedLiquidity_ != absorbedLiquidity_) {
                absorbData_.absorbAvailable = true;
            }
        } catch Error(string memory) {} catch (bytes memory) {}
    }

    function getVaultsAbsorb(address[] memory vaults_) public returns (AbsorbStruct[] memory absorbData_) {
        uint length_ = vaults_.length;
        absorbData_ = new AbsorbStruct[](length_);
        for (uint i = 0; i < length_; i++) {
            absorbData_[i] = getVaultAbsorb(vaults_[i]);
        }
    }

    function getVaultsAbsorb() public returns (AbsorbStruct[] memory absorbData_) {
        return getVaultsAbsorb(getAllVaultsAddresses());
    }
}
