// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IFluidLiquidity } from "../liquidity/interfaces/iLiquidity.sol";
import { IFluidLendingFactory } from "../protocols/lending/interfaces/iLendingFactory.sol";
import { IFTokenAdmin } from "../protocols/lending/interfaces/iFToken.sol";
import { IFluidVaultT1 } from "../protocols/vault/interfaces/iVaultT1.sol";
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
            uint256 existingAllowance_ = IERC20(token_).allowance(address(this), protocol_);

            // making approval 0 first and then re-approving with a new amount.
            SafeERC20.safeApprove(IERC20(address(token_)), protocol_, 0);
            SafeERC20.safeApprove(IERC20(address(token_)), protocol_, amount_);
            _protocolTokens[protocol_].add(token_);
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

            SafeERC20.safeApprove(IERC20(address(token_)), protocol_, 0);
            _protocolTokens[protocol_].remove(token_);
            emit LogRevoke(protocol_, token_);
        }
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

    constructor(IFluidLiquidity liquidity_) validAddress(address(liquidity_)) Variables(liquidity_) {
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

    /// @notice              Executes a rebalance on a protocol by calling that protocol's `rebalance` function
    /// @param protocol_     The protocol to rebalance
    /// @param value_        any msg.value to send along (as fetched from resolver!)
    function rebalanceFToken(address protocol_, uint256 value_) external payable onlyRebalancer {
        uint256 amount_ = IFTokenAdmin(protocol_).rebalance{ value: value_ }();
        emit LogRebalanceFToken(protocol_, amount_);
    }

    /// @notice              Executes a rebalance on a protocol by calling that protocol's `rebalance` function
    /// @param protocol_     The protocol to rebalance
    /// @param value_        any msg.value to send along (as fetched from resolver!)
    function rebalanceVault(address protocol_, uint256 value_) external payable onlyRebalancer {
        (int256 colAmount_, int256 debtAmount_) = IFluidVaultT1(protocol_).rebalance{ value: value_ }();

        IFluidVaultT1.ConstantViews memory constants_ = IFluidVaultT1(protocol_).constantsView();
        if (constants_.supplyToken == NATIVE_TOKEN_ADDRESS) {
            if (value_ > 0 && colAmount_ < 0) {
                revert FluidReserveContractError(ErrorTypes.ReserveContract__WrongValueSent);
            }
        }

        if (constants_.borrowToken == NATIVE_TOKEN_ADDRESS) {
            if (value_ > 0 && debtAmount_ > 0) {
                revert FluidReserveContractError(ErrorTypes.ReserveContract__WrongValueSent);
            }
        }

        if (value_ > 0 && !(constants_.supplyToken == NATIVE_TOKEN_ADDRESS || constants_.borrowToken == NATIVE_TOKEN_ADDRESS)) {
            revert FluidReserveContractError(ErrorTypes.ReserveContract__WrongValueSent);
        }

        emit LogRebalanceVault(protocol_, colAmount_, debtAmount_);
    }

    function transferFunds(address[] calldata tokens_) external virtual onlyAuth {
        for (uint256 i = 0; i < tokens_.length; i++) {
            SafeTransfer.safeTransfer(
                address(tokens_[i]),
                address(LIQUIDITY),
                IERC20(tokens_[i]).balanceOf(address(this))
            );
            emit LogTransferFunds(tokens_[i]);
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

    /// @notice allow receive native token
    receive() external payable {}
}
