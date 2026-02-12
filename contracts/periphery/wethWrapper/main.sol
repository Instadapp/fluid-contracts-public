// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { Error } from "./error.sol";
import { Events } from "./events.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { TickMath } from "../../libraries/tickMath.sol";
import { SafeApprove } from "../../libraries/safeApprove.sol";
import { SafeTransfer } from "../../libraries/safeTransfer.sol";
import { IFluidVaultT1 } from "../../protocols/vault/interfaces/iVaultT1.sol";
import { IWETH9 } from "../../protocols/lending/interfaces/external/iWETH9.sol";

/// @notice OwnableUpgradeable is a modified version of OpenZeppelin's Ownable contract to allow for upgradeable implementation
abstract contract OwnableUpgradeable is Initializable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract ReentrancyGuard is Events, Error {
    uint8 internal constant REENTRANCY_NOT_ENTERED = 1;
    uint8 internal constant REENTRANCY_ENTERED = 2;

    uint8 internal _status;

    function _Reentrancy_init_chained() internal {
        _status = REENTRANCY_NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status != REENTRANCY_NOT_ENTERED) revert FluidWethWrapperError(ErrorTypes.Weth_ReEntracy);
        _status = REENTRANCY_ENTERED;
        _;
        _status = REENTRANCY_NOT_ENTERED;
    }
}

