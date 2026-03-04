// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC721 } from "@openzeppelin/contracts/interfaces/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { SafeTransfer } from "../../../libraries/safeTransfer.sol";

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IFluidVaultFactory } from "../../../protocols/vault/interfaces/iVaultFactory.sol";
import { IFluidVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";
import { IFluidVault } from "../../../protocols/vault/interfaces/iVault.sol";


interface IFluidWalletFactory {
    function WALLET_PROXY() external view returns(address);
}

interface InstaFlashReceiverInterface {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata _data
    ) external returns (bool);
}

abstract contract FluidWalletVariables {
    /***********************************|
    |   Constants/Immutables            |
    |__________________________________*/
    string public constant VERSION = "1.1.1";
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant X32 = 0xffffffff;

    address public immutable VAULT_FACTORY;
    address public immutable FLUID_WALLET_FACTORY;

    /***********************************|
    |           Slot 0                  |
    |__________________________________*/
    /// @dev owner address of this wallet. It is initialized while deploying the wallet for the user.
    address public owner;

    /***********************************|
    |           Slot 1                  |
    |__________________________________*/
    /// @dev transient allow hash used to signal allowing certain entry into methods such as executeOperation etc.
    bytes32 internal _transientAllowHash;
    
    function _resetTransientStorage() internal {
        assembly {
            sstore(1, 1) // Store 1 in the transient storage 1
        }
    }
}

contract FluidWalletErrorsAndEvents {
    error FluidWallet__NotAllowed();
    error FluidWallet__ToHexDigit();
    error FluidWallet__Unauthorized();

    event Executed(
        address indexed owner,
        uint256 indexed tokenId
    );

    event ExecutedCast(address indexed owner);

    struct Action {
        address target;
        bytes data;
        uint256 value;
        uint8 operation;
    }
}

