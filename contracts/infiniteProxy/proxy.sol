// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.29;

import { Events } from "./events.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Error } from "./error.sol";
import { StorageRead } from "../libraries/storageRead.sol";

contract CoreInternals is StorageRead, Events, Error {
    struct SigsSlot {
        bytes4[] value;
    }

    /// @dev Storage slot with the admin of the contract.
    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
    /// validated in the constructor.
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev Storage slot with the address of the current dummy-implementation.
    /// This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
    /// validated in the constructor.
    bytes32 internal constant _DUMMY_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev use EIP1967 proxy slot (see _DUMMY_IMPLEMENTATION_SLOT) except for first 4 bytes,
    // which are set to 0. This is combined with a sig which will be set in those first 4 bytes
    bytes32 internal constant _SIG_SLOT_BASE = 0x000000003ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Returns the storage slot which stores the sigs array set for the implementation.
    function _getSlotImplSigsSlot(address implementation_) internal pure returns (bytes32) {
        return keccak256(abi.encode("eip1967.proxy.implementation", implementation_));
    }

    /// @dev Returns the storage slot which stores the implementation address for the function sig.
    function _getSlotSigsImplSlot(bytes4 sig_) internal pure returns (bytes32 result_) {
        assembly {
            // or operator sets sig_ in first 4 bytes with rest of bytes32 having default value of _SIG_SLOT_BASE
            result_ := or(_SIG_SLOT_BASE, sig_)
        }
    }

    /// @dev Returns an address `data_` located at `slot_`.
    function _getAddressSlot(bytes32 slot_) internal view returns (address data_) {
        assembly {
            data_ := sload(slot_)
        }
    }

    /// @dev Sets an address `data_` located at `slot_`.
    function _setAddressSlot(bytes32 slot_, address data_) internal {
        assembly {
            sstore(slot_, data_)
        }
    }

    /// @dev Returns an `SigsSlot` with member `value` located at `slot`.
    function _getSigsSlot(bytes32 slot_) internal pure returns (SigsSlot storage _r) {
        assembly {
            _r.slot := slot_
        }
    }

    /// @dev Sets new implementation and adds mapping from implementation to sigs and sig to implementation.
    function _setImplementationSigs(address implementation_, bytes4[] memory sigs_) internal {
        require(sigs_.length != 0, "no-sigs");
        bytes32 slot_ = _getSlotImplSigsSlot(implementation_);
        bytes4[] memory sigsCheck_ = _getSigsSlot(slot_).value;
        require(sigsCheck_.length == 0, "implementation-already-exist");

        for (uint256 i; i < sigs_.length; i++) {
            bytes32 sigSlot_ = _getSlotSigsImplSlot(sigs_[i]);
            require(_getAddressSlot(sigSlot_) == address(0), "sig-already-exist");
            _setAddressSlot(sigSlot_, implementation_);
        }

        _getSigsSlot(slot_).value = sigs_;
        emit LogSetImplementation(implementation_, sigs_);
    }

    /// @dev Removes implementation and the mappings corresponding to it.
    function _removeImplementationSigs(address implementation_) internal {
        bytes32 slot_ = _getSlotImplSigsSlot(implementation_);
        bytes4[] memory sigs_ = _getSigsSlot(slot_).value;
        require(sigs_.length != 0, "implementation-not-exist");

        for (uint256 i; i < sigs_.length; i++) {
            bytes32 sigSlot_ = _getSlotSigsImplSlot(sigs_[i]);
            _setAddressSlot(sigSlot_, address(0));
        }

        delete _getSigsSlot(slot_).value;
        emit LogRemoveImplementation(implementation_);
    }

    /// @dev Returns bytes4[] sigs from implementation address. If implemenatation is not registered then returns empty array.
    function _getImplementationSigs(address implementation_) internal view returns (bytes4[] memory) {
        bytes32 slot_ = _getSlotImplSigsSlot(implementation_);
        return _getSigsSlot(slot_).value;
    }

    /// @dev Returns implementation address from bytes4 sig. If sig is not registered then returns address(0).
    function _getSigImplementation(bytes4 sig_) internal view returns (address implementation_) {
        bytes32 slot_ = _getSlotSigsImplSlot(sig_);
        return _getAddressSlot(slot_);
    }

    /// @dev Returns the current admin.
    function _getAdmin() internal view returns (address) {
        return _getAddressSlot(_ADMIN_SLOT);
    }

    /// @dev Returns the current dummy-implementation.
    function _getDummyImplementation() internal view returns (address) {
        return _getAddressSlot(_DUMMY_IMPLEMENTATION_SLOT);
    }

    /// @dev Stores a new address in the EIP1967 admin slot.
    function _setAdmin(address newAdmin_) internal {
        address oldAdmin_ = _getAdmin();
        require(newAdmin_ != address(0), "ERC1967: new admin is the zero address");
        _setAddressSlot(_ADMIN_SLOT, newAdmin_);
        emit LogSetAdmin(oldAdmin_, newAdmin_);
    }

    /// @dev Stores a new address in the EIP1967 implementation slot.
    function _setDummyImplementation(address newDummyImplementation_) internal {
        address oldDummyImplementation_ = _getDummyImplementation();
        _setAddressSlot(_DUMMY_IMPLEMENTATION_SLOT, newDummyImplementation_);
        emit LogSetDummyImplementation(oldDummyImplementation_, newDummyImplementation_);
    }
}

