// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

/// @notice implements calculation of address for contracts deployed through CREATE.
/// Accepts contract deployed from which address & nonce
library AddressCalcs {

    /// @notice                         Computes the address of a contract based
    /// @param deployedFrom_            Address from which the contract was deployed
    /// @param nonce_                   Nonce at which the contract was deployed
    /// @return contract_               Address of deployed contract
    function addressCalc(address deployedFrom_, uint nonce_) internal pure returns (address contract_) {
        // @dev based on https://ethereum.stackexchange.com/a/61413

        // nonce of smart contract always starts with 1. so, with nonce 0 there won't be any deployment
        // hence, nonce of vault deployment starts with 1.
        bytes memory data;
        if (nonce_ == 0x00) {
            return address(0);
        } else if (nonce_ <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployedFrom_, uint8(nonce_));
        } else if (nonce_ <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), deployedFrom_, bytes1(0x81), uint8(nonce_));
        } else if (nonce_ <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), deployedFrom_, bytes1(0x82), uint16(nonce_));
        } else if (nonce_ <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), deployedFrom_, bytes1(0x83), uint24(nonce_));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), deployedFrom_, bytes1(0x84), uint32(nonce_));
        }

        return address(uint160(uint256(keccak256(data))));
    }

}