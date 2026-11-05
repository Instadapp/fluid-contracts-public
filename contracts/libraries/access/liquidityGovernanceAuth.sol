// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

interface IFluidLiquidityGovernance {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

/// @title LiquidityGovernanceAuth
/// @notice Shared helpers for contracts gated by Fluid Liquidity Layer governance.
/// @dev Liquidity proxy is set at construction (prod, permissioned, or test). Governance is the
///      EIP-1967 admin stored on that proxy (read via `readFromStorage`).
abstract contract LiquidityGovernanceAuth {
    /// @dev Liquidity Layer proxy bound at deploy — not assumed identical across deployments.
    address public immutable LIQUIDITY;

    /// @dev EIP-1967 admin slot on Liquidity — holds the governance address.
    bytes32 internal constant _LIQUIDITY_GOVERNANCE_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    error Access__Unauthorized();

    /// @param liquidity_ Liquidity proxy whose EIP-1967 admin is governance for this contract.
    constructor(address liquidity_) {
        if (liquidity_ == address(0)) {
            revert Access__Unauthorized();
        }
        LIQUIDITY = liquidity_;
    }

    /// @dev Current Liquidity Layer governance (owner) for `LIQUIDITY`.
    function _governance() internal view returns (address) {
        return address(uint160(IFluidLiquidityGovernance(LIQUIDITY).readFromStorage(_LIQUIDITY_GOVERNANCE_SLOT)));
    }

    /// @dev Whether `msg.sender` is Liquidity Layer governance.
    function _isGovernance() internal view returns (bool) {
        return msg.sender == _governance();
    }

    /// @dev Only Liquidity Layer governance.
    modifier onlyGovernance() {
        if (!_isGovernance()) {
            revert Access__Unauthorized();
        }
        _;
    }
}
