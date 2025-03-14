// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IWeETHsAccountant {
    /**
     * @notice Get this BoringVault's current rate in the base.
     */
    function getRate() external view returns (uint256 rate);

    /**
     * @notice Get this BoringVault's current rate in the base.
     * @dev Revert if paused.
     */
    function getRateSafe() external view returns (uint256 rate);

    /**
     * @notice The BoringVault this accountant is working with.
     *         Used to determine share supply for fee calculation.
     */
    function vault() external view returns (address vault);
}
