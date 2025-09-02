// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";
import { ChainlinkSourceReader } from "../sourceReaders/chainlinkSourceReader.sol";
import { FluidSourceReader } from "../sourceReaders/fluidSourceReader.sol";
import { FluidDebtSourceReader } from "../sourceReaders/fluidDebtSourceReader.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

abstract contract GenericOracleStructs {
    enum SourceType {
        Fluid, // 0, e.g. FluidCappedRate col asset side or some other IFluidOracle
        Redstone, // 1
        Chainlink, // 2
        UniV3Checked, // 3
        FluidDebt // 4 FluidCappedRate debt asset side methods
        // DO NOT add a rate source like ERC4626 here, any external contract source should ALWAYS be filtered through a FluidCappedRate contract
    }

    struct OracleHopSource {
        address source;
        bool invertRate;
        uint256 multiplier;
        uint256 divisor;
        SourceType sourceType; // e.g. FLUID, REDSTONE, UNIV3CHECKED, CHAINLINK
    }
}

/// @notice generic configurable Oracle Base
/// combines up to 4 hops from sources such as
///  - an existing IFluidOracle (e.g. ContractRate)
///  - Redstone
///  - Chainlink
abstract contract FluidGenericOracleBase is
    OracleError,
    GenericOracleStructs,
    ChainlinkSourceReader,
    FluidSourceReader,
    FluidDebtSourceReader
{
    address internal immutable _SOURCE1;
    bool internal immutable _SOURCE1_INVERT;
    uint256 internal immutable _SOURCE1_MULTIPLIER;
    uint256 internal immutable _SOURCE1_DIVISOR;
    SourceType internal immutable _SOURCE1_TYPE;

    address internal immutable _SOURCE2;
    bool internal immutable _SOURCE2_INVERT;
    uint256 internal immutable _SOURCE2_MULTIPLIER;
    uint256 internal immutable _SOURCE2_DIVISOR;
    SourceType internal immutable _SOURCE2_TYPE;

    address internal immutable _SOURCE3;
    bool internal immutable _SOURCE3_INVERT;
    uint256 internal immutable _SOURCE3_MULTIPLIER;
    uint256 internal immutable _SOURCE3_DIVISOR;
    SourceType internal immutable _SOURCE3_TYPE;

    address internal immutable _SOURCE4;
    bool internal immutable _SOURCE4_INVERT;
    uint256 internal immutable _SOURCE4_MULTIPLIER;
    uint256 internal immutable _SOURCE4_DIVISOR;
    SourceType internal immutable _SOURCE4_TYPE;

    address internal immutable _SOURCE5;
    bool internal immutable _SOURCE5_INVERT;
    uint256 internal immutable _SOURCE5_MULTIPLIER;
    uint256 internal immutable _SOURCE5_DIVISOR;
    SourceType internal immutable _SOURCE5_TYPE;

    constructor(OracleHopSource[] memory sources_) {
        if (sources_.length == 0 || sources_.length > 5) {
            revert FluidOracleError(ErrorTypes.GenericOracle__InvalidParams);
        }

        _verifyOracleHopSource(sources_[0]);
        _SOURCE1 = sources_[0].source;
        _SOURCE1_INVERT = sources_[0].invertRate;
        _SOURCE1_MULTIPLIER = sources_[0].multiplier;
        _SOURCE1_DIVISOR = sources_[0].divisor;
        _SOURCE1_TYPE = sources_[0].sourceType;

        if (sources_.length > 1) {
            _verifyOracleHopSource(sources_[1]);
            _SOURCE2 = sources_[1].source;
            _SOURCE2_INVERT = sources_[1].invertRate;
            _SOURCE2_MULTIPLIER = sources_[1].multiplier;
            _SOURCE2_DIVISOR = sources_[1].divisor;
            _SOURCE2_TYPE = sources_[1].sourceType;
        }

        if (sources_.length > 2) {
            _verifyOracleHopSource(sources_[2]);
            _SOURCE3 = sources_[2].source;
            _SOURCE3_INVERT = sources_[2].invertRate;
            _SOURCE3_MULTIPLIER = sources_[2].multiplier;
            _SOURCE3_DIVISOR = sources_[2].divisor;
            _SOURCE3_TYPE = sources_[2].sourceType;
        }

        if (sources_.length > 3) {
            _verifyOracleHopSource(sources_[3]);
            _SOURCE4 = sources_[3].source;
            _SOURCE4_INVERT = sources_[3].invertRate;
            _SOURCE4_MULTIPLIER = sources_[3].multiplier;
            _SOURCE4_DIVISOR = sources_[3].divisor;
            _SOURCE4_TYPE = sources_[3].sourceType;
        }

        if (sources_.length > 4) {
            _verifyOracleHopSource(sources_[4]);
            _SOURCE5 = sources_[4].source;
            _SOURCE5_INVERT = sources_[4].invertRate;
            _SOURCE5_MULTIPLIER = sources_[4].multiplier;
            _SOURCE5_DIVISOR = sources_[4].divisor;
            _SOURCE5_TYPE = sources_[4].sourceType;
        }
    }

    /// @dev verifies a hop source config
    function _verifyOracleHopSource(OracleHopSource memory source_) internal view virtual {
        if (
            address(source_.source) == address(0) ||
            source_.sourceType == SourceType.UniV3Checked ||
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
    ) internal view virtual returns (uint256 rate_) {
        if (sourceType_ == SourceType.Redstone || sourceType_ == SourceType.Chainlink) {
            rate_ = _readChainlinkSource(source_);
        } else if (sourceType_ == SourceType.Fluid) {
            rate_ = _readFluidSource(source_, isOperate_);
        } else if (sourceType_ == SourceType.FluidDebt) {
            rate_ = _readFluidDebtSource(source_, isOperate_);
        } else {
            // should never happen because of config checks in constructor
            revert FluidOracleError(ErrorTypes.GenericOracle__UnexpectedConfig);
        }
    }

    /// @dev gets the exchange rate for a single configured hop
    function _getExchangeRateForHop(
        uint256 curHopsRate_,
        bool isOperate_,
        OracleHopSource memory source_
    ) internal view virtual returns (uint256 rate_) {
        rate_ = _readSource(source_.source, source_.sourceType, isOperate_);

        // scale to 1e27
        rate_ = (rate_ * source_.multiplier) / source_.divisor;

        if (source_.invertRate && rate_ > 0) {
            rate_ = (10 ** (OracleUtils.RATE_OUTPUT_DECIMALS * 2)) / uint256(rate_);
        }

        rate_ = (curHopsRate_ * rate_) / (10 ** OracleUtils.RATE_OUTPUT_DECIMALS); // combine with current hops rate
    }

    /// @dev gets the exchange rate combined for all configured hops
    function _getHopsExchangeRate(bool isOperate_) internal view returns (uint256 rate_) {
        rate_ = _getExchangeRateForHop(
            (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
            isOperate_,
            OracleHopSource(_SOURCE1, _SOURCE1_INVERT, _SOURCE1_MULTIPLIER, _SOURCE1_DIVISOR, _SOURCE1_TYPE)
        );
        if (rate_ == 0) {
            revert FluidOracleError(ErrorTypes.GenericOracle__RateZero);
        }
        if (address(_SOURCE2) == address(0) && _SOURCE2_TYPE != SourceType.UniV3Checked) {
            return rate_;
        }

        // 2 hops -> return rate of hop 1 combined with hop 2
        rate_ = _getExchangeRateForHop(
            rate_,
            isOperate_,
            OracleHopSource(_SOURCE2, _SOURCE2_INVERT, _SOURCE2_MULTIPLIER, _SOURCE2_DIVISOR, _SOURCE2_TYPE)
        );
        if (rate_ == 0) {
            revert FluidOracleError(ErrorTypes.GenericOracle__RateZero);
        }
        if (address(_SOURCE3) == address(0) && _SOURCE3_TYPE != SourceType.UniV3Checked) {
            return rate_;
        }

        // 3 hops -> return rate of hop 1 combined with hop 2 & hop 3
        rate_ = _getExchangeRateForHop(
            rate_,
            isOperate_,
            OracleHopSource(_SOURCE3, _SOURCE3_INVERT, _SOURCE3_MULTIPLIER, _SOURCE3_DIVISOR, _SOURCE3_TYPE)
        );
        if (rate_ == 0) {
            revert FluidOracleError(ErrorTypes.GenericOracle__RateZero);
        }
        if (address(_SOURCE4) == address(0) && _SOURCE4_TYPE != SourceType.UniV3Checked) {
            return rate_;
        }

        // 4 hops -> return rate of hop 1 combined with hop 2, hop 3 & hop 4
        rate_ = _getExchangeRateForHop(
            rate_,
            isOperate_,
            OracleHopSource(_SOURCE4, _SOURCE4_INVERT, _SOURCE4_MULTIPLIER, _SOURCE4_DIVISOR, _SOURCE4_TYPE)
        );
        if (rate_ == 0) {
            revert FluidOracleError(ErrorTypes.GenericOracle__RateZero);
        }
        if (address(_SOURCE5) == address(0) && _SOURCE5_TYPE != SourceType.UniV3Checked) {
            return rate_;
        }

        // 5 hops -> return rate of hop 1 combined with hop 2, hop 3, hop 4 & hop 5
        rate_ = _getExchangeRateForHop(
            rate_,
            isOperate_,
            OracleHopSource(_SOURCE5, _SOURCE5_INVERT, _SOURCE5_MULTIPLIER, _SOURCE5_DIVISOR, _SOURCE5_TYPE)
        );
        if (rate_ == 0) {
            revert FluidOracleError(ErrorTypes.GenericOracle__RateZero);
        }
    }

    /// @notice Returns the exchange rate for each hop.
    /// @return rateSource1Operate_ The exchange rate for hop 1 during operate.
    /// @return rateSource1Liquidate_ The exchange rate for hop 1 during liquidate.
    /// @return rateSource2Operate_ The exchange rate for hop 2 during operate.
    /// @return rateSource2Liquidate_ The exchange rate for hop 2 during liquidate.
    /// @return rateSource3Operate_ The exchange rate for hop 3 during operate.
    /// @return rateSource3Liquidate_ The exchange rate for hop 3 during liquidate.
    /// @return rateSource4Operate_ The exchange rate for hop 4 during operate.
    /// @return rateSource4Liquidate_ The exchange rate for hop 4 during liquidate.
    /// @return rateSource5Operate_ The exchange rate for hop 5 during operate.
    /// @return rateSource5Liquidate_ The exchange rate for hop 5 during liquidate.
    function getHopExchangeRates()
        public
        view
        returns (
            uint256 rateSource1Operate_,
            uint256 rateSource1Liquidate_,
            uint256 rateSource2Operate_,
            uint256 rateSource2Liquidate_,
            uint256 rateSource3Operate_,
            uint256 rateSource3Liquidate_,
            uint256 rateSource4Operate_,
            uint256 rateSource4Liquidate_,
            uint256 rateSource5Operate_,
            uint256 rateSource5Liquidate_
        )
    {
        rateSource1Operate_ = _getExchangeRateForHop(
            (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
            true,
            OracleHopSource(_SOURCE1, _SOURCE1_INVERT, _SOURCE1_MULTIPLIER, _SOURCE1_DIVISOR, _SOURCE1_TYPE)
        );
        rateSource1Liquidate_ = _getExchangeRateForHop(
            (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
            false,
            OracleHopSource(_SOURCE1, _SOURCE1_INVERT, _SOURCE1_MULTIPLIER, _SOURCE1_DIVISOR, _SOURCE1_TYPE)
        );

        if (address(_SOURCE2) != address(0) || _SOURCE2_TYPE == SourceType.UniV3Checked) {
            rateSource2Operate_ = _getExchangeRateForHop(
                (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
                true,
                OracleHopSource(_SOURCE2, _SOURCE2_INVERT, _SOURCE2_MULTIPLIER, _SOURCE2_DIVISOR, _SOURCE2_TYPE)
            );
            rateSource2Liquidate_ = _getExchangeRateForHop(
                (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
                false,
                OracleHopSource(_SOURCE2, _SOURCE2_INVERT, _SOURCE2_MULTIPLIER, _SOURCE2_DIVISOR, _SOURCE2_TYPE)
            );
        }

        if (address(_SOURCE3) != address(0) || _SOURCE3_TYPE == SourceType.UniV3Checked) {
            rateSource3Operate_ = _getExchangeRateForHop(
                (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
                true,
                OracleHopSource(_SOURCE3, _SOURCE3_INVERT, _SOURCE3_MULTIPLIER, _SOURCE3_DIVISOR, _SOURCE3_TYPE)
            );
            rateSource3Liquidate_ = _getExchangeRateForHop(
                (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
                false,
                OracleHopSource(_SOURCE3, _SOURCE3_INVERT, _SOURCE3_MULTIPLIER, _SOURCE3_DIVISOR, _SOURCE3_TYPE)
            );
        }

        if (address(_SOURCE4) != address(0) || _SOURCE4_TYPE == SourceType.UniV3Checked) {
            rateSource4Operate_ = _getExchangeRateForHop(
                (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
                true,
                OracleHopSource(_SOURCE4, _SOURCE4_INVERT, _SOURCE4_MULTIPLIER, _SOURCE4_DIVISOR, _SOURCE4_TYPE)
            );
            rateSource4Liquidate_ = _getExchangeRateForHop(
                (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
                false,
                OracleHopSource(_SOURCE4, _SOURCE4_INVERT, _SOURCE4_MULTIPLIER, _SOURCE4_DIVISOR, _SOURCE4_TYPE)
            );
        }

        if (address(_SOURCE5) != address(0) || _SOURCE5_TYPE == SourceType.UniV3Checked) {
            rateSource5Operate_ = _getExchangeRateForHop(
                (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
                true,
                OracleHopSource(_SOURCE5, _SOURCE5_INVERT, _SOURCE5_MULTIPLIER, _SOURCE5_DIVISOR, _SOURCE5_TYPE)
            );
            rateSource5Liquidate_ = _getExchangeRateForHop(
                (10 ** OracleUtils.RATE_OUTPUT_DECIMALS),
                false,
                OracleHopSource(_SOURCE5, _SOURCE5_INVERT, _SOURCE5_MULTIPLIER, _SOURCE5_DIVISOR, _SOURCE5_TYPE)
            );
        }
    }

    /// @notice Returns the configured OracleHopSources
    function getOracleHopSources() public view returns (OracleHopSource[] memory sources_) {
        sources_ = new OracleHopSource[](5);
        sources_[0] = OracleHopSource(_SOURCE1, _SOURCE1_INVERT, _SOURCE1_MULTIPLIER, _SOURCE1_DIVISOR, _SOURCE1_TYPE);
        sources_[1] = OracleHopSource(_SOURCE2, _SOURCE2_INVERT, _SOURCE2_MULTIPLIER, _SOURCE2_DIVISOR, _SOURCE2_TYPE);
        sources_[2] = OracleHopSource(_SOURCE3, _SOURCE3_INVERT, _SOURCE3_MULTIPLIER, _SOURCE3_DIVISOR, _SOURCE3_TYPE);
        sources_[3] = OracleHopSource(_SOURCE4, _SOURCE4_INVERT, _SOURCE4_MULTIPLIER, _SOURCE4_DIVISOR, _SOURCE4_TYPE);
        sources_[4] = OracleHopSource(_SOURCE5, _SOURCE5_INVERT, _SOURCE5_MULTIPLIER, _SOURCE5_DIVISOR, _SOURCE5_TYPE);
    }
}
