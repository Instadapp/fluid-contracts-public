// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FluidDexResolver } from "../dex/main.sol";
import { FluidSmartLendingFactory } from "../../../protocols/dex/smartLending/factory/main.sol";
import { FluidSmartLending } from "../../../protocols/dex/smartLending/main.sol";
import { Structs } from "./structs.sol";
import { Structs as DexResolverStructs } from "../dex/structs.sol";

/// @notice Fluid Smart Lending resolver
/// Implements various view-only methods to give easy access to Smart Lending protocol data.
contract FluidSmartLendingResolver is Structs {
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    FluidDexResolver public immutable DEX_RESOLVER;

    FluidSmartLendingFactory public immutable SMART_LENDING_FACTORY;

    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice thrown if an input param address is zero
    error FluidSmartLendingResolver__AddressZero();

    constructor(FluidDexResolver dexResolver_, FluidSmartLendingFactory smartLendingFactory_) {
        if (address(dexResolver_) == address(0) || address(smartLendingFactory_) == address(0)) {
            revert FluidSmartLendingResolver__AddressZero();
        }

        DEX_RESOLVER = dexResolver_;
        SMART_LENDING_FACTORY = smartLendingFactory_;
    }

    /// @notice List of all existing SmartLending tokens
    function getAllSmartLendingAddresses() public view returns (address[] memory) {
        return SMART_LENDING_FACTORY.allTokens();
    }

    /// @notice Get the address of a SmartLending for a certain dexId. address zero if no SmartLending exists for the dex.
    function getSmartLendingAddress(uint dexId_) public view returns (address smartLending) {
        return SMART_LENDING_FACTORY.getSmartLendingAddress(dexId_);
    }

    /// @notice Get the entire data for a SmartLending, EXCEPT underlying DexEntireData. use write method for that.
    /// @param smartLending_ The address of the SmartLending
    /// @return data_ A struct containing all the data for the SmartLending
    function getSmartLendingEntireViewData(
        address payable smartLending_
    ) public view returns (SmartLendingEntireData memory data_) {
        data_.smartLending = smartLending_;
        data_.name = FluidSmartLending(smartLending_).name();
        data_.symbol = FluidSmartLending(smartLending_).symbol();
        data_.decimals = 18;
        data_.totalSupply = uint256(FluidSmartLending(smartLending_).totalSupply());

        data_.token0 = FluidSmartLending(smartLending_).TOKEN0();
        data_.token1 = FluidSmartLending(smartLending_).TOKEN1();
        data_.dex = address(FluidSmartLending(smartLending_).DEX());

        data_.lastTimestamp = uint256(FluidSmartLending(smartLending_).lastTimestamp());
        data_.feeOrReward = int256(FluidSmartLending(smartLending_).feeOrReward());
        (data_.exchangePrice, ) = FluidSmartLending(smartLending_).getUpdateExchangePrice();
        // exchangePrice is in 1e18, shares are in 1e18, SmartLending is in 1e18
        data_.assetsPerShare = (1e18 * 1e18) / data_.exchangePrice;
        data_.sharesPerAsset = data_.exchangePrice; // just providing same value for extra clarity. would be 1e18 * exchangePrice / 1e18

        data_.totalUnderlyingShares = (data_.totalSupply * data_.exchangePrice) / 1e18;

        data_.rebalancer = FluidSmartLending(smartLending_).rebalancer();
        data_.rebalanceDiff = uint256(FluidSmartLending(smartLending_).rebalanceDiff());

        data_.dexUserSupplyData = DEX_RESOLVER.getUserSupplyData(data_.dex, smartLending_);
    }

    /// @notice Get the entire view data for multiple SmartLendings, EXCEPT underlying DexEntireData. use write method for that.
    /// @param smartLendings_ An array of SmartLending addresses
    /// @return datas_ An array of structs containing all the data for each SmartLending
    function getSmartLendingEntireViewDatas(
        address[] memory smartLendings_
    ) public view returns (SmartLendingEntireData[] memory datas_) {
        uint256 length_ = smartLendings_.length;
        datas_ = new SmartLendingEntireData[](length_);

        for (uint256 i; i < length_; i++) {
            datas_[i] = getSmartLendingEntireViewData(payable(smartLendings_[i]));
        }
    }

    /// @notice Get the entire data for all SmartLendings, EXCEPT underlying DexEntireData. use write method for that.
    /// @return datas_ An array of structs containing all the data for all SmartLendings
    function getAllSmartLendingEntireViewDatas() public view returns (SmartLendingEntireData[] memory datas_) {
        return getSmartLendingEntireViewDatas(getAllSmartLendingAddresses());
    }

    /// @notice Get the entire data for a SmartLending, incl. underlying DexEntireData and totalUnderlyingAssets for each token
    /// @param smartLending_ The address of the SmartLending
    /// @return data_ A struct containing all the data for the SmartLending
    /// @dev expected to be called via callStatic
    function getSmartLendingEntireData(
        address payable smartLending_
    ) public returns (SmartLendingEntireData memory data_) {
        data_ = getSmartLendingEntireViewData(smartLending_);

        data_.dexEntireData = DEX_RESOLVER.getDexEntireData(data_.dex);

        data_.totalUnderlyingAssetsToken0 =
            (data_.totalUnderlyingShares * data_.dexEntireData.dexState.token0PerSupplyShare) /
            1e18;
        data_.totalUnderlyingAssetsToken1 =
            (data_.totalUnderlyingShares * data_.dexEntireData.dexState.token1PerSupplyShare) /
            1e18;
    }

    /// @notice Get the entire data for multiple SmartLendings
    /// @param smartLendings_ An array of SmartLending addresses
    /// @return datas_ An array of structs containing all the data for each SmartLending
    /// @dev expected to be called via callStatic
    function getSmartLendingEntireDatas(
        address[] memory smartLendings_
    ) public returns (SmartLendingEntireData[] memory datas_) {
        uint256 length_ = smartLendings_.length;
        datas_ = new SmartLendingEntireData[](length_);

        for (uint256 i; i < length_; i++) {
            datas_[i] = getSmartLendingEntireData(payable(smartLendings_[i]));
        }
    }

    /// @notice Get the entire data for all SmartLendings
    /// @return datas_ An array of structs containing all the data for all SmartLendings
    /// @dev expected to be called via callStatic
    function getAllSmartLendingEntireDatas() public returns (SmartLendingEntireData[] memory datas_) {
        return getSmartLendingEntireDatas(getAllSmartLendingAddresses());
    }

    /// @notice gets a user position at a certain SmartLending. EXCLUDING underlyingAssetsToken0 and underlyingAssetsToken1.
    ///          use write method for that.
    function getUserPositionView(
        address payable smartLending_,
        address user_
    ) public view returns (UserPosition memory userPosition_) {
        userPosition_.user = user_;
        userPosition_.smartLendingAssets = FluidSmartLending(payable(smartLending_)).balanceOf(user_);

        {
            (uint256 exchangePrice_, ) = FluidSmartLending(smartLending_).getUpdateExchangePrice();
            userPosition_.underlyingShares = (userPosition_.smartLendingAssets * exchangePrice_) / 1e18;
        }

        {
            IERC20 token0_ = IERC20(FluidSmartLending(smartLending_).TOKEN0());
            IERC20 token1_ = IERC20(FluidSmartLending(smartLending_).TOKEN1());

            if (address(token0_) == _NATIVE_TOKEN_ADDRESS) {
                userPosition_.underlyingBalanceToken0 = address(user_).balance;
            } else {
                userPosition_.underlyingBalanceToken0 = token0_.balanceOf(user_);
                userPosition_.allowanceToken0 = token0_.allowance(user_, address(smartLending_));
            }

            if (address(token1_) == _NATIVE_TOKEN_ADDRESS) {
                userPosition_.underlyingBalanceToken1 = address(user_).balance;
            } else {
                userPosition_.underlyingBalanceToken1 = token1_.balanceOf(user_);
                userPosition_.allowanceToken1 = token1_.allowance(user_, address(smartLending_));
            }
        }
    }

    /// @notice gets a user position at a certain SmartLending incl. underlyingAssetsToken0 and underlyingAssetsToken1
    /// @dev expected to be called via callStatic
    function getUserPosition(
        address payable smartLending_,
        address user_
    ) public returns (UserPosition memory userPosition_) {
        userPosition_ = getUserPositionView(smartLending_, user_);

        {
            DexResolverStructs.DexState memory dexState_ = DEX_RESOLVER.getDexState(
                address(FluidSmartLending(smartLending_).DEX())
            );

            userPosition_.underlyingAssetsToken0 =
                (userPosition_.underlyingShares * dexState_.token0PerSupplyShare) /
                1e18;
            userPosition_.underlyingAssetsToken1 =
                (userPosition_.underlyingShares * dexState_.token1PerSupplyShare) /
                1e18;
        }
    }

    /// @notice gets all Smart lendings entire data and all user positions for each.
    ///         Excluding underlying DexEntireData and underlyingAssetsToken0 and underlyingAssetsToken1. use write method for that.
    function getUserPositionsView(address user_) external view returns (SmartLendingEntireDataUserPosition[] memory) {
        SmartLendingEntireData[] memory smartLendingsEntireData_ = getAllSmartLendingEntireViewDatas();
        SmartLendingEntireDataUserPosition[] memory userPositionArr_ = new SmartLendingEntireDataUserPosition[](
            smartLendingsEntireData_.length
        );
        for (uint256 i = 0; i < smartLendingsEntireData_.length; ) {
            userPositionArr_[i].smartLendingEntireData = smartLendingsEntireData_[i];
            userPositionArr_[i].userPosition = getUserPositionView(
                payable(smartLendingsEntireData_[i].smartLending),
                user_
            );
            unchecked {
                i++;
            }
        }
        return userPositionArr_;
    }

    /// @notice gets all Smart lendings entire data and all user positions for each.
    ///         incl. underlying Dex (=`getSmartLendingEntireViewData()` + DexEntireData) and underlyingAssetsToken0 and underlyingAssetsToken1.
    /// @dev expected to be called via callStatic
    function getUserPositions(address user_) external returns (SmartLendingEntireDataUserPosition[] memory) {
        SmartLendingEntireData[] memory smartLendingsEntireData_ = getAllSmartLendingEntireDatas();
        SmartLendingEntireDataUserPosition[] memory userPositionArr_ = new SmartLendingEntireDataUserPosition[](
            smartLendingsEntireData_.length
        );
        for (uint256 i = 0; i < smartLendingsEntireData_.length; ) {
            userPositionArr_[i].smartLendingEntireData = smartLendingsEntireData_[i];
            userPositionArr_[i].userPosition = getUserPosition(
                payable(smartLendingsEntireData_[i].smartLending),
                user_
            );
            unchecked {
                i++;
            }
        }
        return userPositionArr_;
    }
}
