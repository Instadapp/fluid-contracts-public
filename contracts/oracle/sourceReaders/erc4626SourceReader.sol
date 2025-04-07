// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

abstract contract ERC4626SourceReader {
    function _readERC4626Source(address feed_) internal view returns (uint256 rate_) {
        try IERC4626(feed_).convertToAssets(10 ** OracleUtils.RATE_OUTPUT_DECIMALS) returns (uint256 exchangeRate_) {
            // Return the price in `OracleUtils.RATE_OUTPUT_DECIMALS`
            return exchangeRate_;
        } catch {}
    }
}
