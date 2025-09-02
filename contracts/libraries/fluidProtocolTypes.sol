// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

interface IFluidProtocol {
    function TYPE() external view returns (uint256);
}

/// @notice implements helper methods to filter Fluid protocols by a certain type
library FluidProtocolTypes {
    uint256 internal constant VAULT_T1_TYPE = 10000; // VaultT1 borrow protocol type vaults
    uint256 internal constant VAULT_T2_SMART_COL_TYPE = 20000; // DEX protocol type vault
    uint256 internal constant VAULT_T3_SMART_DEBT_TYPE = 30000; // DEX protocol type vault
    uint256 internal constant VAULT_T4_SMART_COL_SMART_DEBT_TYPE = 40000; // DEX protocol type vault

    /// @dev filters input `addresses_` by protocol `type_`. Input addresses must be actual Fluid protocols, otherwise
    ///      they would be wrongly assumed to be VaultT1 even if they are not Fluid VaultT1 smart contracts.
    ///      `type_` must be a listed constant type of this library.
    ///      Example usage is to filter all vault addresses at the Vault factory by a certain type, e.g. to not include
    ///      DEX protocol type vaults.
    function filterBy(address[] memory addresses_, uint256 type_) internal view returns (address[] memory filtered_) {
        uint256 curType_;
        uint256 filteredProtocols_ = addresses_.length;
        for (uint256 i; i < addresses_.length; ) {
            try IFluidProtocol(addresses_[i]).TYPE() returns (uint256 protocolType_) {
                curType_ = protocolType_;
            } catch {
                curType_ = VAULT_T1_TYPE;
            }

            if (curType_ != type_) {
                addresses_[i] = address(0);
                --filteredProtocols_;
            }

            unchecked {
                ++i;
            }
        }

        filtered_ = new address[](filteredProtocols_);
        uint256 index_;
        unchecked {
            for (uint256 i; i < addresses_.length; ) {
                if (addresses_[i] != address(0)) {
                    filtered_[index_] = addresses_[i];
                    ++index_;
                }
                ++i;
            }
        }
    }
}