contract FluidWalletImplementation is FluidWalletVariables, FluidWalletErrorsAndEvents {
    
    constructor(
        address vaultFactory_,
        address fluidWalletFactory_
    ) {
        VAULT_FACTORY = vaultFactory_;
        FLUID_WALLET_FACTORY = fluidWalletFactory_;
    }

    /// @dev                    ERC721 callback used Fluid Vault Factory and executes actions encoded in `data_`
    ///                         Caller should be Fluid Wallet Factory.
    /// @param operator_        operator_ caller to transfer the the given token ID
    /// @param from_            from_ previous owner of the given token ID
    /// @param tokenId_         tokenId_ id of the ERC721
    /// @param data_            data bytes containing the `abi.encoded()` actions that are executed like in `Action[]` & `owner`
    function onERC721Received(
        address operator_,
        address from_,
        uint256 tokenId_,
        bytes calldata data_
    ) external returns (bytes4) {
        if (msg.sender != address(VAULT_FACTORY)) revert FluidWallet__NotAllowed();
        if (operator_ != from_) revert FluidWallet__NotAllowed();
        if (operator_ != FLUID_WALLET_FACTORY) revert FluidWallet__NotAllowed();

        (address owner_, Action[] memory actions_) = abi.decode(data_, (address, Action[]));

        /// @dev validate owner by computing wallet address.
        _validateOwner(owner_);

        /// @dev execute actions.
        _executeActions(actions_);

        /// @dev reset _transientAllowHash to prevent reentrancy
        _resetTransientStorage();

        // Transfer tokenId back to main owner
        if (IERC721(VAULT_FACTORY).ownerOf(tokenId_) == address(this)) {
            IERC721(VAULT_FACTORY).transferFrom(address(this), owner_, tokenId_);
        }

        // sweep vault specific tokens to owner address
        _sweepTokens(owner_, tokenId_);

        emit Executed(owner_, tokenId_);

        return this.onERC721Received.selector;
    }

    function cast(
        Action[] memory actions_
    ) public payable {
        /// @dev validate owner by computing wallet address.
        _validateOwner(msg.sender);

        /// @dev execute actions.
        _executeActions(actions_);

        /// @dev reset _transientAllowHash to prevent reentrancy
        _resetTransientStorage();

        emit ExecutedCast(msg.sender);
    }
    

    /***********************************|
    |         FLASHLOAN CALLBACK        |
    |__________________________________*/

    /// @dev                    callback used by Instadapp Flashloan Aggregator, executes operations while owning
    ///                         the flashloaned amounts. `data_` must contain actions, one of them must pay back flashloan
    // /// @param assets_       assets_ received a flashloan for
    // /// @param amounts_      flashloaned amounts for each asset
    // /// @param premiums_     fees to pay for the flashloan
    /// @param initiator_       flashloan initiator -> must be this contract
    /// @param data_            data bytes containing the `abi.encoded()` actions that are executed like in `CastParams.actions`

    function executeOperation(
        address[] calldata /* assets */,
        uint256[] calldata /* amounts */,
        uint256[] calldata /* premiums */,
        address initiator_,
        bytes calldata data_
    ) external returns (bool) {
        if (
            !(_transientAllowHash ==
                bytes32(keccak256(abi.encode(data_, block.timestamp))) &&
                initiator_ == address(this))
        ) {
            revert FluidWallet__Unauthorized();
        }

        _executeActions(abi.decode(data_, (Action[])));

        return true;
    }

    /***********************************|
    |         INTERNAL HELPERS          |
    |__________________________________*/

    /// @notice Calculating the slot ID for Liquidity contract for single mapping
    function _calculateStorageSlotUintMapping(uint256 slot_, uint key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    struct VaultConstants {
        address supplyToken0;
        address supplyToken1;
        address borrowToken0;
        address borrowToken1;
    }

    function _sweepTokens(address owner_, uint256 tokenId_) internal {
        uint256 tokenConfig_ = IFluidVaultFactory(VAULT_FACTORY).readFromStorage(_calculateStorageSlotUintMapping(3, tokenId_));
        address vaultAddress_ = IFluidVaultFactory(VAULT_FACTORY).getVaultAddress((tokenConfig_ >> 192) & X32);

        VaultConstants memory constants_ = _getVaultConstants(vaultAddress_);

        _flushTokens(constants_.supplyToken0, owner_);
        _flushTokens(constants_.supplyToken1, owner_);
        _flushTokens(constants_.borrowToken0, owner_);
        _flushTokens(constants_.borrowToken1, owner_);
    }

    function _getVaultConstants(address vault_) internal view returns (VaultConstants memory constants_) {
        if (vault_.code.length == 0) {
            return constants_;
        }
        try IFluidVault(vault_).TYPE() returns (uint256 type_) {
            IFluidVault.ConstantViews memory vaultConstants_ = IFluidVault(vault_).constantsView();

            constants_.supplyToken0 = vaultConstants_.supplyToken.token0;
            constants_.supplyToken1 = vaultConstants_.supplyToken.token1;
            constants_.borrowToken0 = vaultConstants_.borrowToken.token0;
            constants_.borrowToken1 = vaultConstants_.borrowToken.token1;
        } catch {
            IFluidVaultT1.ConstantViews memory vaultConstants_ = IFluidVaultT1(vault_).constantsView();
            
            constants_.supplyToken0 = vaultConstants_.supplyToken;
            constants_.supplyToken1 = address(0);
            constants_.borrowToken0 = vaultConstants_.borrowToken;
            constants_.borrowToken1 = address(0);
        }
    }

    function _flushTokens(address token_, address owner_) internal {
        if (token_ == address(0)) return;

        if (token_ == ETH_ADDRESS) {
            uint256 balance_ = address(this).balance;
            
            if (balance_ > 0) SafeTransfer.safeTransferNative(payable(owner_), balance_);
        } else {
            uint256 balance_ = IERC20(token_).balanceOf(address(this));

            if (balance_ > 0) SafeTransfer.safeTransfer(token_, owner_, balance_);
        }
    }

    /// @dev validate `owner` by recomputing fluid address.
    function _validateOwner(address owner_) internal view {
        address wallet_ = Clones.predictDeterministicAddress(
            IFluidWalletFactory(FLUID_WALLET_FACTORY).WALLET_PROXY(),
            keccak256(abi.encode(owner_)),
            FLUID_WALLET_FACTORY
        );
        if (wallet_ != address(this)) revert FluidWallet__NotAllowed();
    }

    /// @dev executes `actions_` with respective target, calldata, operation etc.
    function _executeActions(Action[] memory actions_) internal {
       uint256 actionsLength_ = actions_.length;
        for (uint256 i; i < actionsLength_; ) {
            Action memory action_ = actions_[i];

            // execute action
            bool success_;
            bytes memory result_;
            if (action_.operation == 0) {
                // call (operation = 0)

                // low-level call will return success true also if action target is not even a contract.
                // we do not explicitly check for this, default interaction is via UI which can check and handle this.
                // Also applies to delegatecall etc.
                (success_, result_) = action_.target.call{ value: action_.value }(action_.data);

                // handle action failure right after external call to better detect out of gas errors
                if (!success_) {
                    _handleActionFailure(i, result_);
                }
            } else if (action_.operation == 1) {
                // delegatecall (operation = 1)

                (success_, result_) = action_.target.delegatecall(action_.data);

                // reset _transientAllowHash to make sure it can not be set up in any way for reentrancy
                _resetTransientStorage();

                // handle action failure right after external call to better detect out of gas errors
                if (!success_) {
                    _handleActionFailure(i, result_);
                }
            } else if (action_.operation == 2) {
                // flashloan (operation = 2)
                // flashloan is always executed via .call, flashloan aggregator uses `msg.sender`, so .delegatecall
                // wouldn't send funds to this contract but rather to the original sender.

                bytes memory data_ = action_.data;
                assembly {
                    data_ := add(data_, 4) // Skip function selector (4 bytes)
                }
                // get actions data from calldata action_.data. Only supports InstaFlashAggregatorInterface
                (, , , data_, ) = abi.decode(data_, (address[], uint256[], uint256, bytes, bytes));

                // set allowHash to signal allowed entry into executeOperation()
                _transientAllowHash = bytes32(
                    keccak256(abi.encode(data_, block.timestamp))
                );

                // handle action failure right after external call to better detect out of gas errors
                (success_, result_) = action_.target.call{ value: action_.value }(action_.data);

                if (!success_) {
                    _handleActionFailure(i, result_);
                }

                // reset _transientAllowHash to prevent reentrancy during actions execution
                _resetTransientStorage();
            } else {
                // either operation does not exist or the id was not set according to what the action wants to execute
                revert(string.concat(Strings.toString(i), "_FLUID__INVALID_ID_OR_OPERATION"));
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev handles failure of an action execution depending on error cause,
    /// decoding and reverting with `result_` as reason string.
    function _handleActionFailure(uint256 i_, bytes memory result_) internal pure {
        revert(string.concat(Strings.toString(i_), _getRevertReasonFromReturnedData(result_)));
    }

    uint256 internal constant REVERT_REASON_MAX_LENGTH = 250;

    /// @dev Get the revert reason from the returnedData (supports Panic, Error & Custom Errors).
    /// Based on https://github.com/superfluid-finance/protocol-monorepo/blob/dev/packages/ethereum-contracts/contracts/libs/CallUtils.sol
    /// This is needed in order to provide some human-readable revert message from a call.
    /// @param returnedData_ revert data of the call
    /// @return reason_      revert reason
    function _getRevertReasonFromReturnedData(
        bytes memory returnedData_
    ) internal pure returns (string memory reason_) {
        if (returnedData_.length < 4) {
            // case 1: catch all
            return "_REASON_NOT_DEFINED";
        }

        bytes4 errorSelector_;
        assembly {
            errorSelector_ := mload(add(returnedData_, 0x20))
        }
        if (errorSelector_ == bytes4(0x4e487b71)) {
            // case 2: Panic(uint256), selector 0x4e487b71 (Defined since 0.8.0)
            // ref: https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require)

            // convert last byte to hex digits -> string to decode the panic code
            bytes memory result_ = new bytes(2);
            result_[0] = _toHexDigit(uint8(returnedData_[returnedData_.length - 1]) / 16);
            result_[1] = _toHexDigit(uint8(returnedData_[returnedData_.length - 1]) % 16);
            reason_ = string.concat("_TARGET_PANICKED: 0x", string(result_));
        } else if (errorSelector_ == bytes4(0x08c379a0)) {
            // case 3: Error(string), selector 0x08c379a0 (Defined at least since 0.7.0)
            // based on https://ethereum.stackexchange.com/a/83577
            assembly {
                returnedData_ := add(returnedData_, 0x04)
            }
            reason_ = string.concat("_", abi.decode(returnedData_, (string)));
        } else {
            // case 4: Custom errors (Defined since 0.8.0)

            // convert bytes4 selector to string, params are ignored...
            // based on https://ethereum.stackexchange.com/a/111876
            bytes memory result_ = new bytes(8);
            for (uint256 i; i < 4; ) {
                // use unchecked as i is < 4 and division. also errorSelector can not underflow
                unchecked {
                    result_[2 * i] = _toHexDigit(uint8(errorSelector_[i]) / 16);
                    result_[2 * i + 1] = _toHexDigit(uint8(errorSelector_[i]) % 16);
                    ++i;
                }
            }
            reason_ = string.concat("_CUSTOM_ERROR: 0x", string(result_));
        }

        {
            // truncate reason_ string to REVERT_REASON_MAX_LENGTH for reserveGas used to ensure Cast event is emitted
            if (bytes(reason_).length > REVERT_REASON_MAX_LENGTH) {
                bytes memory reasonBytes_ = bytes(reason_);
                uint256 maxLength_ = REVERT_REASON_MAX_LENGTH + 1; // cheaper than <= in each loop
                bytes memory truncatedRevertReason_ = new bytes(maxLength_);
                for (uint256 i; i < maxLength_; ) {
                    truncatedRevertReason_[i] = reasonBytes_[i];

                    unchecked {
                        ++i;
                    }
                }
                reason_ = string(truncatedRevertReason_);
            }
        }
    }

    /// @dev used to convert bytes4 selector to string
    function _toHexDigit(uint8 d) internal pure returns (bytes1) {
        // use unchecked as the operations with d can not over / underflow
        unchecked {
            if (d < 10) {
                return bytes1(uint8(bytes1("0")) + d);
            }
            if (d < 16) {
                return bytes1(uint8(bytes1("a")) + d - 10);
            }
        }
        revert FluidWallet__ToHexDigit();
    }
}