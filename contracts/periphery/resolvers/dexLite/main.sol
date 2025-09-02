// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./helpers.sol";

contract FluidDexLiteResolver is Helpers {
    constructor(address dexLite_, address liquidity_, address deployerContract_) {
        DEX_LITE = IDexLite(dexLite_);
        LIQUIDITY = liquidity_;
        DEPLOYER_CONTRACT = deployerContract_;
    }

    function getAllDexes() public view returns (DexKey[] memory) {
        uint256 totalDexes = uint256(DEX_LITE.readFromStorage(bytes32(DSL.DEX_LITE_DEXES_LIST_SLOT)));
        DexKey[] memory dexes = new DexKey[](totalDexes);
        for (uint256 i = 0; i < totalDexes; i++) {
            dexes[i] = _readDexKeyAtIndex(i);
        }
        return dexes;
    }

    function getDexState(DexKey memory dexKey) public view returns (DexState memory) {
        bytes8 dexId_ = _calculateDexId(dexKey);
        (
            uint256 dexVariables_,
            uint256 centerPriceShift_,
            uint256 rangeShift_,
            uint256 thresholdShift_
        ) = _readPoolState(dexId_);

        return
            DexState(
                _unpackDexVariables(dexVariables_),
                _unpackCenterPriceShift(centerPriceShift_),
                _unpackRangeShift(rangeShift_),
                _unpackThresholdShift(thresholdShift_)
            );
    }

    function getPricesAndReserves(
        DexKey memory dexKey
    ) public returns (Prices memory prices_, Reserves memory reserves_) {
        bytes8 dexId_ = _calculateDexId(dexKey);
        (
            uint256 dexVariables_,
            uint256 centerPriceShift_,
            uint256 rangeShift_,
            uint256 thresholdShift_
        ) = _readPoolState(dexId_);

        uint256 token0Supply_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) & X60;
        uint256 token1Supply_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED) & X60;

        return
            _getPricesAndReserves(
                dexKey,
                dexVariables_,
                centerPriceShift_,
                rangeShift_,
                thresholdShift_,
                token0Supply_,
                token1Supply_
            );
    }

    function getDexEntireData(DexKey memory dexKey_) public returns (DexEntireData memory entireData_) {
        entireData_.dexKey = dexKey_;
        entireData_.constantViews = ConstantViews(
            LIQUIDITY,
            DEPLOYER_CONTRACT
        );
        entireData_.dexId = _calculateDexId(dexKey_);
        entireData_.dexState = getDexState(dexKey_);
        (entireData_.prices, entireData_.reserves) = getPricesAndReserves(dexKey_);
    }

    function getAllDexesEntireData() public returns (DexEntireData[] memory allDexesEntireData_) {
        DexKey[] memory dexes_ = getAllDexes();
        allDexesEntireData_ = new DexEntireData[](dexes_.length);
        for (uint256 i = 0; i < dexes_.length; i++) {
            allDexesEntireData_[i] = getDexEntireData(dexes_[i]);
        }
        return allDexesEntireData_;
    }

    function estimateSwapSingle(
        DexKey calldata dexKey_,
        bool swap0To1_,
        int256 amountSpecified_
    ) public returns (uint256 amountUnspecified_) {
        try
            DEX_LITE.swapSingle(
                dexKey_,
                swap0To1_,
                amountSpecified_,
                amountSpecified_ > 0 ? 0 : type(uint256).max,
                address(0),
                false,
                "",
                abi.encode(ESTIMATE_SWAP)
            )
        {
            // Should not reach here
            revert("Estimation Failed");
        } catch (bytes memory reason) {
            // Check if this is the EstimateSwap error
            if (reason.length >= 36) {
                bytes4 errorSelector = bytes4(reason);
                // EstimateSwap error selector should match
                if (errorSelector == bytes4(keccak256("EstimateSwap(uint256)"))) {
                    // Skip the 4-byte selector and decode the uint256 parameter
                    assembly {
                        amountUnspecified_ := mload(add(reason, 36))
                    }
                } else {
                    revert("Estimation Failed - Wrong Error");
                }
            } else {
                revert("Estimation Failed - Invalid Reason");
            }
        }
    }

    function estimateSwapHop(
        address[] calldata path_,
        DexKey[] calldata dexKeys_,
        int256 amountSpecified_
    ) public returns (uint256 amountUnspecified_) {
        uint256[] memory amountLimits_ = new uint256[](dexKeys_.length);
        if (amountSpecified_ < 0) {
            for (uint256 i = 0; i < dexKeys_.length; i++) {
                amountLimits_[i] = type(uint256).max;
            }
        }

        try
            DEX_LITE.swapHop(
                path_,
                dexKeys_,
                amountSpecified_,
                amountLimits_,
                TransferParams(address(0), false, "", abi.encode(ESTIMATE_SWAP))
            )
        {
            // Should not reach here
            revert("Estimation Failed");
        } catch (bytes memory reason) {
            // Check if this is the EstimateSwap error
            if (reason.length >= 36) {
                bytes4 errorSelector = bytes4(reason);
                // EstimateSwap error selector should match
                if (errorSelector == bytes4(keccak256("EstimateSwap(uint256)"))) {
                    // Skip the 4-byte selector and decode the uint256 parameter
                    assembly {
                        amountUnspecified_ := mload(add(reason, 36))
                    }
                } else {
                    revert("Estimation Failed - Wrong Error");
                }
            } else {
                revert("Estimation Failed - Invalid Reason");
            }
        }
    }
}
