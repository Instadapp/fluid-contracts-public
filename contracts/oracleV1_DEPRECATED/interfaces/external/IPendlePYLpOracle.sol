// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IPendlePYLpOracle {
    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256);

    function getYtToAssetRate(address market, uint32 duration) external view returns (uint256);

    function getLpToAssetRate(address market, uint32 duration) external view returns (uint256);

    function getPtToSyRate(address market, uint32 duration) external view returns (uint256);

    function getYtToSyRate(address market, uint32 duration) external view returns (uint256);

    function getLpToSyRate(address market, uint32 duration) external view returns (uint256);

    function getOracleState(
        address market,
        uint32 duration
    )
        external
        view
        returns (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied);
}
