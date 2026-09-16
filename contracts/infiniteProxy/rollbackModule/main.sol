// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

import { Events } from "../events.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { CoreInternals } from "../proxy.sol";

abstract contract RollbackCoreInternals is CoreInternals {
    struct RollbackSigsSlot {
        uint40 rollbackRegisterTimestamp;
        address replacesImplementation; // address of the newly registered implementation that is supposed to be rolled back to the rollback registered one
        bytes4[] sigs;
    }

    // This is the keccak-256 hash of "eip1967.proxy.rollback" subtracted by 1
    bytes32 internal constant _ROLLBACK_DUMMY_IMPLEMENTATION_SLOT =
        0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /// @dev use EIP1967 proxy slot (see _ROLLBACK_DUMMY_IMPLEMENTATION_SLOT) except for first 4 bytes,
    // which are set to 0. This is combined with a sig which will be set in those first 4 bytes
    bytes32 internal constant _ROLLBACK_SIG_SLOT_BASE =
        0x0000000016fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /// @notice Team multisigs allowed to trigger rollback
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    /// @notice duration for how long team multisig is allowed to trigger a rollback after it has been registered
    uint256 public constant ROLLBACK_PERIOD = 7 days;

    /// @dev Sets a uint `data_` located at `slot_`.
    function _setUintSlot(bytes32 slot_, uint data_) internal {
        assembly {
            sstore(slot_, data_)
        }
    }

    /// @dev Returns a uint `data_` located at `slot_`.
    function _getUintSlot(bytes32 slot_) internal view returns (uint data_) {
        assembly {
            data_ := sload(slot_)
        }
    }

    // @dev methods below are almost the same as in ./proxy.sol, just adjusted for using rollback slots instead.

    /// @dev Returns the storage slot which stores the sigs array set for the rollback implementation.
    function _getRollbackSlotImplSigsSlot(address implementation_) internal pure returns (bytes32) {
        return keccak256(abi.encode("eip1967.proxy.rollback", implementation_));
    }

    /// @dev Returns the storage slot which stores the rollback implementation address for the function sig.
    function _getRollbackSlotSigsImplSlot(bytes4 sig_) internal pure returns (bytes32 result_) {
        assembly {
            // or operator sets sig_ in first 4 bytes with rest of bytes32 having default value of _ROLLBACK_SIG_SLOT_BASE
            result_ := or(_ROLLBACK_SIG_SLOT_BASE, sig_)
        }
    }

    /// @dev Returns an `RollbackSigsSlot` with member `value` and `rollbackRegisterTimestamp` located at `slot`.
    function _getRollbackSigsSlot(bytes32 slot_) internal pure returns (RollbackSigsSlot storage _r) {
        assembly {
            _r.slot := slot_
        }
    }

    /// @dev Sets new rollback implementation and adds mapping from implementation to sigs and sig to implementation.
    /// this method is almost the same as _setImplementationSigs in ./proxy.sol, just adjusted for using rollback slots, no event, and custom errors
    function _setRollbackImplementationSigs(address implementation_, bytes4[] memory sigs_) internal {
        if (sigs_.length == 0) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__NoRollbackSigs);
        }
        bytes32 slot_ = _getRollbackSlotImplSigsSlot(implementation_);

        bytes4[] memory sigsCheck_ = _getRollbackSigsSlot(slot_).sigs;
        if (sigsCheck_.length != 0) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__AlreadyExists);
        }

        for (uint256 i; i < sigs_.length; i++) {
            bytes32 sigSlot_ = _getRollbackSlotSigsImplSlot(sigs_[i]);
            if (sigSlot_ == _ROLLBACK_DUMMY_IMPLEMENTATION_SLOT) {
                revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__SigSlotCollision);
            }
            if (_getAddressSlot(sigSlot_) != address(0)) {
                revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__SigAlreadyExists);
            }
            _setAddressSlot(sigSlot_, implementation_);
        }
    }

    /// @dev Removes rollback implementation and the mappings corresponding to it.
    /// this method is similar as _removeImplementationSigs in ./proxy.sol, just only the remove sigs logic adjusted for using rollback slots
    function _removeRollbackImplementationSigs(bytes4[] memory sigs_) internal {
        for (uint256 i; i < sigs_.length; i++) {
            bytes32 sigSlot_ = _getRollbackSlotSigsImplSlot(sigs_[i]);
            if (sigSlot_ == _ROLLBACK_DUMMY_IMPLEMENTATION_SLOT) continue; // never overwrite dummy impl slot
            _setAddressSlot(sigSlot_, address(0));
        }
    }
}

