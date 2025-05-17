// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IFTokenAdmin } from "../protocols/lending/interfaces/iFToken.sol";
import { IFluidVaultT1 } from "../protocols/vault/interfaces/iVaultT1.sol";
import { IFluidVault } from "../protocols/vault/interfaces/iVault.sol";
import { SafeTransfer } from "../libraries/safeTransfer.sol";

import { Variables } from "./variables.sol";
import { Events } from "./events.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Error } from "./error.sol";

abstract contract ReserveContractAuth is Variables, Error, Events {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__AddressZero);
        }
        _;
    }

    /// @notice Checks that the sender is an auth
    modifier onlyAuth() {
        if (!isAuth[msg.sender] && owner() != msg.sender)
            revert FluidReserveContractError(ErrorTypes.ReserveContract__Unauthorized);
        _;
    }

    /// @notice              Updates an auth's status as an auth
    /// @param auth_         The address to update
    /// @param isAuth_       Whether or not the address should be an auth
    function updateAuth(address auth_, bool isAuth_) external onlyOwner validAddress(auth_) {
        isAuth[auth_] = isAuth_;
        emit LogUpdateAuth(auth_, isAuth_);
    }

    /// @notice                 Updates a rebalancer's status as a rebalancer
    /// @param rebalancer_      The address to update
    /// @param isRebalancer_    Whether or not the address should be a rebalancer
    function updateRebalancer(address rebalancer_, bool isRebalancer_) external onlyAuth validAddress(rebalancer_) {
        isRebalancer[rebalancer_] = isRebalancer_;
        emit LogUpdateRebalancer(rebalancer_, isRebalancer_);
    }

    /// @notice              Approves protocols to spend the reserves tokens
    /// @dev                 The parameters are parallel arrays
    /// @param protocols_    The protocols that will be spending reserve tokens
    /// @param tokens_       The tokens to approve
    /// @param amounts_      The amounts to approve
    function approve(
        address[] memory protocols_,
        address[] memory tokens_,
        uint256[] memory amounts_
    ) external onlyAuth {
        if (protocols_.length != tokens_.length || tokens_.length != amounts_.length) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__InvalidInputLenghts);
        }

        for (uint256 i = 0; i < protocols_.length; i++) {
            address protocol_ = protocols_[i];
            address token_ = tokens_[i];
            uint256 amount_ = amounts_[i];
            uint256 existingAllowance_;

            if (token_ == NATIVE_TOKEN_ADDRESS) {
                existingAllowance_ = nativeTokenAllowances[protocol_];
                _approveNativeToken(protocol_, amount_);
            } else {
                existingAllowance_ = IERC20(token_).allowance(address(this), protocol_);

                // making approval 0 first and then re-approving with a new amount.
                SafeERC20.safeApprove(IERC20(address(token_)), protocol_, 0);
                SafeERC20.safeApprove(IERC20(address(token_)), protocol_, amount_);
            }
            _protocolTokens[protocol_].add(token_);

            _protocols.add(protocol_);
            emit LogAllow(protocol_, token_, amount_, existingAllowance_);
        }
    }

    /// @notice              Revokes protocols' ability to spend the reserves tokens
    /// @dev                 The parameters are parallel arrays
    /// @param protocols_    The protocols that will no longer be spending reserve tokens
    /// @param tokens_       The tokens to revoke
    function revoke(address[] memory protocols_, address[] memory tokens_) external onlyAuth {
        if (protocols_.length != tokens_.length) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__InvalidInputLenghts);
        }

        for (uint256 i = 0; i < protocols_.length; i++) {
            address protocol_ = protocols_[i];
            address token_ = tokens_[i];

            if (token_ == NATIVE_TOKEN_ADDRESS) {
                _approveNativeToken(protocol_, 0);
            } else {
                SafeERC20.safeApprove(IERC20(address(token_)), protocol_, 0);
            }
            _protocolTokens[protocol_].remove(token_);

            if (_protocolTokens[protocol_].length() == 0) {
                _protocols.remove(protocol_);
            }
            emit LogRevoke(protocol_, token_);
        }
    }

    function _approveNativeToken(address protocol_, uint256 amount_) internal {
        nativeTokenAllowances[protocol_] = amount_;
    }
}

