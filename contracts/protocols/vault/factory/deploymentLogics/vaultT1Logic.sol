// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";

import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";
import { IFluidVaultFactory } from "../../interfaces/iVaultFactory.sol";

import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";

import { IFluidVaultT1 } from "../../interfaces/iVaultT1.sol";
import { FluidVaultT1 } from "../../vaultT1/coreModule/main.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract FluidVaultT1DeploymentLogic is Error {
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev SSTORE2 pointer for the VaultT1 creation code. Stored externally to reduce factory bytecode (in 2 parts)
    address internal immutable VAULT_T1_CREATIONCODE_ADDRESS_1;
    address internal immutable VAULT_T1_CREATIONCODE_ADDRESS_2;

    /// @notice address of liquidity contract
    address public immutable LIQUIDITY;

    /// @notice address of Admin implementation
    address public immutable ADMIN_IMPLEMENTATION;

    /// @notice address of Secondary implementation
    address public immutable SECONDARY_IMPLEMENTATION;

    /// @notice address of this contract
    address public immutable ADDRESS_THIS;

    /// @notice Emitted when a new vaultT1 is deployed.
    /// @param vault The address of the newly deployed vault.
    /// @param vaultId The id of the newly deployed vault.
    /// @param supplyToken The address of the supply token.
    /// @param borrowToken The address of the borrow token.
    event VaultT1Deployed(
        address indexed vault,
        uint256 vaultId,
        address indexed supplyToken,
        address indexed borrowToken
    );

    constructor(address liquidity_, address vaultAdminImplementation_, address vaultSecondaryImplementation_) {
        LIQUIDITY = liquidity_;
        ADMIN_IMPLEMENTATION = vaultAdminImplementation_;
        SECONDARY_IMPLEMENTATION = vaultSecondaryImplementation_;

        // split storing creation code into two SSTORE2 pointers, because:
        // due to contract code limits 24576 bytes is the maximum amount of data that can be written in a single pointer / key.
        // Attempting to write more will result in failure.
        // So by splitting in two parts we can make sure that the contract bytecode size can use up the full limit of 24576 bytes.
        uint256 creationCodeLength_ = type(FluidVaultT1).creationCode.length;
        VAULT_T1_CREATIONCODE_ADDRESS_1 = SSTORE2.write(
            _bytesSlice(type(FluidVaultT1).creationCode, 0, creationCodeLength_ / 2)
        );
        // slice lengths:
        // when even length, e.g. 250:
        //      part 1 = 0 -> 250 / 2, so 0 until 125 length, so 0 -> 125
        //      part 2 = 250 / 2 -> 250 - 250 / 2, so 125 until 125 length, so 125 -> 250
        // when odd length: e.g. 251:
        //      part 1 = 0 -> 251 / 2, so 0 until 125 length, so 0 -> 125
        //      part 2 = 251 / 2 -> 251 - 251 / 2, so 125 until 126 length, so 125 -> 251
        VAULT_T1_CREATIONCODE_ADDRESS_2 = SSTORE2.write(
            _bytesSlice(
                type(FluidVaultT1).creationCode,
                creationCodeLength_ / 2,
                creationCodeLength_ - creationCodeLength_ / 2
            )
        );

        ADDRESS_THIS = address(this);
    }

    /// @notice                         Computes vaultT1 bytecode for the given supply token (`supplyToken_`) and borrow token (`borrowToken_`).
    ///                                 This will be called by the VaultFactory via .delegateCall
    /// @param supplyToken_             The address of the supply token.
    /// @param borrowToken_             The address of the borrow token.
    /// @return vaultCreationBytecode_  Returns the bytecode of the new vault to deploy.
    function vaultT1(
        address supplyToken_,
        address borrowToken_
    ) external returns (bytes memory vaultCreationBytecode_) {
        if (address(this) == ADDRESS_THIS) revert FluidVaultError(ErrorTypes.VaultFactory__OnlyDelegateCallAllowed);

        if (supplyToken_ == borrowToken_) revert FluidVaultError(ErrorTypes.VaultFactory__SameTokenNotAllowed);

        IFluidVaultT1.ConstantViews memory constants_;
        constants_.liquidity = LIQUIDITY;
        constants_.factory = address(this);
        constants_.adminImplementation = ADMIN_IMPLEMENTATION;
        constants_.secondaryImplementation = SECONDARY_IMPLEMENTATION;
        constants_.supplyToken = supplyToken_;
        constants_.supplyDecimals = supplyToken_ != NATIVE_TOKEN ? IERC20(supplyToken_).decimals() : 18;
        constants_.borrowToken = borrowToken_;
        constants_.borrowDecimals = borrowToken_ != NATIVE_TOKEN ? IERC20(borrowToken_).decimals() : 18;
        constants_.vaultId = IFluidVaultFactory(address(this)).totalVaults();

        address vault_ = IFluidVaultFactory(address(this)).getVaultAddress(constants_.vaultId);

        constants_ = _calculateLiquidityVaultSlots(constants_, vault_);

        vaultCreationBytecode_ = abi.encodePacked(vaultT1CreationBytecode(), abi.encode(constants_));

        emit VaultT1Deployed(vault_, constants_.vaultId, supplyToken_, borrowToken_);

        return vaultCreationBytecode_;
    }

    /// @notice returns the stored VaultT1 creation bytecode
    function vaultT1CreationBytecode() public view returns (bytes memory) {
        return
            _bytesConcat(SSTORE2.read(VAULT_T1_CREATIONCODE_ADDRESS_1), SSTORE2.read(VAULT_T1_CREATIONCODE_ADDRESS_2));
    }

    /// @dev                            Calculates the liquidity vault slots for the given supply token, borrow token, and vault (`vault_`).
    /// @param constants_               Constants struct as used in Vault T1
    /// @param vault_                   The address of the vault.
    /// @return liquidityVaultSlots_    Returns the calculated liquidity vault slots set in the `IFluidVaultT1.ConstantViews` struct.
    function _calculateLiquidityVaultSlots(
        IFluidVaultT1.ConstantViews memory constants_,
        address vault_
    ) private pure returns (IFluidVaultT1.ConstantViews memory) {
        constants_.liquiditySupplyExchangePriceSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.supplyToken
        );
        constants_.liquidityBorrowExchangePriceSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.borrowToken
        );
        constants_.liquidityUserSupplySlot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            vault_,
            constants_.supplyToken
        );
        constants_.liquidityUserBorrowSlot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            vault_,
            constants_.borrowToken
        );
        return constants_;
    }

    // @dev taken from https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
    function _bytesConcat(bytes memory _preBytes, bytes memory _postBytes) private pure returns (bytes memory) {
        bytes memory tempBytes;

        assembly {
            // Get a location of some free memory and store it in tempBytes as
            // Solidity does for memory variables.
            tempBytes := mload(0x40)

            // Store the length of the first bytes array at the beginning of
            // the memory for tempBytes.
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            // Maintain a memory counter for the current write location in the
            // temp bytes array by adding the 32 bytes for the array length to
            // the starting location.
            let mc := add(tempBytes, 0x20)
            // Stop copying when the memory counter reaches the length of the
            // first bytes array.
            let end := add(mc, length)

            for {
                // Initialize a copy counter to the start of the _preBytes data,
                // 32 bytes into its memory.
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                // Increase both counters by 32 bytes each iteration.
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                // Write the _preBytes data into the tempBytes memory 32 bytes
                // at a time.
                mstore(mc, mload(cc))
            }

            // Add the length of _postBytes to the current length of tempBytes
            // and store it as the new length in the first 32 bytes of the
            // tempBytes memory.
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            // Move the memory counter back from a multiple of 0x20 to the
            // actual end of the _preBytes data.
            mc := end
            // Stop copying when the memory counter reaches the new combined
            // length of the arrays.
            end := add(mc, length)

            for {
                let cc := add(_postBytes, 0x20)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            // Update the free-memory pointer by padding our last write location
            // to 32 bytes: add 31 bytes to the end of tempBytes to move to the
            // next 32 byte block, then round down to the nearest multiple of
            // 32. If the sum of the length of the two arrays is zero then add
            // one before rounding down to leave a blank 32 bytes (the length block with 0).
            mstore(
                0x40,
                and(
                    add(add(end, iszero(add(length, mload(_preBytes)))), 31),
                    not(31) // Round down to the nearest 32 bytes.
                )
            )
        }

        return tempBytes;
    }

    // @dev taken from https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
    function _bytesSlice(bytes memory _bytes, uint256 _start, uint256 _length) private pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }
}