/// @title   WETH Wrapper for Fluid Vault T1
/// @notice  Allows depositing, withdrawal, borrowing and repaying of assets from vaults using WETH following aave interface
/// @dev wrapping/unwrapping to ETH under the hood for vault T1
contract FluidWETHWrapper is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    using SafeTransfer for IERC20;
    using SafeApprove for IERC20;

    IWETH9 public immutable WETH;

    IFluidVaultT1 public immutable VAULT;

    /// @dev below variables can be derived directly or indirectly using vault address
    // USDC token address
    address public immutable BORROW_TOKEN;

    address public immutable VAULT_FACTORY;

    address public immutable LIQUIDITY;

    uint256 public immutable VAULT_ID;

    uint internal constant X8 = 0xff;
    uint internal constant X19 = 0x7ffff;
    uint internal constant X24 = 0xffffff;
    uint internal constant X64 = 0xffffffffffffffff;

    // default value to be zero, so operate can mint fresh position
    uint64 public nftId;

    /// @param vaultAddress_  Fluid Vault address
    /// @param weth_          WETH token address
    constructor(address vaultAddress_, address weth_) {
        // ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();

        if (vaultAddress_ == address(0) || weth_ == address(0))
            revert FluidWethWrapperError(ErrorTypes.Weth_ZeroAddress);

        WETH = IWETH9(weth_);
        VAULT = IFluidVaultT1(vaultAddress_);

        VAULT_ID = VAULT.VAULT_ID();
        LIQUIDITY = VAULT.LIQUIDITY();
        VAULT_FACTORY = VAULT.VAULT_FACTORY();
        BORROW_TOKEN = VAULT.constantsView().borrowToken;
    }

    function initialize() public initializer {
        // initialize reentracy guard
        _Reentrancy_init_chained();

        // set owner as msg.sender
        __Ownable_init_unchained();
    }

    function _calculateStorageSlotUintMapping(uint256 slot_, uint key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    function _calculateStorageSlotIntMapping(uint256 slot_, int key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    function _getPositionDataRaw() internal view returns (uint) {
        return VAULT.readFromStorage(_calculateStorageSlotUintMapping(3, nftId));
    }

    function _getVaultVariables2Raw() internal view returns (uint256) {
        return VAULT.readFromStorage(bytes32(uint256(1)));
    }

    function getTickDataRaw(int tick_) internal view returns (uint) {
        return VAULT.readFromStorage(_calculateStorageSlotIntMapping(5, tick_));
    }

    function _getPositionBorrow() internal view returns (uint256 borrow) {
        uint256 positionData_ = _getPositionDataRaw();

        uint256 supply = (positionData_ >> 45) & X64;
        supply = (supply >> 8) << (supply & X8);

        // if only supply position
        if ((positionData_ & 1) == 1) return 0;

        int256 tick = (positionData_ & 2) == 2 ? int((positionData_ >> 2) & X19) : -int((positionData_ >> 2) & X19);
        uint256 tickId = (positionData_ >> 21) & X24;

        borrow = (TickMath.getRatioAtTick(int24(tick)) * supply) >> 96;

        uint tickData_ = getTickDataRaw(tick);

        if (((tickData_ & 1) == 1) || (((tickData_ >> 1) & X24) > tickId))
            (tick, borrow, supply, , ) = VAULT.fetchLatestPosition(tick, tickId, borrow, tickData_);

        uint256 dustBorrow = (positionData_ >> 109) & X64;
        dustBorrow = (dustBorrow >> 8) << (dustBorrow & X8);

        if (borrow > dustBorrow) borrow = borrow - dustBorrow;
        else {
            borrow = 0;
            dustBorrow = 0;
        }

        // Retrieve the latest exchange prices
        (, , , uint256 vaultBorrowExchangePrice) = VAULT.updateExchangePrices(_getVaultVariables2Raw());

        // exhange precision - 1e12, round up debt then add 1 wei for max repay case
        borrow = ((borrow * vaultBorrowExchangePrice + 1e12 - 1) / 1e12) + 1;
    }

    function _getPositionSupply() internal view returns (uint256 supply) {
        uint256 positionData_ = _getPositionDataRaw();

        supply = (positionData_ >> 45) & X64;
        supply = (supply >> 8) << (supply & X8);

        // if not supply position
        if ((positionData_ & 1) == 0) {
            int256 tick = (positionData_ & 2) == 2 ? int((positionData_ >> 2) & X19) : -int((positionData_ >> 2) & X19);
            uint256 tickId = (positionData_ >> 21) & X24;

            uint tickData_ = getTickDataRaw(tick);

            if (((tickData_ & 1) == 1) || (((tickData_ >> 1) & X24) > tickId)) {
                uint256 borrow = (TickMath.getRatioAtTick(int24(tick)) * supply) >> 96;
                (tick, borrow, supply, , ) = VAULT.fetchLatestPosition(tick, tickId, borrow, tickData_);
            }
        }

        // Retrieve the latest exchange prices
        (, , uint256 vaultSupplyExchangePrice, ) = VAULT.updateExchangePrices(_getVaultVariables2Raw());

        supply = ((supply * vaultSupplyExchangePrice) / 1e12);
    }

    /// @notice get the vault nft position on vault
    /// @return supply amount
    /// @return borrow amount
    function getPosition() external view returns (uint256, uint256) {
        return (_getPositionSupply(), _getPositionBorrow());
    }

    /// @notice Deposit WETH as collateral to a T1 VAULT.
    ///         - If `nftId` == 0, new vault position gets created (NFT mint to this)
    /// @param asset   The asset to deposit in contract (weth)
    /// @param amount  Amount of asset to deposit as collateral
    /// @param onBehalfOf  Deposit on behalf of, should be same as msg.sender
    /// @param referralCode  Un-used param
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external nonReentrant onlyOwner {
        if (amount == 0) revert FluidWethWrapperError(ErrorTypes.WETH__ZeroAmount);
        if (onBehalfOf != msg.sender) revert FluidWethWrapperError(ErrorTypes.Weth_NotOwner);
        if (asset != address(WETH)) revert FluidWethWrapperError(ErrorTypes.Weth_AssetNotSupported);

        SafeTransfer.safeTransferFrom(address(asset), msg.sender, address(this), amount);
        WETH.withdraw(amount);

        (uint256 newNftId, , ) = VAULT.operate{ value: amount }(
            nftId,
            int256(amount), // deposit amount > 0
            int256(0), // no borrow
            address(this) // NFT must be minted to this address
        );

        // If it was a newly minted position, store ownership
        if (nftId != newNftId) nftId = uint64(newNftId);

        emit LogDeposit(msg.sender, nftId, amount);
    }

    /// @notice Withdraw WETH collateral from a T1 vault
    /// @dev    The vault sends us ETH, which we wrap into WETH and transfer to the user.
    /// @param asset   The asset to deposit in contract (weth)
    /// @param amount  Amount of asset to borrow as collateral
    /// @param to withdraw should go to this address
    function withdraw(address asset, uint256 amount, address to) external nonReentrant onlyOwner {
        if (amount == 0) revert FluidWethWrapperError(ErrorTypes.WETH__ZeroAmount);
        if (asset != address(WETH)) revert FluidWethWrapperError(ErrorTypes.Weth_AssetNotSupported);

        (, int256 withdrawAmount_, ) = VAULT.operate(
            nftId,
            amount == type(uint256).max ? type(int256).min : -int256(amount), // withdraw
            int256(0),
            address(this) // withdraw amount should be firstly transferred to this, then unwrap and send to user
        );

        /// @dev as operate returns negative withdraw amount
        WETH.deposit{ value: uint256(-withdrawAmount_) }();
        // transfer withdraw amount to `to`
        SafeTransfer.safeTransfer(address(WETH), to, uint256(-withdrawAmount_));

        emit LogWithdraw(to, nftId, uint256(-withdrawAmount_));
    }

    /// @notice Borrow in USDC from vault, the vault will send ETH to this contract.
    /// @param asset   The asset to borrow
    /// @param amount  Amount of asset to borrow
    /// @param interestRateMode The interest rate mode at which the user wants to borrow, Not used
    /// @param referralCode The code used to register the integrator originating the operation, for potential rewards.NA
    /// @param onBehalfOf The address of the user who will receive the debt.
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external nonReentrant onlyOwner {
        if (amount == 0) revert FluidWethWrapperError(ErrorTypes.WETH__ZeroAmount);
        if (asset != address(BORROW_TOKEN)) revert FluidWethWrapperError(ErrorTypes.Weth_AssetNotSupported);
        if (onBehalfOf != msg.sender) revert FluidWethWrapperError(ErrorTypes.Weth_BorrowNotSupported);

        (, , int256 borrowAmount_) = VAULT.operate(
            nftId,
            int256(0), // supply = 0
            int256(amount), // borrow > 0
            onBehalfOf // borrow to this address
        );

        emit LogBorrow(onBehalfOf, nftId, uint256(borrowAmount_));
    }

    /// @notice Repay debt in USDC to VAULT.
    /// @param asset   The asset to repay (USDC)
    /// @param amount  Amount of asset to repay
    /// @param interestRateMode The interest rate mode at which the user wants to borrow, Not used
    /// @param onBehalfOf should be equal to msg.sender
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external nonReentrant onlyOwner {
        if (amount == 0) revert FluidWethWrapperError(ErrorTypes.WETH__ZeroAmount);
        if (asset != address(BORROW_TOKEN)) revert FluidWethWrapperError(ErrorTypes.Weth_AssetNotSupported);
        if (onBehalfOf != msg.sender) revert FluidWethWrapperError(ErrorTypes.Weth_NotOwner);

        bool isMaxPayback = amount == type(uint256).max;

        if (isMaxPayback) {
            uint256[] memory nftIds_ = new uint256[](1);
            nftIds_[0] = nftId;
            amount = _getPositionBorrow();
        }

        SafeTransfer.safeTransferFrom(BORROW_TOKEN, onBehalfOf, address(this), uint256(amount));
        SafeApprove.safeApprove(BORROW_TOKEN, address(VAULT), amount);

        VAULT.operate(
            nftId,
            int256(0), // no supply
            isMaxPayback ? type(int).min : -int256(amount), // payback < 0
            address(this)
        );

        emit LogPayback(onBehalfOf, nftId, amount);
    }

    /// @notice Accepts NFT transfers only from the configured VAULT.
    ///         Records the `from_` address as the NFT's owner in our mapping,
    ///         so that `from_` can have ownership for withdraw and borrow.
    function onERC721Received(address, address, uint256 tokenId_, bytes calldata) external returns (bytes4) {
        if (msg.sender != address(VAULT_FACTORY)) revert FluidWethWrapperError(ErrorTypes.Weth_NotVaultFactory);

        // For single NFT transer only from vault
        if (nftId != 0) revert FluidWethWrapperError(ErrorTypes.Weth_AlreadyMinted);

        return this.onERC721Received.selector;
    }

    /// @notice                         Spell allows owner aka governance to do any arbitrary call on factory
    /// @param target_                  Address to which the call needs to be delegated
    /// @param data_                    Data to execute at the delegated address
    function spell(address target_, bytes memory data_) external onlyOwner returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    receive() external payable {
        // As we receive funds directly through liquidity layer.
        if (msg.sender != address(LIQUIDITY) && msg.sender != address(WETH))
            revert FluidWethWrapperError(ErrorTypes.Weth_NotLiquidity);
    }

    /// @dev onlyOwner is required as this contract is upgradable
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