/// @title    Reserve Contract
/// @notice   This contract manages the approval of tokens for use by protocols and
///           the execution of rebalances on protocols
contract FluidReserveContract is Error, ReserveContractAuth, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /// @notice Checks that the sender is a rebalancer
    modifier onlyRebalancer() {
        if (!isRebalancer[msg.sender]) revert FluidReserveContractError(ErrorTypes.ReserveContract__Unauthorized);
        _;
    }

    constructor() {
        // ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /// @notice initializes the contract
    /// @param _auths  The addresses that have the auth to approve and revoke protocol token allowances
    /// @param _rebalancers  The addresses that can execute a rebalance on a protocol
    /// @param owner_  owner address is able to upgrade contract and update auth users
    function initialize(
        address[] memory _auths,
        address[] memory _rebalancers,
        address owner_
    ) public initializer validAddress(owner_) {
        for (uint256 i = 0; i < _auths.length; i++) {
            isAuth[_auths[i]] = true;
            emit LogUpdateAuth(_auths[i], true);
        }
        for (uint256 i = 0; i < _rebalancers.length; i++) {
            isRebalancer[_rebalancers[i]] = true;
            emit LogUpdateRebalancer(_rebalancers[i], true);
        }
        _transferOwnership(owner_);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice override renounce ownership as it could leave the contract in an unwanted state if called by mistake.
    function renounceOwnership() public view override onlyOwner {
        revert FluidReserveContractError(ErrorTypes.ReserveContract__RenounceOwnershipUnsupported);
    }

    /// @notice              Executes a rebalance on a fToken protocol by calling that protocol's `rebalance` function
    /// @param protocol_     The protocol to rebalance
    /// @param value_        any msg.value to send along (as fetched from resolver!)
    function rebalanceFToken(address protocol_, uint256 value_) public payable onlyRebalancer {
        if (value_ > 0) {
            if (nativeTokenAllowances[protocol_] < value_) {
                revert FluidReserveContractError(ErrorTypes.ReserveContract__InsufficientAllowance);
            }
            nativeTokenAllowances[protocol_] -= value_;
        }

        uint256 amount_ = IFTokenAdmin(protocol_).rebalance{ value: value_ }();
        emit LogRebalanceFToken(protocol_, amount_);
    }

    /// @notice              Executes a rebalance on a vaultT1 protocol by calling that protocol's `rebalance` function
    /// @param protocol_     The protocol to rebalance
    /// @param value_        any msg.value to send along (as fetched from resolver!)
    function rebalanceVault(address protocol_, uint256 value_) public payable onlyRebalancer {
        if (value_ > 0) {
            if (nativeTokenAllowances[protocol_] < value_) {
                revert FluidReserveContractError(ErrorTypes.ReserveContract__InsufficientAllowance);
            }
            nativeTokenAllowances[protocol_] -= value_;
        }

        (int256 colAmount_, int256 debtAmount_) = IFluidVaultT1(protocol_).rebalance{ value: value_ }();

        if (value_ > 0) {
            IFluidVaultT1.ConstantViews memory constants_ = IFluidVaultT1(protocol_).constantsView();
            if (constants_.supplyToken == NATIVE_TOKEN_ADDRESS && colAmount_ < 0) {
                revert FluidReserveContractError(ErrorTypes.ReserveContract__WrongValueSent);
            }

            if (constants_.borrowToken == NATIVE_TOKEN_ADDRESS && debtAmount_ > 0) {
                revert FluidReserveContractError(ErrorTypes.ReserveContract__WrongValueSent);
            }

            if (!(constants_.supplyToken == NATIVE_TOKEN_ADDRESS || constants_.borrowToken == NATIVE_TOKEN_ADDRESS)) {
                revert FluidReserveContractError(ErrorTypes.ReserveContract__WrongValueSent);
            }
        }

        emit LogRebalanceVault(protocol_, colAmount_, debtAmount_);
    }

    /// @notice              Executes a rebalance on a DEX vault protocol by calling that protocol's `rebalance` function
    /// @param protocol_     The protocol to rebalance
    /// @param value_        any msg.value to send along (as fetched from resolver!)
    /// @param colToken0MinMax_ if vault supply is more than Liquidity Layer then deposit difference through reserve/rebalance contract
    /// @param colToken1MinMax_ if vault supply is less than Liquidity Layer then withdraw difference to reserve/rebalance contract
    /// @param debtToken0MinMax_ if vault borrow is more than Liquidity Layer then borrow difference to reserve/rebalance contract
    /// @param debtToken1MinMax_ if vault borrow is less than Liquidity Layer then payback difference through reserve/rebalance contract
    function rebalanceDexVault(
        address protocol_,
        uint256 value_,
        int colToken0MinMax_,
        int colToken1MinMax_,
        int debtToken0MinMax_,
        int debtToken1MinMax_
    ) public payable onlyRebalancer {
        uint256 initialBalance_ = address(this).balance;
        if (value_ > 0 && nativeTokenAllowances[protocol_] < value_) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__InsufficientAllowance);
        }

        (int256 colAmount_, int256 debtAmount_) = IFluidVault(protocol_).rebalance{ value: value_ }(
            colToken0MinMax_,
            colToken1MinMax_,
            debtToken0MinMax_,
            debtToken1MinMax_
        );

        if (value_ > 0 && (colAmount_ > 0 || debtAmount_ < 0)) {
            // value was sent along and either deposit or payback happened. subtract the amount from allowance.
            // only substract actually used balance from allowance
            uint256 usedBalance_ = initialBalance_ > address(this).balance
                ? initialBalance_ - address(this).balance
                : 0;
            if (msg.value > 0) {
                usedBalance_ = usedBalance_ > msg.value ? usedBalance_ - msg.value : 0;
            }
            if (usedBalance_ > 0) {
                nativeTokenAllowances[protocol_] -= usedBalance_;
            }
        }

        emit LogRebalanceVault(protocol_, colAmount_, debtAmount_);
    }

    /// @notice calls `rebalanceFToken` multiple times
    /// @dev don't need onlyRebalancer modifier as it is already checked in `rebalanceFToken` function
    function rebalanceFTokens(address[] calldata protocols_, uint256[] calldata values_) external payable {
        if (protocols_.length != values_.length) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__InvalidInputLenghts);
        }

        for (uint256 i = 0; i < protocols_.length; i++) {
            rebalanceFToken(protocols_[i], values_[i]);
        }
    }

    /// @notice calls `rebalanceVault` multiple times
    /// @dev  don't need onlyRebalancer modifier as it is already checked in `rebalanceVault` function
    function rebalanceVaults(address[] calldata protocols_, uint256[] calldata values_) external payable {
        if (protocols_.length != values_.length) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__InvalidInputLenghts);
        }

        for (uint256 i = 0; i < protocols_.length; i++) {
            rebalanceVault(protocols_[i], values_[i]);
        }
    }

    /// @notice calls `rebalanceDexVault` multiple times
    /// @dev  don't need onlyRebalancer modifier as it is already checked in `rebalanceDexVault` function
    function rebalanceDexVaults(
        address[] calldata protocols_,
        uint256[] calldata values_,
        int[] calldata colToken0MinMaxs_,
        int[] calldata colToken1MinMaxs_,
        int[] calldata debtToken0MinMaxs_,
        int[] calldata debtToken1MinMaxs_
    ) external payable {
        if (
            protocols_.length != values_.length ||
            protocols_.length != colToken0MinMaxs_.length ||
            protocols_.length != colToken1MinMaxs_.length ||
            protocols_.length != debtToken0MinMaxs_.length ||
            protocols_.length != debtToken1MinMaxs_.length
        ) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__InvalidInputLenghts);
        }

        for (uint256 i = 0; i < protocols_.length; i++) {
            rebalanceDexVault(
                protocols_[i],
                values_[i],
                colToken0MinMaxs_[i],
                colToken1MinMaxs_[i],
                debtToken0MinMaxs_[i],
                debtToken1MinMaxs_[i]
            );
        }
    }

    /// @notice              Withdraws funds from the contract to a specified receiver
    /// @param tokens_       The tokens to withdraw
    /// @param amounts_      The amounts of each token to withdraw
    /// @param receiver_     The address to receive the withdrawn funds
    /// @dev                 This function can only be called by the owner, which is always the Governance address
    function withdrawFunds(address[] memory tokens_, uint256[] memory amounts_, address receiver_) external onlyOwner {
        if (tokens_.length != amounts_.length) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__InvalidInputLenghts);
        }

        for (uint256 i = 0; i < tokens_.length; i++) {
            if (tokens_[i] == NATIVE_TOKEN_ADDRESS) {
                SafeTransfer.safeTransferNative(receiver_, amounts_[i]);
            } else {
                SafeTransfer.safeTransfer(address(tokens_[i]), receiver_, amounts_[i]);
            }
            emit LogWithdrawFunds(tokens_[i], amounts_[i], receiver_);
        }
    }

    /// @notice              Gets the tokens that are approved for use by a protocol
    /// @param protocol_     The protocol to get the tokens for
    /// @return result_      The tokens that are approved for use by the protocol
    function getProtocolTokens(address protocol_) external view returns (address[] memory result_) {
        EnumerableSet.AddressSet storage tokens_ = _protocolTokens[protocol_];
        result_ = new address[](tokens_.length());
        for (uint256 i = 0; i < tokens_.length(); i++) {
            result_[i] = tokens_.at(i);
        }
    }

    /// @notice              Gets the allowances that are approved to a protocol
    /// @param protocol_     The protocol to get the tokens for
    /// @return allowances_  The tokens that are approved for use by the protocol
    function getProtocolAllowances(address protocol_) public view returns (TokenAllowance[] memory allowances_) {
        EnumerableSet.AddressSet storage tokens_ = _protocolTokens[protocol_];
        allowances_ = new TokenAllowance[](tokens_.length());
        for (uint256 i = 0; i < tokens_.length(); i++) {
            address token_ = tokens_.at(i);
            (allowances_[i]).token = token_;
            if (token_ == NATIVE_TOKEN_ADDRESS) {
                (allowances_[i]).allowance = nativeTokenAllowances[protocol_];
            } else {
                (allowances_[i]).allowance = IERC20(token_).allowance(address(this), protocol_);
            }
        }
    }

    /// @notice              Gets the allowances that are approved to a protocol
    /// @return allowances_  The tokens that are approved for use by all the protocols
    function getAllProtocolAllowances() public view returns (ProtocolTokenAllowance[] memory allowances_) {
        allowances_ = new ProtocolTokenAllowance[](_protocols.length());
        for (uint i = 0; i < _protocols.length(); i++) {
            address protocol_ = _protocols.at(i);
            (allowances_[i]).protocol = protocol_;
            (allowances_[i]).tokenAllowances = getProtocolAllowances(protocol_);
        }
    }

    /// @notice allow receive native token
    receive() external payable {}
}
