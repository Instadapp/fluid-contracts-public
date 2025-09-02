// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../errorTypes.sol";
import { FluidOracle } from "../fluidOracle.sol";
import { FluidGenericOracleBase } from "./genericOracleBase.sol";
import { UniV3CheckedSourceReader } from "../sourceReaders/uniV3CheckedSourceReader.sol";

/// @notice generic configurable Oracle
/// combines up to 4 hops from sources such as
///  - an existing IFluidOracle (e.g. ContractRate)
///  - Redstone
///  - Chainlink
///  - UniV3 checked against Chainlink
contract FluidGenericUniV3CheckedOracle is FluidGenericOracleBase, UniV3CheckedSourceReader {
    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        OracleHopSource[] memory sources_,
        UniV3CheckCLRSConstructorParams memory uniV3Params_
    ) FluidGenericOracleBase(sources_) UniV3CheckedSourceReader(infoName_, targetDecimals_, uniV3Params_) {
        uint256 uniV3SourcesCount_;
        if (sources_[0].sourceType == SourceType.UniV3Checked) uniV3SourcesCount_++;
        if (sources_.length > 1 && sources_[1].sourceType == SourceType.UniV3Checked) uniV3SourcesCount_++;
        if (sources_.length > 2 && sources_[2].sourceType == SourceType.UniV3Checked) uniV3SourcesCount_++;
        if (sources_.length > 3 && sources_[3].sourceType == SourceType.UniV3Checked) uniV3SourcesCount_++;
        if (sources_.length > 4 && sources_[4].sourceType == SourceType.UniV3Checked) uniV3SourcesCount_++;

        if (uniV3SourcesCount_ != 1) {
            revert FluidOracleError(ErrorTypes.GenericOracle__InvalidParams);
        }
    }

    /// @dev verifies a hop source config
    function _verifyOracleHopSource(OracleHopSource memory source_) internal view virtual override {
        if (
            (source_.sourceType != SourceType.UniV3Checked && address(source_.source) == address(0)) ||
            source_.divisor == 0 ||
            source_.multiplier == 0 ||
            source_.divisor > 1e40 ||
            source_.multiplier > 1e40
        ) {
            revert FluidOracleError(ErrorTypes.GenericOracle__InvalidParams);
        }
    }

    /// @dev reads the exchange rate for a hop source
    function _readSource(
        address source_,
        SourceType sourceType_,
        bool isOperate_
    ) internal view virtual override returns (uint256 rate_) {
        if (sourceType_ == SourceType.Redstone || sourceType_ == SourceType.Chainlink) {
            rate_ = _readChainlinkSource(source_);
        } else if (sourceType_ == SourceType.Fluid) {
            rate_ = _readFluidSource(source_, isOperate_);
        } else if (sourceType_ == SourceType.UniV3Checked) {
            rate_ = _readUniV3CheckedSource(isOperate_);
        } else {
            // should never happen because of config checks in constructor
            revert FluidOracleError(ErrorTypes.GenericOracle__UnexpectedConfig);
        }
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(true);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(false);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(false);
    }
}