/// @notice Events for InfiniteProxy rollback operations
abstract contract RollbackEvents {
    /// @notice Emitted when dummy implementation is registered for rollback
    event LogRegisterRollbackDummyImplementation(address rollbackDummyImplementation, uint256 timestamp);

    /// @notice Emitted when dummy implementation rollback occurs
    event LogRollbackDummyImplementation(address restoredDummyImplementation);

    /// @notice Emitted when a rollback implementation is registered
    event LogRegisterRollbackImplementation(address rollbackImplementation, address newImplementation, bytes4[] sigs);

    /// @notice Emitted when a rollback occurs
    event LogRollbackImplementation(address rollbackImplementation, address replacedImplementation, bytes4[] sigs);

    /// @notice Emitted when expired rollback implementation storage is cleaned up
    event LogCleanupExpiredRollbackImplementation(address implementation);
}

/// @title InfiniteProxy rollback module
/// @notice Allows the team multisig to roll back to a previously registered implementation or dummy implementation within a time window after upgrades.
/// @dev Upgrades are expected to happen infrequently (every few months).
///      Performing an upgrade while another upgrade is still within its active rollback window is not an expected scenario and is not supported.
///      The design assumes the rollback period will have elapsed before any new upgrade is performed.
contract InfiniteProxyRollbackModule is RollbackCoreInternals, RollbackEvents {
    /// @dev Only admin guard
    modifier onlyAdmin() {
        if (_getAdmin() != msg.sender) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__Unauthorized);
        }
        _;
    }

    /// @dev Only team multisig guard
    modifier onlyMultisig() {
        if (TEAM_MULTISIG != msg.sender) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__Unauthorized);
        }
        _;
    }

    /// @notice Register the current dummy implementation for rollback.
    function registerRollbackDummyImplementation() external onlyAdmin {
        uint256 data_ = _getUintSlot(_ROLLBACK_DUMMY_IMPLEMENTATION_SLOT);
        if (data_ != 0) {
            uint256 rollbackRegisterTimestamp_ = data_ >> 160;
            if (block.timestamp <= rollbackRegisterTimestamp_ + ROLLBACK_PERIOD) {
                revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__AlreadyExists);
            }
            // Expired: delete first then write
            _setUintSlot(_ROLLBACK_DUMMY_IMPLEMENTATION_SLOT, 0);
        }
        address oldDummyImplementation_ = _getDummyImplementation();
        if (oldDummyImplementation_ == address(0)) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__ZeroDummyImplementation);
        }
        // Compose bytes32: upper 5 bytes = block.timestamp (uint40), lower 20 bytes = address, remaining 7 bytes = 0
        data_ = (uint160(oldDummyImplementation_)) | (uint256(uint40(block.timestamp)) << 160);
        _setUintSlot(_ROLLBACK_DUMMY_IMPLEMENTATION_SLOT, data_);
        emit LogRegisterRollbackDummyImplementation(oldDummyImplementation_, block.timestamp);
    }

    /// @notice Rollback to the previously registered dummy implementation.
    function rollbackDummyImplementation() external onlyMultisig {
        uint256 data_ = _getUintSlot(_ROLLBACK_DUMMY_IMPLEMENTATION_SLOT);

        address previousDummyImplementation_ = address(uint160(data_));

        if (previousDummyImplementation_ == address(0)) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__NotRegistered);
        }

        uint256 rollbackRegisterTimestamp_ = uint256(data_ >> 160);

        if (block.timestamp > rollbackRegisterTimestamp_ + ROLLBACK_PERIOD) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__Expired);
        }

        _setDummyImplementation(previousDummyImplementation_);

        _setUintSlot(_ROLLBACK_DUMMY_IMPLEMENTATION_SLOT, 0); // clear out rollback dummy impl slot

        emit LogRollbackDummyImplementation(previousDummyImplementation_);
    }

    /// @notice Register a currently active implementation as rollback implementation. To be triggered before upgrade.
    /// @param rollbackImplementation_ The currently active implementation to rollback to.
    /// @param newImplementation_ The new implementation being upgraded to, which is replaced by the old one in the rollback.
    function registerRollbackImplementation(
        address rollbackImplementation_,
        address newImplementation_
    ) external onlyAdmin {
        bytes4[] memory sigs_ = _getImplementationSigs(rollbackImplementation_); // read currently registered sigs

        _setRollbackImplementationSigs(rollbackImplementation_, sigs_); // store currently registered sigs for rollback

        RollbackSigsSlot storage slotData_ = _getRollbackSigsSlot(
            _getRollbackSlotImplSigsSlot(rollbackImplementation_)
        );
        slotData_.sigs = sigs_;
        slotData_.rollbackRegisterTimestamp = uint40(block.timestamp);
        slotData_.replacesImplementation = newImplementation_;

        emit LogRegisterRollbackImplementation(rollbackImplementation_, newImplementation_, sigs_);
    }

    /// @notice Rollback a currently active implementation to its' previously registered implementation.
    /// @param rollbackImplementation_ The implementation to rollback to.
    /// @param newImplementation_ The new, recently upgraded currently active implementation being replaced by the old one in the rollback.
    function rollbackImplementation(address rollbackImplementation_, address newImplementation_) external onlyMultisig {
        bytes32 slot_ = _getRollbackSlotImplSigsSlot(rollbackImplementation_);

        RollbackSigsSlot memory slotData_ = _getRollbackSigsSlot(slot_);
        if (slotData_.sigs.length == 0) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__NotRegistered);
        }

        if (block.timestamp > slotData_.rollbackRegisterTimestamp + ROLLBACK_PERIOD) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__Expired);
        }

        if (newImplementation_ != slotData_.replacesImplementation) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__NotRegistered);
        }

        _removeImplementationSigs(newImplementation_); // remove the upgraded implementation currently active

        _setImplementationSigs(rollbackImplementation_, slotData_.sigs); // register the previously active implementation registered as rollback

        _removeRollbackImplementationSigs(slotData_.sigs); // clean up the rollback sigs

        // clean up the rollback storage data
        RollbackSigsSlot storage storageSlot_ = _getRollbackSigsSlot(slot_);
        delete storageSlot_.sigs;
        delete storageSlot_.rollbackRegisterTimestamp;
        delete storageSlot_.replacesImplementation;

        emit LogRollbackImplementation(rollbackImplementation_, slotData_.replacesImplementation, slotData_.sigs);
    }

    /// @notice Clean up expired rollback storage for an implementation. Callable by anyone once ROLLBACK_PERIOD has elapsed.
    /// @param implementation_ The rollback implementation whose storage should be cleaned up.
    function cleanupExpiredRollbackImplementation(address implementation_) external {
        bytes32 slot_ = _getRollbackSlotImplSigsSlot(implementation_);
        RollbackSigsSlot storage storageSlot_ = _getRollbackSigsSlot(slot_);

        if (storageSlot_.sigs.length == 0) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__NotRegistered);
        }
        if (block.timestamp <= storageSlot_.rollbackRegisterTimestamp + ROLLBACK_PERIOD) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__NotExpired);
        }

        bytes4[] memory sigs_ = storageSlot_.sigs;
        _removeRollbackImplementationSigs(sigs_);

        delete storageSlot_.sigs;
        delete storageSlot_.rollbackRegisterTimestamp;
        delete storageSlot_.replacesImplementation;

        emit LogCleanupExpiredRollbackImplementation(implementation_);
    }

    /// @dev Returns rollback data for a certain implementation address
    function getRollbackForImplementation(
        address rollbackImplementation_
    ) external view returns (RollbackSigsSlot memory rollbackData_) {
        address rollbackDummyImplementation_ = address(uint160(_getUintSlot(_ROLLBACK_DUMMY_IMPLEMENTATION_SLOT)));
        if (rollbackImplementation_ == rollbackDummyImplementation_) {
            revert FluidInfiniteProxyError(ErrorTypes.InfiniteProxyRollback__NotAllowed);
        }
        bytes32 slot_ = _getRollbackSlotImplSigsSlot(rollbackImplementation_);
        RollbackSigsSlot storage slotData_ = _getRollbackSigsSlot(slot_);
        rollbackData_.sigs = slotData_.sigs;
        rollbackData_.rollbackRegisterTimestamp = slotData_.rollbackRegisterTimestamp;
        rollbackData_.replacesImplementation = slotData_.replacesImplementation;
    }

    /// @dev Returns rollback dummy-implementations's addres and the registered rollback timestamp
    function getRollbackDummyImplementation()
        external
        view
        returns (address rollbackDummyImplementation_, uint256 rollbackRegisterTimestamp_)
    {
        uint256 data_ = _getUintSlot(_ROLLBACK_DUMMY_IMPLEMENTATION_SLOT);

        rollbackDummyImplementation_ = address(uint160(data_));
        rollbackRegisterTimestamp_ = uint256(data_ >> 160);
    }
}