contract AdminInternals is CoreInternals {
    /// @dev Only admin guard
    modifier onlyAdmin() {
        require(msg.sender == _getAdmin(), "only-admin");
        _;
    }

    constructor(address admin_, address dummyImplementation_) {
        _setAdmin(admin_);
        _setDummyImplementation(dummyImplementation_);
    }

    /// @dev Sets new admin.
    function setAdmin(address newAdmin_) external onlyAdmin {
        _setAdmin(newAdmin_);
    }

    /// @dev Sets new dummy-implementation.
    function setDummyImplementation(address newDummyImplementation_) external onlyAdmin {
        _setDummyImplementation(newDummyImplementation_);
    }

    /// @dev Adds new implementation address.
    function addImplementation(address implementation_, bytes4[] calldata sigs_) external onlyAdmin {
        _setImplementationSigs(implementation_, sigs_);
    }

    /// @dev Removes an existing implementation address.
    function removeImplementation(address implementation_) external onlyAdmin {
        _removeImplementationSigs(implementation_);
    }
}

/// @title Proxy
/// @notice This abstract contract provides a fallback function that delegates all calls to another contract using the EVM.
/// It implements the Instadapp infinite-proxy: https://github.com/Instadapp/infinite-proxy
abstract contract Proxy is AdminInternals {
    constructor(address admin_, address dummyImplementation_) AdminInternals(admin_, dummyImplementation_) {}

    /// @dev Returns admin's address.
    function getAdmin() external view returns (address) {
        return _getAdmin();
    }

    /// @dev Returns dummy-implementations's address.
    function getDummyImplementation() external view returns (address) {
        return _getDummyImplementation();
    }

    /// @dev Returns bytes4[] sigs from implementation address If not registered then returns empty array.
    function getImplementationSigs(address impl_) external view returns (bytes4[] memory) {
        return _getImplementationSigs(impl_);
    }

    /// @dev Returns implementation address from bytes4 sig. If sig is not registered then returns address(0).
    function getSigsImplementation(bytes4 sig_) external view returns (address) {
        return _getSigImplementation(sig_);
    }

    /// @dev Fallback function that delegates calls to the address returned by Implementations registry.
    fallback() external payable {
        address implementation_;
        assembly {
            // get slot for sig and directly SLOAD implementation address from storage at that slot
            implementation_ := sload(
                // same as in `_getSlotSigsImplSlot()` but we must also load msg.sig from calldata.
                // msg.sig is first 4 bytes of calldata, so we can use calldataload(0) with a mask
                or(
                    // or operator sets sig_ in first 4 bytes with rest of bytes32 having default value of _SIG_SLOT_BASE
                    _SIG_SLOT_BASE,
                    and(calldataload(0), 0xFFFFFFFF00000000000000000000000000000000000000000000000000000000)
                )
            )
        }

        if (implementation_ == address(0)) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxy__ImplementationNotExist);
        }

        // Delegate the current call to `implementation`.
        // This does not return to its internall call site, it will return directly to the external caller.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            if eq(result, 0) {
                // delegatecall returns 0 on error.
                revert(0, returndatasize())
            }

            return(0, returndatasize())
        }
    }

    receive() external payable {
        // receive method can never have calldata in EVM so no need for any logic here
    }
}
