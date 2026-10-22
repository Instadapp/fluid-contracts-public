// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BasicValidations } from "contracts/libraries/utils/basicValidations.sol";
import { LibsErrorTypes } from "contracts/libraries/errorTypes.sol";

import { FluidPauseAuth } from "contracts/config/pauseAuth/main.sol";
import { FluidPauseAuthLiquidity } from "contracts/config/pauseAuth/pauseAuthLiquidity.sol";
import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { IFluidVault } from "contracts/protocols/vault/interfaces/iVault.sol";
import { IFluidVaultT1 } from "contracts/protocols/vault/interfaces/iVaultT1.sol";
import { IFluidDexT1 } from "contracts/protocols/dex/interfaces/iDexT1.sol";
import { IFluidLiquidityAdmin } from "contracts/liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "contracts/libraries/liquiditySlotsLink.sol";

error Access__Unauthorized();

// ==================== Mock contracts ====================

contract MockLiquidity {
    event PauseUserSupplyCalled(address user, address[] tokens, bool pauseSupply, bool pauseWithdraw);
    event PauseUserBorrowCalled(address user, address[] tokens, bool pauseBorrow, bool pausePayback);
    event UnpauseUserSupplyCalled(address user, address[] tokens, bool unpauseSupply, bool unpauseWithdraw);
    event UnpauseUserBorrowCalled(address user, address[] tokens, bool unpauseBorrow, bool unpausePayback);
    event PauseTokenCalled(address[] tokens);
    event UnpauseTokenCalled(address[] tokens);

    mapping(bytes32 => uint256) internal _storage;

    /// @dev Sets the value returned by readFromStorage for a given slot.
    function setStorageValue(bytes32 slot_, uint256 value_) external {
        _storage[slot_] = value_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        return _storage[slot_];
    }

    function _getUserPauseMode(
        uint256 userData_,
        uint256 pauseModeBits_
    ) internal pure returns (bool pausePrimary_, bool pauseSecondary_) {
        require(userData_ != 0, "UserNotDefined");
        uint256 pauseMode_ = (userData_ >> pauseModeBits_) & 3;
        pausePrimary_ =
            pauseMode_ == LiquiditySlotsLink.USER_PAUSE_MODE_ALL ||
            pauseMode_ == LiquiditySlotsLink.USER_PAUSE_MODE_SUPPLY_OR_BORROW;
        pauseSecondary_ =
            pauseMode_ == LiquiditySlotsLink.USER_PAUSE_MODE_ALL ||
            pauseMode_ == LiquiditySlotsLink.USER_PAUSE_MODE_WITHDRAW_OR_PAYBACK;
    }

    function _storeUserPauseMode(
        uint256 userData_,
        bool pausePrimary_,
        bool pauseSecondary_,
        uint256 pauseModeBits_
    ) internal pure returns (uint256) {
        uint256 pauseMode_;
        if (pausePrimary_) {
            pauseMode_ = pauseSecondary_
                ? LiquiditySlotsLink.USER_PAUSE_MODE_ALL
                : LiquiditySlotsLink.USER_PAUSE_MODE_SUPPLY_OR_BORROW;
        } else {
            pauseMode_ = pauseSecondary_
                ? LiquiditySlotsLink.USER_PAUSE_MODE_WITHDRAW_OR_PAYBACK
                : LiquiditySlotsLink.USER_PAUSE_MODE_NONE;
        }

        return (userData_ & ~(uint256(3) << pauseModeBits_)) | (pauseMode_ << pauseModeBits_);
    }

    function _updateUserSupplyPause(
        address user_,
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool isUnpause_
    ) internal returns (bool[] memory actedSupply_, bool[] memory actedWithdraw_) {
        uint256 length_ = tokens_.length;
        actedSupply_ = new bool[](length_);
        actedWithdraw_ = new bool[](length_);

        for (uint256 i; i < length_; i++) {
            bytes32 slot_ = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                user_,
                tokens_[i]
            );
            uint256 userData_ = _storage[slot_];
            (bool currentSupply_, bool currentWithdraw_) = _getUserPauseMode(
                userData_,
                LiquiditySlotsLink.BITS_USER_SUPPLY_PAUSE_MODE
            );

            actedSupply_[i] = pauseSupply_ && currentSupply_ == isUnpause_;
            actedWithdraw_[i] = pauseWithdraw_ && currentWithdraw_ == isUnpause_;

            if (isUnpause_) {
                currentSupply_ = currentSupply_ && !pauseSupply_;
                currentWithdraw_ = currentWithdraw_ && !pauseWithdraw_;
            } else {
                currentSupply_ = currentSupply_ || pauseSupply_;
                currentWithdraw_ = currentWithdraw_ || pauseWithdraw_;
            }

            _storage[slot_] = _storeUserPauseMode(
                userData_,
                currentSupply_,
                currentWithdraw_,
                LiquiditySlotsLink.BITS_USER_SUPPLY_PAUSE_MODE
            );
        }
    }

    function _updateUserBorrowPause(
        address user_,
        address[] calldata tokens_,
        bool pauseBorrow_,
        bool pausePayback_,
        bool isUnpause_
    ) internal returns (bool[] memory actedBorrow_, bool[] memory actedPayback_) {
        uint256 length_ = tokens_.length;
        actedBorrow_ = new bool[](length_);
        actedPayback_ = new bool[](length_);

        for (uint256 i; i < length_; i++) {
            bytes32 slot_ = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
                user_,
                tokens_[i]
            );
            uint256 userData_ = _storage[slot_];
            (bool currentBorrow_, bool currentPayback_) = _getUserPauseMode(
                userData_,
                LiquiditySlotsLink.BITS_USER_BORROW_PAUSE_MODE
            );

            actedBorrow_[i] = pauseBorrow_ && currentBorrow_ == isUnpause_;
            actedPayback_[i] = pausePayback_ && currentPayback_ == isUnpause_;

            if (isUnpause_) {
                currentBorrow_ = currentBorrow_ && !pauseBorrow_;
                currentPayback_ = currentPayback_ && !pausePayback_;
            } else {
                currentBorrow_ = currentBorrow_ || pauseBorrow_;
                currentPayback_ = currentPayback_ || pausePayback_;
            }

            _storage[slot_] = _storeUserPauseMode(
                userData_,
                currentBorrow_,
                currentPayback_,
                LiquiditySlotsLink.BITS_USER_BORROW_PAUSE_MODE
            );
        }
    }

    function _updateSingleTokenPause(
        address token_,
        uint256 requestedPauseMode_,
        bool isUnpause_
    ) internal returns (bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            token_
        );
        uint256 exchangePricesAndConfig_ = _storage[slot_];
        uint256 pauseMode_ = (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_PAUSE_MODE) & 15;

        actedSupply_ =
            (requestedPauseMode_ & LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_SUPPLY != 0) &&
            (((pauseMode_ & LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_SUPPLY) != 0) == isUnpause_);
        actedWithdraw_ =
            (requestedPauseMode_ & LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_WITHDRAW != 0) &&
            (((pauseMode_ & LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_WITHDRAW) != 0) == isUnpause_);
        actedBorrow_ =
            (requestedPauseMode_ & LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_BORROW != 0) &&
            (((pauseMode_ & LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_BORROW) != 0) == isUnpause_);
        actedPayback_ =
            (requestedPauseMode_ & LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_PAYBACK != 0) &&
            (((pauseMode_ & LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_PAYBACK) != 0) == isUnpause_);

        pauseMode_ = isUnpause_ ? pauseMode_ & ~requestedPauseMode_ : pauseMode_ | requestedPauseMode_;
        _storage[slot_] =
            (exchangePricesAndConfig_ & ~(uint256(15) << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_PAUSE_MODE)) |
            (pauseMode_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_PAUSE_MODE);
    }

    function _updateTokenPause(
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_,
        bool isUnpause_
    )
        internal
        returns (
            bool[] memory actedSupply_,
            bool[] memory actedWithdraw_,
            bool[] memory actedBorrow_,
            bool[] memory actedPayback_
        )
    {
        uint256 length_ = tokens_.length;
        actedSupply_ = new bool[](length_);
        actedWithdraw_ = new bool[](length_);
        actedBorrow_ = new bool[](length_);
        actedPayback_ = new bool[](length_);

        uint256 requestedPauseMode_ = (pauseSupply_ ? LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_SUPPLY : 0) |
            (pauseWithdraw_ ? LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_WITHDRAW : 0) |
            (pauseBorrow_ ? LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_BORROW : 0) |
            (pausePayback_ ? LiquiditySlotsLink.EXCHANGE_PRICES_PAUSE_MODE_PAYBACK : 0);

        for (uint256 i; i < length_; i++) {
            (actedSupply_[i], actedWithdraw_[i], actedBorrow_[i], actedPayback_[i]) = _updateSingleTokenPause(
                tokens_[i],
                requestedPauseMode_,
                isUnpause_
            );
        }
    }

    function pauseUserSupply(
        address user_,
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_
    ) external returns (bool[] memory actedSupply_, bool[] memory actedWithdraw_) {
        emit PauseUserSupplyCalled(user_, tokens_, pauseSupply_, pauseWithdraw_);
        return _updateUserSupplyPause(user_, tokens_, pauseSupply_, pauseWithdraw_, false);
    }

    function pauseUserBorrow(
        address user_,
        address[] calldata tokens_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external returns (bool[] memory actedBorrow_, bool[] memory actedPayback_) {
        emit PauseUserBorrowCalled(user_, tokens_, pauseBorrow_, pausePayback_);
        return _updateUserBorrowPause(user_, tokens_, pauseBorrow_, pausePayback_, false);
    }

    function unpauseUserSupply(
        address user_,
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_
    ) external returns (bool[] memory actedSupply_, bool[] memory actedWithdraw_) {
        emit UnpauseUserSupplyCalled(user_, tokens_, unpauseSupply_, unpauseWithdraw_);
        return _updateUserSupplyPause(user_, tokens_, unpauseSupply_, unpauseWithdraw_, true);
    }

    function unpauseUserBorrow(
        address user_,
        address[] calldata tokens_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external returns (bool[] memory actedBorrow_, bool[] memory actedPayback_) {
        emit UnpauseUserBorrowCalled(user_, tokens_, unpauseBorrow_, unpausePayback_);
        return _updateUserBorrowPause(user_, tokens_, unpauseBorrow_, unpausePayback_, true);
    }

    function pauseTokens(
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    )
        external
        returns (
            bool[] memory actedSupply_,
            bool[] memory actedWithdraw_,
            bool[] memory actedBorrow_,
            bool[] memory actedPayback_
        )
    {
        emit PauseTokenCalled(tokens_);
        return _updateTokenPause(tokens_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_, false);
    }

    function unpauseTokens(
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    )
        external
        returns (
            bool[] memory actedSupply_,
            bool[] memory actedWithdraw_,
            bool[] memory actedBorrow_,
            bool[] memory actedPayback_
        )
    {
        emit UnpauseTokenCalled(tokens_);
        return _updateTokenPause(tokens_, unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_, true);
    }
}

contract MockVaultFactory {
    mapping(uint256 => address) internal _vaults;
    mapping(address => bool) internal _isVault;

    function setVault(uint256 vaultId_, address vault_) external {
        _vaults[vaultId_] = vault_;
        _isVault[vault_] = vault_.code.length > 0;
    }

    function getVaultAddress(uint256 vaultId_) external view returns (address) {
        return _vaults[vaultId_];
    }

    function isVault(address vault_) external view returns (bool) {
        return _isVault[vault_];
    }
}

contract MockDexFactory {
    mapping(uint256 => address) internal _dexes;
    mapping(address => bool) internal _isDex;

    function setDex(uint256 dexId_, address dex_) external {
        _dexes[dexId_] = dex_;
        _isDex[dex_] = dex_.code.length > 0;
    }

    function getDexAddress(uint256 dexId_) external view returns (address) {
        return _dexes[dexId_];
    }

    function isDex(address dex_) external view returns (bool) {
        return _isDex[dex_];
    }
}

/// @dev Mock T1 vault. Does NOT implement TYPE() — mirrors real T1 vaults.
contract MockVaultT1 {
    address public immutable SUPPLY_TOKEN;
    address public immutable BORROW_TOKEN;

    constructor(address supplyToken_, address borrowToken_) {
        SUPPLY_TOKEN = supplyToken_;
        BORROW_TOKEN = borrowToken_;
    }

    function constantsView()
        external
        view
        returns (
            address liquidity,
            address factory,
            address adminImplementation,
            address secondaryImplementation,
            address supplyToken,
            address borrowToken,
            uint8 supplyDecimals,
            uint8 borrowDecimals,
            uint256 vaultId,
            bytes32 liquiditySupplyExchangePriceSlot,
            bytes32 liquidityBorrowExchangePriceSlot,
            bytes32 liquidityUserSupplySlot,
            bytes32 liquidityUserBorrowSlot
        )
    {
        return (
            address(0),
            address(0),
            address(0),
            address(0),
            SUPPLY_TOKEN,
            BORROW_TOKEN,
            18,
            18,
            1,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            bytes32(0)
        );
    }
}

/// @dev Mock newer vault that implements TYPE() but reverts on constantsView().
contract MockVaultNewerReverting {
    function TYPE() external pure returns (uint256) {
        return 20000;
    }

    function constantsView() external pure {
        revert("mock newer vault revert");
    }
}

/// @dev Mock newer vault (T2+). Implements TYPE() returning 20000 (VAULT_T2_SMART_COL_TYPE).
contract MockVaultNewer {
    address public immutable LIQUIDITY_ADDR;
    address public immutable SUPPLY_ADDR;
    address public immutable BORROW_ADDR;
    address public immutable SUPPLY_TOKEN0;
    address public immutable SUPPLY_TOKEN1;
    address public immutable BORROW_TOKEN0;
    address public immutable BORROW_TOKEN1;

    constructor(
        address liquidity_,
        address supply_,
        address borrow_,
        address supplyToken0_,
        address supplyToken1_,
        address borrowToken0_,
        address borrowToken1_
    ) {
        LIQUIDITY_ADDR = liquidity_;
        SUPPLY_ADDR = supply_;
        BORROW_ADDR = borrow_;
        SUPPLY_TOKEN0 = supplyToken0_;
        SUPPLY_TOKEN1 = supplyToken1_;
        BORROW_TOKEN0 = borrowToken0_;
        BORROW_TOKEN1 = borrowToken1_;
    }

    function TYPE() external pure returns (uint256) {
        return 20000;
    }

    function constantsView() external view returns (IFluidVault.ConstantViews memory cv_) {
        cv_.liquidity = LIQUIDITY_ADDR;
        cv_.supply = SUPPLY_ADDR;
        cv_.borrow = BORROW_ADDR;
        cv_.supplyToken = IFluidVault.Tokens(SUPPLY_TOKEN0, SUPPLY_TOKEN1);
        cv_.borrowToken = IFluidVault.Tokens(BORROW_TOKEN0, BORROW_TOKEN1);
        cv_.vaultId = 2;
        cv_.vaultType = 2;
    }
}

contract MockRevertingVault {
    function constantsView() external pure {
        revert("mock revert");
    }
}

contract MockDex {
    address public immutable TOKEN0;
    address public immutable TOKEN1;

    uint256 public dexVariables2;

    constructor(address token0_, address token1_, uint256 dexVariables2_) {
        TOKEN0 = token0_;
        TOKEN1 = token1_;
        dexVariables2 = dexVariables2_;
    }

    function setDexVariables2(uint256 dexVariables2_) external {
        dexVariables2 = dexVariables2_;
    }

    function constantsView() external view returns (IFluidDexT1.ConstantViews memory cv_) {
        cv_.token0 = TOKEN0;
        cv_.token1 = TOKEN1;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        if (uint256(slot_) == 1) return dexVariables2;
        return 0;
    }
}

contract MockPauseAuthDex {
    event PauseVaultCalled(uint256 vaultId, bool pauseSupply, bool pauseWithdraw, bool pauseBorrow, bool pausePayback);
    event UnpauseVaultCalled(
        uint256 vaultId,
        bool unpauseSupply,
        bool unpauseWithdraw,
        bool unpauseBorrow,
        bool unpausePayback
    );
    event PauseSwapAndArbitrageCalled(uint256 dexId);
    event UnpauseSwapAndArbitrageCalled(uint256 dexId);
    event PauseSmartLendingCalled(uint256 dexId);
    event UnpauseSmartLendingCalled(uint256 dexId);
    event PauseUserCalled(
        uint256 dexId,
        address user,
        bool pauseSupply,
        bool pauseWithdraw,
        bool pauseBorrow,
        bool pausePayback
    );
    event UnpauseUserCalled(
        uint256 dexId,
        address user,
        bool unpauseSupply,
        bool unpauseWithdraw,
        bool unpauseBorrow,
        bool unpausePayback
    );

    address internal _swapDexResult;
    bool internal _swapActed;
    address internal _smartLendingDexResult;
    address internal _smartLendingResult;
    bool internal _smartLendingActedSupply;
    bool internal _smartLendingActedWithdraw;
    address internal _userDexResult;
    bool internal _revertPartialSide;
    address internal _pauseVaultDexResult;
    bool internal _pauseVaultActedSupply;
    bool internal _pauseVaultActedWithdraw;
    bool internal _pauseVaultActedBorrow;
    bool internal _pauseVaultActedPayback;

    /// @dev vault and user entry points revert like the real executor on supply/withdraw alone or payback alone
    function setRevertPartialSide(bool revert_) external {
        _revertPartialSide = revert_;
    }

    function setSwapResult(address dex_, bool acted_) external {
        _swapDexResult = dex_;
        _swapActed = acted_;
    }

    function setSmartLendingResult(
        address dex_,
        address smartLending_,
        bool actedSupply_,
        bool actedWithdraw_
    ) external {
        _smartLendingDexResult = dex_;
        _smartLendingResult = smartLending_;
        _smartLendingActedSupply = actedSupply_;
        _smartLendingActedWithdraw = actedWithdraw_;
    }

    function setUserResult(address dex_) external {
        _userDexResult = dex_;
    }

    function setPauseVaultResult(
        address dex_,
        bool actedSupply_,
        bool actedWithdraw_,
        bool actedBorrow_,
        bool actedPayback_
    ) external {
        _pauseVaultDexResult = dex_;
        _pauseVaultActedSupply = actedSupply_;
        _pauseVaultActedWithdraw = actedWithdraw_;
        _pauseVaultActedBorrow = actedBorrow_;
        _pauseVaultActedPayback = actedPayback_;
    }

    function pauseVault(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external returns (address, bool, bool, bool, bool) {
        emit PauseVaultCalled(vaultId_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
        _revertIfPartialSideMode(pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
        return (
            _pauseVaultDexResult,
            _pauseVaultActedSupply,
            _pauseVaultActedWithdraw,
            _pauseVaultActedBorrow,
            _pauseVaultActedPayback
        );
    }

    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external returns (address, bool, bool, bool, bool) {
        emit UnpauseVaultCalled(vaultId_, unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_);
        _revertIfPartialSideMode(unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_);
        return (
            _pauseVaultDexResult,
            _pauseVaultActedSupply,
            _pauseVaultActedWithdraw,
            _pauseVaultActedBorrow,
            _pauseVaultActedPayback
        );
    }

    function _revertIfPartialSideMode(bool supply_, bool withdraw_, bool borrow_, bool payback_) internal view {
        if (_revertPartialSide && (supply_ != withdraw_ || (payback_ && !borrow_))) {
            revert Error.FluidConfigError(ErrorTypes.PauseAuthDex__PartialSideNotSupported);
        }
    }

    function pauseSwapAndArbitrage(uint256 dexId_) external returns (address, bool) {
        emit PauseSwapAndArbitrageCalled(dexId_);
        return (_swapDexResult, _swapActed);
    }

    function unpauseSwapAndArbitrage(uint256 dexId_) external returns (address, bool) {
        emit UnpauseSwapAndArbitrageCalled(dexId_);
        return (_swapDexResult, _swapActed);
    }

    function pauseSmartLending(
        uint256 dexId_,
        bool,
        bool
    ) external returns (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) {
        emit PauseSmartLendingCalled(dexId_);
        dex_ = _smartLendingDexResult;
        smartLending_ = _smartLendingResult;
        actedSupply_ = _smartLendingActedSupply;
        actedWithdraw_ = _smartLendingActedWithdraw;
    }

    function unpauseSmartLending(
        uint256 dexId_,
        bool,
        bool
    ) external returns (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) {
        emit UnpauseSmartLendingCalled(dexId_);
        dex_ = _smartLendingDexResult;
        smartLending_ = _smartLendingResult;
        actedSupply_ = _smartLendingActedSupply;
        actedWithdraw_ = _smartLendingActedWithdraw;
    }

    function pauseUser(
        uint256 dexId_,
        address user_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external returns (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) {
        emit PauseUserCalled(dexId_, user_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
        _revertIfPartialSideMode(pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
        dex_ = _userDexResult;
        actedSupply_ = pauseSupply_;
        actedWithdraw_ = pauseWithdraw_;
        actedBorrow_ = pauseBorrow_;
        actedPayback_ = pausePayback_;
    }

    function unpauseUser(
        uint256 dexId_,
        address user_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external returns (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) {
        emit UnpauseUserCalled(dexId_, user_, unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_);
        _revertIfPartialSideMode(unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_);
        dex_ = _userDexResult;
        actedSupply_ = unpauseSupply_;
        actedWithdraw_ = unpauseWithdraw_;
        actedBorrow_ = unpauseBorrow_;
        actedPayback_ = unpausePayback_;
    }
}

// ==================== Tests ====================

// To test run:
// forge test -vvv --match-path test/foundry/config/pauseAuth.t.sol
contract PauseAuthTest is Test {
    FluidPauseAuth public pauseAuth;

    MockLiquidity public mockLiquidity;
    MockVaultFactory public mockVaultFactory;
    MockDexFactory public mockDexFactory;
    FluidPauseAuthLiquidity public mockPauseAuthLiquidity;
    MockPauseAuthDex public mockPauseAuthDex;
    address internal pauseAuthOracleV2;

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    address public authGate;

    address public class1Auth = makeAddr("class1Auth");
    address public class2Auth = makeAddr("class2Auth");
    address public class3Auth = makeAddr("class3Auth");
    address public unauthorizedUser = makeAddr("unauthorizedUser");

    address public constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant WSTETH = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    MockVaultT1 public mockVaultT1;
    MockVaultNewer public mockVaultNewer;
    MockVaultNewer public mockVaultNewerDexBacked;
    MockRevertingVault public mockRevertingVault;
    MockVaultNewerReverting public mockVaultNewerReverting;
    MockDex public mockDex;

    uint256 public constant VAULT_T1_ID = 1;
    uint256 public constant VAULT_NEWER_ID = 2;
    uint256 public constant VAULT_DEX_BACKED_ID = 3;
    uint256 public constant VAULT_REVERTING_ID = 4;
    uint256 public constant VAULT_NEWER_REVERTING_ID = 5;
    uint256 public constant DEX_ID = 1;
    uint256 public constant UNREGISTERED_VAULT_ID = 999;
    uint256 public constant UNREGISTERED_DEX_ID = 998;

    // Events from FluidPauseAuth
    event LogPauseVault(
        uint256 indexed vaultId,
        address vault,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseVault(
        uint256 indexed vaultId,
        address vault,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );
    event LogPauseDex(
        uint256 indexed dexId,
        address dex,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseDex(
        uint256 indexed dexId,
        address dex,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );
    event LogPauseUser(
        address indexed user,
        address indexed token,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseUser(
        address indexed user,
        address indexed token,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );
    event LogPauseToken(
        address indexed token,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseToken(
        address indexed token,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );
    event LogSetPauseAuth(address indexed pauseAuth, uint256 authClass);
    event LogSetNotPausableVaultId(uint256 indexed vaultId, bool notPausable);
    event LogSetNotPausableDexId(uint256 indexed dexId, bool notPausable);
    event LogSkipVaultUserClass(uint256 indexed vaultId, address vault, uint256 userClass);
    event LogSkipDexUserClass(uint256 indexed dexId, address dex, uint256 userClass);
    event LogSkipTokenNotPausable(address indexed token);
    event LogSetNotPausableToken(address indexed token, bool notPausable);
    event LogPauseSwapAndArbitrage(uint256 indexed dexId, address dex);
    event LogUnpauseSwapAndArbitrage(uint256 indexed dexId, address dex);
    event LogPauseSmartLending(
        uint256 indexed dexId,
        address dex,
        address smartLending,
        bool pausedSupply,
        bool pausedWithdraw
    );
    event LogUnpauseSmartLending(
        uint256 indexed dexId,
        address dex,
        address smartLending,
        bool unpausedSupply,
        bool unpausedWithdraw
    );
    event LogPauseDexUser(
        uint256 indexed dexId,
        address dex,
        address user,
        bool pauseSupply,
        bool pauseWithdraw,
        bool pauseBorrow,
        bool pausePayback
    );
    event LogUnpauseDexUser(
        uint256 indexed dexId,
        address dex,
        address user,
        bool unpauseSupply,
        bool unpauseWithdraw,
        bool unpauseBorrow,
        bool unpausePayback
    );

    // Events from MockPauseAuthDex
    event PauseVaultCalled(uint256 vaultId, bool pauseSupply, bool pauseWithdraw, bool pauseBorrow, bool pausePayback);
    event UnpauseVaultCalled(
        uint256 vaultId,
        bool unpauseSupply,
        bool unpauseWithdraw,
        bool unpauseBorrow,
        bool unpausePayback
    );

    function setUp() public {
        mockLiquidity = new MockLiquidity();
        mockVaultFactory = new MockVaultFactory();
        mockDexFactory = new MockDexFactory();
        authGate = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(address(mockLiquidity), TEAM_MULTISIG, TEAM_MULTISIG2, makeAddr("teamTimelock"))
        );
        mockPauseAuthLiquidity = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            authGate
        );
        mockPauseAuthDex = new MockPauseAuthDex();
        pauseAuthOracleV2 = makeAddr("pauseAuthOracleV2");

        pauseAuth = new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex),
            pauseAuthOracleV2,
            authGate
        );

        vm.prank(TEAM_MULTISIG);
        mockPauseAuthLiquidity.setPauseAuthContract(address(pauseAuth));

        // Deploy mock vaults and DEX
        mockVaultT1 = new MockVaultT1(USDC, WETH);
        mockVaultNewer = new MockVaultNewer(
            address(mockLiquidity), // liquidity
            address(mockLiquidity), // supply via liquidity
            address(mockLiquidity), // borrow via liquidity
            WSTETH,
            DAI, // supply tokens (smart collateral: 2 tokens)
            WETH,
            address(0) // borrow token (single)
        );
        address mockDexAddr = makeAddr("mockDexAddr");
        mockVaultNewerDexBacked = new MockVaultNewer(
            address(mockLiquidity), // liquidity
            mockDexAddr, // supply via DEX (not liquidity)
            address(mockLiquidity), // borrow via liquidity
            WSTETH,
            WETH, // supply tokens (won't be included since supply is DEX)
            USDC,
            address(0) // borrow token
        );
        mockRevertingVault = new MockRevertingVault();
        mockVaultNewerReverting = new MockVaultNewerReverting();
        mockDex = new MockDex(WSTETH, WETH, 3);

        // Register in factories
        mockVaultFactory.setVault(VAULT_T1_ID, address(mockVaultT1));
        mockVaultFactory.setVault(VAULT_NEWER_ID, address(mockVaultNewer));
        mockVaultFactory.setVault(VAULT_DEX_BACKED_ID, address(mockVaultNewerDexBacked));
        mockVaultFactory.setVault(VAULT_REVERTING_ID, address(mockRevertingVault));
        mockVaultFactory.setVault(VAULT_NEWER_REVERTING_ID, address(mockVaultNewerReverting));
        mockDexFactory.setDex(DEX_ID, address(mockDex));

        // Set up mock LL storage: mark user supply/borrow data as defined (non-zero) for all vault/dex + token combos.
        // Value 1 means defined and not paused (bit 255 = 0).
        _setUserData(address(mockVaultT1), USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultNewer), WSTETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultNewer), DAI, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultNewer), WETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultNewerDexBacked), USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockDex), WSTETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockDex), WETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
    }

    /// @dev Sets mock LL storage for a user+token supply and borrow data.
    function _setUserData(address user_, address token_, uint256 supplyData_, uint256 borrowData_) internal {
        bytes32 supplySlot_ = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            user_,
            token_
        );
        bytes32 borrowSlot_ = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            user_,
            token_
        );
        mockLiquidity.setStorageValue(supplySlot_, supplyData_);
        mockLiquidity.setStorageValue(borrowSlot_, borrowData_);
    }

    uint256 constant DEFINED_NOT_PAUSED = 1;
    uint256 constant DEFINED_AND_PAUSED = 1 | (uint256(1) << 255);

    /// @dev Sets mock LL state for all registered user/token pairs to "paused" (bit 255 set).
    function _setAllTokensPausedAtLL() internal {
        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultNewer), WSTETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultNewer), DAI, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultNewer), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultNewerDexBacked), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockDex), WSTETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockDex), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
    }

    function _boolArray(uint256 length_, bool value_) internal pure returns (bool[] memory arr_) {
        arr_ = new bool[](length_);
        for (uint256 i; i < length_; i++) {
            arr_[i] = value_;
        }
    }

    /// @dev Sets mock LL storage for user class (0 = new protocol, 1 = established/not pausable by guardians).
    function _setUserClass(address user_, uint256 class_) internal {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_CLASS_MAPPING_SLOT,
            user_
        );
        mockLiquidity.setStorageValue(slot_, class_);
    }

    /// @dev `vm.expectEmit` cannot assert absence. The non-empty check keeps a silently skipped
    ///      routing step from passing as "event not emitted".
    function _assertNotLogged(bytes32 topic0_) internal {
        Vm.Log[] memory logs_ = vm.getRecordedLogs();
        assertGt(logs_.length, 0);
        for (uint256 i; i < logs_.length; i++) {
            assertTrue(logs_[i].topics.length == 0 || logs_[i].topics[0] != topic0_);
        }
    }

    /// @dev Sets the LL exchangePricesAndConfig for a token so it appears paused or unpaused.
    function _setTokenPauseState(address token_, bool paused_) internal {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            token_
        );
        uint256 value_ = paused_ ? uint256(15) << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_PAUSE_MODE : uint256(0);
        mockLiquidity.setStorageValue(slot_, value_);
    }

    // ==================== Constructor tests ====================

    function test_deployment() public view {
        assertEq(address(pauseAuth.LIQUIDITY()), address(mockLiquidity));
        assertEq(address(pauseAuth.VAULT_FACTORY()), address(mockVaultFactory));
        assertEq(address(pauseAuth.DEX_FACTORY()), address(mockDexFactory));
        assertEq(address(pauseAuth.PAUSE_AUTH_LIQUIDITY()), address(mockPauseAuthLiquidity));
        assertEq(address(pauseAuth.PAUSE_AUTH_DEX()), address(mockPauseAuthDex));
        assertEq(address(pauseAuth.AUTH_GATE()), authGate);
    }

    function test_constructor_revertZeroLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuth(
            address(0),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex),
            pauseAuthOracleV2,
            authGate
        );
    }

    function test_constructor_revertZeroVaultFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuth(
            address(mockLiquidity),
            address(0),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex),
            pauseAuthOracleV2,
            authGate
        );
    }

    function test_constructor_revertZeroDexFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(0),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex),
            pauseAuthOracleV2,
            authGate
        );
    }

    function test_constructor_revertZeroPauseAuthLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(0),
            address(mockPauseAuthDex),
            pauseAuthOracleV2,
            authGate
        );
    }

    function test_constructor_revertZeroPauseAuthDex() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(0),
            pauseAuthOracleV2,
            authGate
        );
    }

    function test_constructor_revertZeroPauseAuthOracleV2() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex),
            address(0),
            authGate
        );
    }

    function test_constructor_RevertIfAuthGateForOtherLiquidity() public {
        address otherLiquidity_ = makeAddr("otherLiquidity");
        address otherAuthGate_ = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(otherLiquidity_, TEAM_MULTISIG, TEAM_MULTISIG2, makeAddr("teamTimelock"))
        );

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex),
            pauseAuthOracleV2,
            otherAuthGate_
        );
    }

    // ==================== Admin: setPauseAuth ====================

    function test_setPauseAuth_class1() public {
        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuth(class1Auth, 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        assertEq(pauseAuth.pauseAuths(class1Auth), 1);
    }

    function test_setPauseAuth_class2() public {
        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuth(class2Auth, 2);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        assertEq(pauseAuth.pauseAuths(class2Auth), 2);
    }

    function test_setPauseAuth_class3() public {
        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuth(class3Auth, 3);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        assertEq(pauseAuth.pauseAuths(class3Auth), 3);
    }

    function test_setPauseAuth_removeAuth() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        assertEq(pauseAuth.pauseAuths(class1Auth), 1);

        pauseAuth.setPauseAuth(class1Auth, 0);
        assertEq(pauseAuth.pauseAuths(class1Auth), 0);
        vm.stopPrank();
    }

    function test_setPauseAuth_revertInvalidClass() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.setPauseAuth(class1Auth, 4);
    }

    function test_setPauseAuth_revertNotMultisig() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.setPauseAuth(class1Auth, 1);
    }

    function test_setPauseAuth_revertZeroAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        pauseAuth.setPauseAuth(address(0), 1);
    }

    // ==================== Admin: setNotPausableVaultId ====================

    function test_setNotPausableVaultId() public {
        vm.expectEmit(true, false, false, true);
        emit LogSetNotPausableVaultId(VAULT_T1_ID, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        assertTrue(pauseAuth.notPausableVaultIds(VAULT_T1_ID));
    }

    function test_setNotPausableVaultId_revertNotMultisig() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);
    }

    function test_setNotPausableVaultId_revertInvalidVaultId() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.setNotPausableVaultId(UNREGISTERED_VAULT_ID, true);
    }

    // ==================== Admin: setNotPausableDexId ====================

    function test_setNotPausableDexId() public {
        vm.expectEmit(true, false, false, true);
        emit LogSetNotPausableDexId(DEX_ID, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableDexId(DEX_ID, true);

        assertTrue(pauseAuth.notPausableDexIds(DEX_ID));
    }

    function test_setNotPausableDexId_revertNotMultisig() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.setNotPausableDexId(DEX_ID, true);
    }

    function test_setNotPausableDexId_revertInvalidDexId() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.setNotPausableDexId(UNREGISTERED_DEX_ID, true);
    }

    // ==================== removeClass1PauseAuth ====================

    function test_removeClass1PauseAuth_byClass3() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setPauseAuth(class3Auth, 3);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuth(class1Auth, 0);

        vm.prank(class3Auth);
        pauseAuth.removeClass1PauseAuth(class1Auth);

        assertEq(pauseAuth.pauseAuths(class1Auth), 0);
    }

    function test_removeClass1PauseAuth_byMultisig() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuth(class1Auth, 0);

        pauseAuth.removeClass1PauseAuth(class1Auth);
        vm.stopPrank();

        assertEq(pauseAuth.pauseAuths(class1Auth), 0);
    }

    function test_removeClass1PauseAuth_revertNotClass2() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setPauseAuth(class2Auth, 2);
        vm.stopPrank();

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.removeClass1PauseAuth(class1Auth);
    }

    function test_removeClass1PauseAuth_revertClass1CannotRemove() public {
        address class1Auth2 = makeAddr("class1Auth2");
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setPauseAuth(class1Auth2, 1);
        vm.stopPrank();

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.removeClass1PauseAuth(class1Auth2);
    }

    function test_removeClass1PauseAuth_revertTargetNotClass1() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
        pauseAuth.setPauseAuth(class3Auth, 3);
        vm.stopPrank();

        vm.prank(class3Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.removeClass1PauseAuth(class2Auth);
    }

    function test_removeClass1PauseAuth_revertZeroAddress() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);
        vm.stopPrank();

        vm.prank(class3Auth);
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        pauseAuth.removeClass1PauseAuth(address(0));
    }

    // ==================== Class separation tests ====================

    function test_class1_canPause() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);
    }

    function test_class1_cannotPauseSupply() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, false, false, false);
    }

    function test_class1_canPauseSwapAndArbitrage() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, false, false, false, false, true);
    }

    function test_class1_cannotUnpause() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_class2_canPause() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        vm.prank(class2Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_class2_cannotUnpause() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_class3_canUnpause() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        vm.prank(class3Auth);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_multisig2_canPauseAsImplicitLevel2() public {
        vm.prank(TEAM_MULTISIG2);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_multisig2_cannotUnpause() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG2);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_multisig2_cannotAdmin() public {
        vm.prank(TEAM_MULTISIG2);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.setPauseAuth(class1Auth, 1);
    }

    function test_multisig2_respectsNotPausable() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        vm.prank(TEAM_MULTISIG2);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_teamTimelock_canAdminAndUnpause() public {
        address teamTimelock_ = makeAddr("teamTimelock");
        _setAllTokensPausedAtLL();

        vm.prank(teamTimelock_);
        pauseAuth.setPauseAuth(class1Auth, 1);
        assertEq(pauseAuth.pauseAuths(class1Auth), 1);

        vm.prank(teamTimelock_);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_teamTimelock_bypassesNotPausable() public {
        address teamTimelock_ = makeAddr("teamTimelock");

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        vm.prank(teamTimelock_);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_multisig_canUnpauseAsImplicitLevel3() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_class1_canPauseDex() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, false, false, true, false, false);
    }

    function test_class1_cannotUnpauseDex() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_class3_canUnpauseDex() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        vm.prank(class3Auth);
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    // ==================== pauseVault ====================

    function test_pauseVault_multisig_T1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_multisig_newerVault() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_NEWER_ID, true, true, true, true);
    }

    function test_pauseVault_multisig_dexBackedVault() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);
    }

    function test_pauseVault_class1Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);
    }

    /// @dev level 1's borrow-only shape is a limits freeze on DEX legs, so the bot's batch may carry T3/T4
    function test_pauseVault_class1Auth_borrowOnlyReachesDexLeg() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        mockPauseAuthDex.setRevertPartialSide(true);

        vm.expectEmit(true, true, true, true, address(mockPauseAuthDex));
        emit PauseVaultCalled(VAULT_NEWER_ID, false, false, true, false);
        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_NEWER_ID, false, false, true, false);
    }

    /// @dev the DEX leg runs after the Liquidity leg, so its revert must unwind the Liquidity pause too
    function test_pauseVault_dexLegRevertRollsBackLiquidityLeg() public {
        bytes32 borrowSlot_ = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            address(mockVaultNewer),
            WETH
        );
        assertEq(mockLiquidity.readFromStorage(borrowSlot_), DEFINED_NOT_PAUSED);

        mockPauseAuthDex.setRevertPartialSide(true);

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuth.pauseVault(VAULT_NEWER_ID, false, false, false, true);

        assertEq(mockLiquidity.readFromStorage(borrowSlot_), DEFINED_NOT_PAUSED);

        // without the DEX leg reverting the same call does pause, so the assert above is not vacuous
        mockPauseAuthDex.setRevertPartialSide(false);
        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_NEWER_ID, false, false, false, true);
        assertTrue(mockLiquidity.readFromStorage(borrowSlot_) != DEFINED_NOT_PAUSED);
    }

    function test_pauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_revertNotPauseAuth() public {
        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);
        vm.stopPrank();

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_revertZeroVaultAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVault(UNREGISTERED_VAULT_ID, true, true, true, true);
    }

    function test_pauseVault_T1_callsLiquidityCorrectly() public {
        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockVaultT1), expectedSupply, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockVaultT1), expectedBorrow, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_newer_callsLiquidityCorrectly() public {
        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = DAI;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockVaultNewer), expectedSupply, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockVaultNewer), expectedBorrow, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_NEWER_ID, true, true, true, true);
    }

    function test_pauseVault_dexBacked_excludesDexTokens() public {
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.pauseUserBorrow,
                (address(mockVaultNewerDexBacked), expectedBorrow, true, true)
            )
        );

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseVault, (VAULT_DEX_BACKED_ID, true, true, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);
    }

    function test_pauseVault_anyClassCanCall() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setPauseAuth(class2Auth, 2);
        pauseAuth.setPauseAuth(class3Auth, 3);
        vm.stopPrank();

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);

        vm.prank(class2Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);

        vm.prank(class3Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_onlySupply() public {
        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockVaultT1), expectedSupply, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, false, false);
    }

    function test_pauseVault_onlyBorrow() public {
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockVaultT1), expectedBorrow, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, true);
    }

    function test_pauseVault_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, false, false);
    }

    function test_pauseVault_dexBacked_supplyOnlyCallsPauseAuthDex() public {
        // Supply is on DEX, borrow is on LL. Pausing supply only → no LL call, only PAUSE_AUTH_DEX call.
        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseVault, (VAULT_DEX_BACKED_ID, true, true, false, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true, false, false);
    }

    // ==================== unpauseVault ====================

    function test_unpauseVault_multisig() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(mockVaultT1), expectedSupply, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (address(mockVaultT1), expectedBorrow, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseVault(VAULT_T1_ID, address(mockVaultT1), true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_unpauseVault_class3Auth() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        vm.prank(class3Auth);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_unpauseVault_revertClass1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_unpauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_unpauseVault_revertZeroVaultAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVault(UNREGISTERED_VAULT_ID, true, true, true, true);
    }

    function test_unpauseVault_newer_callsLiquidityCorrectly() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = DAI;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.unpauseUserSupply,
                (address(mockVaultNewer), expectedSupply, true, true)
            )
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.unpauseUserBorrow,
                (address(mockVaultNewer), expectedBorrow, true, true)
            )
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_NEWER_ID, true, true, true, true);
    }

    function test_unpauseVault_dexBacked_excludesDexTokens() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.unpauseUserBorrow,
                (address(mockVaultNewerDexBacked), expectedBorrow, true, true)
            )
        );

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.unpauseVault, (VAULT_DEX_BACKED_ID, true, true, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);
    }

    function test_unpauseVault_onlySupply() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(mockVaultT1), expectedSupply, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, false, false);
    }

    function test_unpauseVault_onlyBorrow() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (address(mockVaultT1), expectedBorrow, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, false, false, true, true);
    }

    function test_unpauseVault_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVault(VAULT_T1_ID, false, false, false, false);
    }

    function test_unpauseVault_dexBacked_supplyOnlyCallsPauseAuthDex() public {
        // Supply is on DEX, borrow is on LL. Unpausing supply only → no LL call, only PAUSE_AUTH_DEX call.
        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.unpauseVault, (VAULT_DEX_BACKED_ID, true, true, false, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_DEX_BACKED_ID, true, true, false, false);
    }

    function test_unpauseVault_revertInvalidVaultConstants() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVault(VAULT_REVERTING_ID, true, true, true, true);
    }

    // ==================== pauseDex ====================

    function test_pauseDex_multisig() public {
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), expectedTokens, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), expectedTokens, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(DEX_ID, address(mockDex), true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_class1Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, false, false, true, false, false);
    }

    function test_pauseDex_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableDexId(DEX_ID, true);
        vm.stopPrank();

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseDex(DEX_ID, false, false, true, false, false);
    }

    function test_pauseDex_revertZeroDexAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseDex(UNREGISTERED_DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_onlySmartCol() public {
        mockDex.setDexVariables2(1);

        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), expectedSupply, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_onlySmartDebt() public {
        mockDex.setDexVariables2(2);

        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), expectedBorrow, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_neitherSmartColNorDebt() public {
        mockDex.setDexVariables2(0);

        vm.expectCall(address(mockLiquidity), abi.encodeWithSelector(IFluidLiquidityAdmin.pauseUserSupply.selector), 0);
        vm.expectCall(address(mockLiquidity), abi.encodeWithSelector(IFluidLiquidityAdmin.pauseUserBorrow.selector), 0);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_filterSupplyOnly() public {
        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), expectedSupply, true, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, false, false, false, false);
    }

    function test_pauseDex_filterBorrowOnly() public {
        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), expectedBorrow, true, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, false, false, true, false, false);
    }

    function test_pauseDex_swapAndArbitrage_forwardsToDexModule() public {
        mockPauseAuthDex.setSwapResult(address(mockDex), true);

        vm.expectCall(address(mockPauseAuthDex), abi.encodeCall(MockPauseAuthDex.pauseSwapAndArbitrage, (DEX_ID)));

        vm.expectEmit(true, false, false, true);
        emit LogPauseSwapAndArbitrage(DEX_ID, address(mockDex));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, false, false, false, false, true);
    }

    function test_pauseDex_swapAndArbitrage_noEventWhenAlreadySet() public {
        mockPauseAuthDex.setSwapResult(address(mockDex), false);

        vm.recordLogs();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, false, false, false, false, true);

        _assertNotLogged(LogPauseSwapAndArbitrage.selector);
    }

    function test_pauseDex_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseDex(DEX_ID, false, false, false, false, false);
    }

    // ==================== unpauseDex ====================

    function test_unpauseDex_multisig() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(mockDex), expectedTokens, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (address(mockDex), expectedTokens, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseDex(DEX_ID, address(mockDex), true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_class3Auth() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        vm.prank(class3Auth);
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_revertClass1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);
        pauseAuth.setNotPausableDexId(DEX_ID, true);
        vm.stopPrank();

        vm.prank(class3Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_revertZeroDexAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseDex(UNREGISTERED_DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_onlySmartCol() public {
        _setAllTokensPausedAtLL();
        mockDex.setDexVariables2(1);

        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(mockDex), expectedSupply, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_onlySmartDebt() public {
        _setAllTokensPausedAtLL();
        mockDex.setDexVariables2(2);

        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (address(mockDex), expectedBorrow, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_neitherSmartColNorDebt() public {
        mockDex.setDexVariables2(0);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeWithSelector(IFluidLiquidityAdmin.unpauseUserSupply.selector),
            0
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeWithSelector(IFluidLiquidityAdmin.unpauseUserBorrow.selector),
            0
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_unpauseDex_filterSupplyOnly() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(mockDex), expectedSupply, true, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, false, false, false, false);
    }

    function test_unpauseDex_filterBorrowOnly() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (address(mockDex), expectedBorrow, true, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, false, false, true, false, false);
    }

    function test_unpauseDex_swapAndArbitrage_forwardsToDexModule() public {
        mockPauseAuthDex.setSwapResult(address(mockDex), true);

        vm.expectCall(address(mockPauseAuthDex), abi.encodeCall(MockPauseAuthDex.unpauseSwapAndArbitrage, (DEX_ID)));

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseSwapAndArbitrage(DEX_ID, address(mockDex));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, false, false, false, false, true);
    }

    function test_unpauseDex_swapAndArbitrage_noEventWhenAlreadySet() public {
        mockPauseAuthDex.setSwapResult(address(mockDex), false);

        vm.recordLogs();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, false, false, false, false, true);

        _assertNotLogged(LogUnpauseSwapAndArbitrage.selector);
    }

    function test_unpauseDex_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseDex(DEX_ID, false, false, false, false, false);
    }

    // ==================== pauseUserLiquidity (pass-through) ====================

    function test_pauseUserSupply_multisig() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        _setUserData(user, USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (user, tokens, true, true))
        );

        vm.expectEmit(true, true, false, true, address(pauseAuth));
        emit LogPauseUser(user, USDC, true, true, false, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseUserSupplyLiquidity(user, tokens, true, true);
    }

    function test_pauseUserBorrow_multisig() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;
        _setUserData(user, WETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (user, tokens, true, true))
        );

        vm.expectEmit(true, true, false, true, address(pauseAuth));
        emit LogPauseUser(user, WETH, false, false, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseUserBorrowLiquidity(user, tokens, true, true);
    }

    function test_pauseUserSupply_revertPauseAuth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(class1Auth);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.pauseUserSupplyLiquidity(user, tokens, true, true);
    }

    function test_pauseUserSupply_revertUnauthorized() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.pauseUserSupplyLiquidity(user, tokens, true, true);
    }

    function test_pauseUserSupply_multisig2CanPause() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        _setUserData(user, USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);

        vm.prank(TEAM_MULTISIG2);
        pauseAuth.pauseUserSupplyLiquidity(user, tokens, true, true);
    }

    function test_pauseUserBorrow_multisig2CanPause() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        _setUserData(user, USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);

        vm.prank(TEAM_MULTISIG2);
        pauseAuth.pauseUserBorrowLiquidity(user, tokens, true, true);
    }

    function test_unpauseUserSupply_revertMultisig2() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(TEAM_MULTISIG2);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.unpauseUserSupplyLiquidity(user, tokens, true, true);
    }

    function test_unpauseUserDex_revertMultisig2() public {
        vm.prank(TEAM_MULTISIG2);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.unpauseUserDex(DEX_ID, makeAddr("dexUser"), true, true, true, true);
    }

    function test_pauseUserDex_multisig() public {
        address user = makeAddr("dexUser");
        mockPauseAuthDex.setUserResult(address(mockDex));

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseUser, (DEX_ID, user, true, true, false, false))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseDexUser(DEX_ID, address(mockDex), user, true, true, false, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseUserDex(DEX_ID, user, true, true, false, false);
    }

    /// @dev the DEX executor rejects supply alone; the pass-through must not swallow that
    function test_pauseUserDex_RevertIfPartialSide() public {
        mockPauseAuthDex.setRevertPartialSide(true);

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuth.pauseUserDex(DEX_ID, makeAddr("dexUser"), true, false, false, false);
    }

    function test_pauseUserDex_revertUnauthorized() public {
        address user = makeAddr("dexUser");

        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.pauseUserDex(DEX_ID, user, true, true, false, false);
    }

    // ==================== unpauseUserLiquidity (pass-through) ====================

    function test_unpauseUserSupply_multisig() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        _setUserData(user, USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (user, tokens, true, true))
        );

        vm.expectEmit(true, true, false, true, address(pauseAuth));
        emit LogUnpauseUser(user, USDC, true, true, false, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseUserSupplyLiquidity(user, tokens, true, true);
    }

    function test_unpauseUserBorrow_multisig() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;
        _setUserData(user, WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (user, tokens, true, true))
        );

        vm.expectEmit(true, true, false, true, address(pauseAuth));
        emit LogUnpauseUser(user, WETH, false, false, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseUserBorrowLiquidity(user, tokens, true, true);
    }

    function test_unpauseUserSupply_revertPauseAuth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(class2Auth);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.unpauseUserSupplyLiquidity(user, tokens, true, true);
    }

    function test_unpauseUserSupply_revertUnauthorized() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.unpauseUserSupplyLiquidity(user, tokens, true, true);
    }

    function test_unpauseUserDex_multisig() public {
        address user = makeAddr("dexUser");
        mockPauseAuthDex.setUserResult(address(mockDex));

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.unpauseUser, (DEX_ID, user, false, false, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseDexUser(DEX_ID, address(mockDex), user, false, false, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseUserDex(DEX_ID, user, false, false, true, true);
    }

    function test_unpauseUserDex_RevertIfPartialSide() public {
        mockPauseAuthDex.setRevertPartialSide(true);

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuth.unpauseUserDex(DEX_ID, makeAddr("dexUser"), false, false, false, true);
    }

    function test_unpauseUserDex_revertUnauthorized() public {
        address user = makeAddr("dexUser");

        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.unpauseUserDex(DEX_ID, user, false, false, true, true);
    }

    // ==================== smart lending ====================

    function test_pauseSmartLending_forwardsToDexModule() public {
        address smartLending = makeAddr("smartLending");
        mockPauseAuthDex.setSmartLendingResult(address(mockDex), smartLending, true, true);

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseSmartLending, (DEX_ID, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseSmartLending(DEX_ID, address(mockDex), smartLending, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseSmartLending(DEX_ID, true, true);
    }

    function test_pauseSmartLending_noEventWhenAlreadySet() public {
        mockPauseAuthDex.setSmartLendingResult(address(mockDex), makeAddr("smartLending"), false, false);

        vm.recordLogs();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseSmartLending(DEX_ID, true, true);

        _assertNotLogged(LogPauseSmartLending.selector);
    }

    function test_pauseSmartLending_revertClass1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseSmartLending(DEX_ID, true, true);
    }

    function test_pauseSmartLending_revertNotPausableDexId() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
        pauseAuth.setNotPausableDexId(DEX_ID, true);
        vm.stopPrank();

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseSmartLending(DEX_ID, true, true);
    }

    function test_unpauseSmartLending_forwardsToDexModule() public {
        address smartLending = makeAddr("smartLending");
        mockPauseAuthDex.setSmartLendingResult(address(mockDex), smartLending, true, true);

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.unpauseSmartLending, (DEX_ID, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseSmartLending(DEX_ID, address(mockDex), smartLending, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseSmartLending(DEX_ID, true, true);
    }

    function test_unpauseSmartLending_noEventWhenAlreadySet() public {
        mockPauseAuthDex.setSmartLendingResult(address(mockDex), makeAddr("smartLending"), false, false);

        vm.recordLogs();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseSmartLending(DEX_ID, true, true);

        _assertNotLogged(LogUnpauseSmartLending.selector);
    }

    function test_unpauseSmartLending_revertClass2() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseSmartLending(DEX_ID, true, true);
    }

    // ==================== pauseTokens / unpauseTokens ====================

    function test_pauseTokens_multisig() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens, true, true, true, true))
        );

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseToken(tokens[0], true, true, true, true);
        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseToken(tokens[1], true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseTokens(tokens);
    }

    function test_pauseTokens_revertClass1Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseTokens(tokens);
    }

    function test_pauseTokens_class2Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens, true, true, true, true))
        );

        vm.prank(class2Auth);
        pauseAuth.pauseTokens(tokens);
    }

    function test_pauseTokens_revertNoSidesSelected() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseTokens(tokens, false, false, false, false);
    }

    function test_pauseTokens_revertUnauthorized() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseTokens(tokens);
    }

    function test_unpauseTokens_multisig() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens, true, true, true, true))
        );

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogUnpauseToken(tokens[0], true, true, true, true);
        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogUnpauseToken(tokens[1], true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_class3Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        _setTokenPauseState(USDC, true);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens, true, true, true, true))
        );

        vm.prank(class3Auth);
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_revertClass2() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_revertClass1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_revertNoSidesSelected() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseTokens(tokens, false, false, false, false);
    }

    function test_unpauseTokens_revertUnauthorized() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseTokens(tokens);
    }

    // ==================== notPausableTokens ====================

    function test_setNotPausableToken() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(USDC, true);
        assertTrue(pauseAuth.notPausableTokens(USDC));
    }

    function test_setNotPausableToken_revertNotMultisig() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.setNotPausableToken(USDC, true);
    }

    function test_setNotPausableToken_revertZeroAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        pauseAuth.setNotPausableToken(address(0), true);
    }

    function test_pauseTokens_skipsNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
        pauseAuth.setNotPausableToken(USDC, true);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        address[] memory expected = new address[](1);
        expected[0] = WETH;

        vm.expectEmit(true, false, false, false);
        emit LogSkipTokenNotPausable(USDC);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (expected, true, true, true, true))
        );

        vm.prank(class2Auth);
        pauseAuth.pauseTokens(tokens);
    }

    function test_pauseTokens_skipsAllNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
        pauseAuth.setNotPausableToken(USDC, true);
        vm.stopPrank();

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectEmit(true, false, false, false);
        emit LogSkipTokenNotPausable(USDC);

        vm.prank(class2Auth);
        pauseAuth.pauseTokens(tokens);
        // no call to LIQUIDITY.pauseTokens — all tokens were skipped
    }

    function test_pauseTokens_multisigBypassesNotPausable() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(USDC, true);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens, true, true, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseTokens(tokens);
    }

    function test_unpauseTokens_skipsNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);
        pauseAuth.setNotPausableToken(USDC, true);
        vm.stopPrank();

        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        address[] memory expected = new address[](1);
        expected[0] = WETH;

        vm.expectEmit(true, false, false, false);
        emit LogSkipTokenNotPausable(USDC);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (expected, true, true, true, true))
        );

        vm.prank(class3Auth);
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_skipsAllNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);
        pauseAuth.setNotPausableToken(USDC, true);
        vm.stopPrank();

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectEmit(true, false, false, false);
        emit LogSkipTokenNotPausable(USDC);

        vm.prank(class3Auth);
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_multisigBypassesNotPausable() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(USDC, true);

        _setTokenPauseState(USDC, true);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens, true, true, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseTokens(tokens);
    }

    // ==================== token LL state skip ====================

    function test_pauseTokens_alreadyPaused_stillCallsLiquidity() public {
        _setTokenPauseState(USDC, true); // USDC already paused at LL

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens, true, true, true, true))
        );

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseToken(tokens[1], true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseTokens(tokens);
    }

    function test_pauseTokens_allAlreadyPaused_stillCallsLiquidity() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens, true, true, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseTokens(tokens);
    }

    function test_unpauseTokens_alreadyUnpaused_stillCallsLiquidity() public {
        // USDC and WETH default to 0 (unpaused) in mock

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens, true, true, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_partiallyPaused_stillCallsLiquidity() public {
        _setTokenPauseState(WETH, true); // only WETH is paused

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens, true, true, true, true))
        );

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogUnpauseToken(tokens[1], true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseTokens(tokens);
    }

    // ==================== pauseVaults / unpauseVaults (batch) ====================

    function test_pauseVaults_batch() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.prank(class1Auth);
        pauseAuth.pauseVaults(
            vaultIds,
            _boolArray(2, false),
            _boolArray(2, false),
            _boolArray(2, true),
            _boolArray(2, false)
        );
    }

    function test_pauseVaults_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableVaultId(VAULT_NEWER_ID, true);
        vm.stopPrank();

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVaults(
            vaultIds,
            _boolArray(2, false),
            _boolArray(2, false),
            _boolArray(2, true),
            _boolArray(2, false)
        );
    }

    function test_pauseVaults_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVaults(
            vaultIds,
            _boolArray(1, false),
            _boolArray(1, false),
            _boolArray(1, false),
            _boolArray(1, false)
        );
    }

    function test_unpauseVaults_batch() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        _setAllTokensPausedAtLL();

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.prank(class3Auth);
        pauseAuth.unpauseVaults(
            vaultIds,
            _boolArray(2, true),
            _boolArray(2, true),
            _boolArray(2, true),
            _boolArray(2, true)
        );
    }

    function test_unpauseVaults_revertClass1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVaults(
            vaultIds,
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true)
        );
    }

    function test_pauseVaults_skipsAlreadyPausedAtLL() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, 1);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), false, false, true, false);

        vm.prank(class1Auth);
        pauseAuth.pauseVaults(
            vaultIds,
            _boolArray(1, false),
            _boolArray(1, false),
            _boolArray(1, true),
            _boolArray(1, false)
        );
    }

    function test_pauseVaults_skipsFullyPausedAtLL() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.recordLogs();

        vm.prank(class1Auth);
        pauseAuth.pauseVaults(
            vaultIds,
            _boolArray(1, false),
            _boolArray(1, false),
            _boolArray(1, true),
            _boolArray(1, false)
        );

        _assertNotLogged(LogPauseVault.selector);
    }

    function test_unpauseVaults_skipsNotPausedAtLL() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, 1); // supply paused, borrow not paused
        _setUserData(address(mockVaultT1), WETH, 1, 1); // neither paused

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogUnpauseVault(VAULT_T1_ID, address(mockVaultT1), true, true, false, false);

        vm.prank(class3Auth);
        pauseAuth.unpauseVaults(
            vaultIds,
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true)
        );
    }

    // ==================== batch array length mismatch ====================

    function test_pauseVaults_revertArrayLengthMismatch() public {
        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVaults(
            vaultIds,
            _boolArray(1, true),
            _boolArray(2, true),
            _boolArray(2, true),
            _boolArray(2, true)
        );
    }

    function test_unpauseVaults_revertArrayLengthMismatch() public {
        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVaults(
            vaultIds,
            _boolArray(2, true),
            _boolArray(1, true),
            _boolArray(2, true),
            _boolArray(2, true)
        );
    }

    function test_pauseDexes_revertArrayLengthMismatch() public {
        uint256[] memory dexIds = new uint256[](1);
        dexIds[0] = DEX_ID;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseDexes(
            dexIds,
            _boolArray(2, true),
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true)
        );
    }

    function test_unpauseDexes_revertArrayLengthMismatch() public {
        uint256[] memory dexIds = new uint256[](1);
        dexIds[0] = DEX_ID;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseDexes(
            dexIds,
            _boolArray(1, true),
            _boolArray(2, true),
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true)
        );
    }

    // ==================== pauseDexes / unpauseDexes (batch) ====================

    function test_pauseDexes_batch() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory dexIds = new uint256[](1);
        dexIds[0] = DEX_ID;

        vm.prank(class1Auth);
        pauseAuth.pauseDexes(
            dexIds,
            _boolArray(1, false),
            _boolArray(1, false),
            _boolArray(1, true),
            _boolArray(1, false),
            _boolArray(1, false)
        );
    }

    function test_pauseDexes_revertNotPausable() public {
        uint256 otherDexId = 997;
        mockDexFactory.setDex(otherDexId, address(mockDex));

        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableDexId(otherDexId, true);
        vm.stopPrank();

        uint256[] memory dexIds = new uint256[](2);
        dexIds[0] = DEX_ID;
        dexIds[1] = otherDexId;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseDexes(
            dexIds,
            _boolArray(2, true),
            _boolArray(2, false),
            _boolArray(2, true),
            _boolArray(2, false),
            _boolArray(2, false)
        );
    }

    function test_unpauseDexes_batch() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        _setAllTokensPausedAtLL();

        uint256[] memory dexIds = new uint256[](1);
        dexIds[0] = DEX_ID;

        vm.prank(class3Auth);
        pauseAuth.unpauseDexes(
            dexIds,
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, true),
            _boolArray(1, false)
        );
    }

    function test_pauseVaults_batch_perIndexFlags() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        bool[] memory supplyFlags = new bool[](2);
        bool[] memory withdrawFlags = new bool[](2);
        bool[] memory borrowFlags = new bool[](2);
        bool[] memory paybackFlags = new bool[](2);

        supplyFlags[0] = false;
        supplyFlags[1] = true;
        withdrawFlags[0] = true;
        withdrawFlags[1] = false;
        borrowFlags[0] = false;
        borrowFlags[1] = true;
        paybackFlags[0] = true;
        paybackFlags[1] = false;

        address[] memory expectedSupplyVault0 = new address[](1);
        expectedSupplyVault0[0] = USDC;
        address[] memory expectedBorrowVault0 = new address[](1);
        expectedBorrowVault0[0] = WETH;

        address[] memory expectedSupplyVault1 = new address[](2);
        expectedSupplyVault1[0] = WSTETH;
        expectedSupplyVault1[1] = DAI;
        address[] memory expectedBorrowVault1 = new address[](1);
        expectedBorrowVault1[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.pauseUserSupply,
                (address(mockVaultT1), expectedSupplyVault0, false, true)
            )
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.pauseUserBorrow,
                (address(mockVaultT1), expectedBorrowVault0, false, true)
            )
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.pauseUserSupply,
                (address(mockVaultNewer), expectedSupplyVault1, true, false)
            )
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.pauseUserBorrow,
                (address(mockVaultNewer), expectedBorrowVault1, true, false)
            )
        );

        vm.prank(class2Auth);
        pauseAuth.pauseVaults(vaultIds, supplyFlags, withdrawFlags, borrowFlags, paybackFlags);
    }

    function test_pauseDexes_batch_perIndexFlags() public {
        uint256 otherDexId = 2;
        MockDex otherDex = new MockDex(USDC, DAI, 3);
        mockDexFactory.setDex(otherDexId, address(otherDex));
        _setUserData(address(otherDex), USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(otherDex), DAI, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        uint256[] memory dexIds = new uint256[](2);
        dexIds[0] = DEX_ID;
        dexIds[1] = otherDexId;

        bool[] memory supplyFlags = new bool[](2);
        bool[] memory withdrawFlags = new bool[](2);
        bool[] memory borrowFlags = new bool[](2);
        bool[] memory paybackFlags = new bool[](2);
        bool[] memory swapArbitrageFlags = new bool[](2);

        supplyFlags[0] = false;
        supplyFlags[1] = true;
        withdrawFlags[0] = false;
        withdrawFlags[1] = true;
        borrowFlags[0] = true;
        borrowFlags[1] = false;
        paybackFlags[0] = false;
        paybackFlags[1] = true;
        swapArbitrageFlags[0] = true;
        swapArbitrageFlags[1] = false;

        address[] memory expectedTokensDex1 = new address[](2);
        expectedTokensDex1[0] = WSTETH;
        expectedTokensDex1[1] = WETH;

        address[] memory expectedTokensDex2 = new address[](2);
        expectedTokensDex2[0] = USDC;
        expectedTokensDex2[1] = DAI;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), expectedTokensDex1, true, false))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(otherDex), expectedTokensDex2, true, true))
        );
        vm.expectCall(address(mockPauseAuthDex), abi.encodeCall(MockPauseAuthDex.pauseSwapAndArbitrage, (DEX_ID)));

        vm.prank(class2Auth);
        pauseAuth.pauseDexes(dexIds, supplyFlags, withdrawFlags, borrowFlags, paybackFlags, swapArbitrageFlags);
    }

    function test_unpauseVaults_batch_perIndexFlags() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        bool[] memory supplyFlags = new bool[](2);
        bool[] memory withdrawFlags = new bool[](2);
        bool[] memory borrowFlags = new bool[](2);
        bool[] memory paybackFlags = new bool[](2);

        supplyFlags[0] = true;
        supplyFlags[1] = false;
        withdrawFlags[0] = false;
        withdrawFlags[1] = true;
        borrowFlags[0] = true;
        borrowFlags[1] = false;
        paybackFlags[0] = false;
        paybackFlags[1] = true;

        address[] memory expectedSupplyVault0 = new address[](1);
        expectedSupplyVault0[0] = USDC;
        address[] memory expectedBorrowVault0 = new address[](1);
        expectedBorrowVault0[0] = WETH;

        address[] memory expectedSupplyVault1 = new address[](2);
        expectedSupplyVault1[0] = WSTETH;
        expectedSupplyVault1[1] = DAI;
        address[] memory expectedBorrowVault1 = new address[](1);
        expectedBorrowVault1[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.unpauseUserSupply,
                (address(mockVaultT1), expectedSupplyVault0, true, false)
            )
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.unpauseUserBorrow,
                (address(mockVaultT1), expectedBorrowVault0, true, false)
            )
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.unpauseUserSupply,
                (address(mockVaultNewer), expectedSupplyVault1, false, true)
            )
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.unpauseUserBorrow,
                (address(mockVaultNewer), expectedBorrowVault1, false, true)
            )
        );

        vm.prank(class3Auth);
        pauseAuth.unpauseVaults(vaultIds, supplyFlags, withdrawFlags, borrowFlags, paybackFlags);
    }

    function test_unpauseDexes_batch_perIndexFlags() public {
        _setAllTokensPausedAtLL();

        uint256 otherDexId = 2;
        MockDex otherDex = new MockDex(USDC, DAI, 3);
        mockDexFactory.setDex(otherDexId, address(otherDex));
        _setUserData(address(otherDex), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(otherDex), DAI, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);

        uint256[] memory dexIds = new uint256[](2);
        dexIds[0] = DEX_ID;
        dexIds[1] = otherDexId;

        bool[] memory supplyFlags = new bool[](2);
        bool[] memory withdrawFlags = new bool[](2);
        bool[] memory borrowFlags = new bool[](2);
        bool[] memory paybackFlags = new bool[](2);
        bool[] memory swapArbitrageFlags = new bool[](2);

        supplyFlags[0] = true;
        supplyFlags[1] = false;
        withdrawFlags[0] = false;
        withdrawFlags[1] = true;
        borrowFlags[0] = true;
        borrowFlags[1] = false;
        paybackFlags[0] = false;
        paybackFlags[1] = true;
        swapArbitrageFlags[0] = false;
        swapArbitrageFlags[1] = true;

        address[] memory expectedTokensDex1 = new address[](2);
        expectedTokensDex1[0] = WSTETH;
        expectedTokensDex1[1] = WETH;

        address[] memory expectedTokensDex2 = new address[](2);
        expectedTokensDex2[0] = USDC;
        expectedTokensDex2[1] = DAI;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(mockDex), expectedTokensDex1, true, false))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (address(mockDex), expectedTokensDex1, true, false))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(otherDex), expectedTokensDex2, false, true))
        );
        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.unpauseSwapAndArbitrage, (otherDexId))
        );

        vm.prank(class3Auth);
        pauseAuth.unpauseDexes(dexIds, supplyFlags, withdrawFlags, borrowFlags, paybackFlags, swapArbitrageFlags);
    }

    function test_pauseVaults_batch_RevertIfLevelViolatedInLaterElement() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        bool[] memory supplyFlags = new bool[](2);
        bool[] memory withdrawFlags = new bool[](2);
        bool[] memory borrowFlags = new bool[](2);
        bool[] memory paybackFlags = new bool[](2);

        supplyFlags[0] = false;
        supplyFlags[1] = false;
        withdrawFlags[0] = false;
        withdrawFlags[1] = true;
        borrowFlags[0] = true;
        borrowFlags[1] = true;
        paybackFlags[0] = false;
        paybackFlags[1] = false;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVaults(vaultIds, supplyFlags, withdrawFlags, borrowFlags, paybackFlags);
    }

    function test_pauseVault_emitsDexLegEvent() public {
        mockPauseAuthDex.setPauseVaultResult(address(mockVaultNewerDexBacked), true, false, true, false);

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_DEX_BACKED_ID, address(mockVaultNewerDexBacked), true, false, true, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);
    }

    // ==================== Edge cases ====================

    function test_revokePauseAuth_thenRevert() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 0);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);
    }

    function test_revokeVaultId_thenRevertNotPausable() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);
    }

    function test_pauseAuth_revertNotPausableVaultId() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableVaultId(VAULT_NEWER_ID, true);
        vm.stopPrank();

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_NEWER_ID, false, false, true, false);
    }

    function test_pauseAuth_revertNotPausableDexId() public {
        uint256 otherDexId = 997;
        mockDexFactory.setDex(otherDexId, address(mockDex));

        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableDexId(otherDexId, true);
        vm.stopPrank();

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, false, false, true, false, false);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseDex(otherDexId, false, false, true, false, false);
    }

    function test_class3RemovesClass1_thenClass1CannotPause() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setPauseAuth(class3Auth, 3);
        vm.stopPrank();

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);

        vm.prank(class3Auth);
        pauseAuth.removeClass1PauseAuth(class1Auth);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);
    }

    function test_pauseVault_revertInvalidVaultConstants() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVault(VAULT_REVERTING_ID, true, true, true, true);
    }

    function test_pauseVault_revertNewerVaultInvalidConstants() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVault(VAULT_NEWER_REVERTING_ID, true, true, true, true);
    }

    function test_unpauseVault_revertNewerVaultInvalidConstants() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVault(VAULT_NEWER_REVERTING_ID, true, true, true, true);
    }

    function test_unpauseVault_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class3Auth, 3);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);
        vm.stopPrank();

        vm.prank(class3Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    // ==================== TEAM_MULTISIG bypasses notPausable ====================

    function test_pauseVault_multisig_bypassesNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), true, true, true, true);

        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
        vm.stopPrank();
    }

    function test_unpauseVault_multisig_bypassesNotPausable() public {
        _setAllTokensPausedAtLL();

        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseVault(VAULT_T1_ID, address(mockVaultT1), true, true, true, true);

        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
        vm.stopPrank();
    }

    function test_pauseDex_multisig_bypassesNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setNotPausableDexId(DEX_ID, true);

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(DEX_ID, address(mockDex), true, true, true, true);

        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
        vm.stopPrank();
    }

    function test_unpauseDex_multisig_bypassesNotPausable() public {
        _setAllTokensPausedAtLL();

        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setNotPausableDexId(DEX_ID, true);

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseDex(DEX_ID, address(mockDex), true, true, true, true);

        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
        vm.stopPrank();
    }

    // ==================== Class 1 user skip (vault) ====================

    function test_pauseVault_skipsClass1Vault() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), true, false, true, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_class1_stripsWithdrawPayback() public {
        _setUserClass(address(mockVaultT1), 1);

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockVaultT1), expectedSupply, true, false))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockVaultT1), expectedBorrow, true, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_class1Auth_skipsClass1Vault() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), false, false, true, false);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, false);
    }

    function test_pauseVault_class2_skipsLiquidityLeg() public {
        _setUserClass(address(mockVaultNewerDexBacked), 2);

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogSkipVaultUserClass(VAULT_DEX_BACKED_ID, address(mockVaultNewerDexBacked), 2);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);
    }

    function test_pauseVault_class1_dexBackedStillForwards() public {
        _setUserClass(address(mockVaultNewerDexBacked), 1);

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_DEX_BACKED_ID, address(mockVaultNewerDexBacked), false, false, true, false);
        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass(VAULT_DEX_BACKED_ID, address(mockVaultNewerDexBacked), 1);

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseVault, (VAULT_DEX_BACKED_ID, true, true, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);
    }

    function test_unpauseVault_class1_stillCallsLL() public {
        _setUserClass(address(mockVaultT1), 1);
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(mockVaultT1), expectedSupply, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (address(mockVaultT1), expectedBorrow, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseVault(VAULT_T1_ID, address(mockVaultT1), true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_class0_notSkipped() public {
        _setUserClass(address(mockVaultT1), 0);

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockVaultT1), expectedSupply, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockVaultT1), expectedBorrow, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVaults_batch_class1Skipped() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), false, false, true, false);

        // Vault Newer (class 0): bot may only pause borrow at LL
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockVaultNewer), expectedBorrow, true, false))
        );

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseVault(VAULT_NEWER_ID, address(mockVaultNewer), false, false, true, false);

        vm.prank(class1Auth);
        pauseAuth.pauseVaults(
            vaultIds,
            _boolArray(2, false),
            _boolArray(2, false),
            _boolArray(2, true),
            _boolArray(2, false)
        );
    }

    function test_pauseVault_class1_alreadyPausedAtLL_emitsAlreadySet() public {
        _setUserClass(address(mockVaultT1), 1);
        _setAllTokensPausedAtLL();

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogSkipVaultUserClass(VAULT_T1_ID, address(mockVaultT1), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    // ==================== Class 1 user skip (DEX) ====================

    function test_pauseDex_skipsClass1Dex() public {
        _setUserClass(address(mockDex), 1);

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseDex(DEX_ID, address(mockDex), true, false, true, false);
        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogSkipDexUserClass(DEX_ID, address(mockDex), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_class1_stripsWithdrawPayback() public {
        _setUserClass(address(mockDex), 1);

        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), expectedTokens, true, false))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), expectedTokens, true, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_class1Auth_skipsClass1Dex() public {
        _setUserClass(address(mockDex), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseDex(DEX_ID, address(mockDex), false, false, true, false);

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, false, false, true, false, false);
    }

    function test_unpauseDex_class1_stillCallsLL() public {
        _setUserClass(address(mockDex), 1);
        _setAllTokensPausedAtLL();

        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (address(mockDex), expectedTokens, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (address(mockDex), expectedTokens, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseDex(DEX_ID, address(mockDex), true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDex_class0_notSkipped() public {
        _setUserClass(address(mockDex), 0);

        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), expectedTokens, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), expectedTokens, true, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(DEX_ID, address(mockDex), true, true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseDexes_batch_class1Skipped() public {
        uint256 otherDexId = 2;
        MockDex otherDex = new MockDex(USDC, DAI, 3);
        mockDexFactory.setDex(otherDexId, address(otherDex));
        _setUserData(address(otherDex), USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(otherDex), DAI, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);

        _setUserClass(address(mockDex), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory dexIds = new uint256[](2);
        dexIds[0] = DEX_ID;
        dexIds[1] = otherDexId;

        // DEX 1 (Liquidity class 1): bot may only pause borrow at LL
        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseDex(DEX_ID, address(mockDex), false, false, true, false);

        // DEX 2 (class 0): bot may only pause borrow at LL
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = USDC;
        expectedTokens[1] = DAI;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(otherDex), expectedTokens, true, false))
        );

        vm.expectEmit(true, false, false, true, address(pauseAuth));
        emit LogPauseDex(otherDexId, address(otherDex), false, false, true, false);

        vm.prank(class1Auth);
        pauseAuth.pauseDexes(
            dexIds,
            _boolArray(2, false),
            _boolArray(2, false),
            _boolArray(2, true),
            _boolArray(2, false),
            _boolArray(2, false)
        );
    }

    function test_pauseDex_class1_alreadyPausedAtLL_emitsAlreadySet() public {
        _setUserClass(address(mockDex), 1);
        _setAllTokensPausedAtLL();

        vm.expectEmit(true, false, false, true);
        emit LogSkipDexUserClass(DEX_ID, address(mockDex), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, true, true, false);
    }

    function test_pauseVault_class1_supplyOnly_skips() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), true, false, false, false);
        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass(VAULT_T1_ID, address(mockVaultT1), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true, false, false);
    }

    function test_pauseVault_class1_borrowOnly_skips() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), false, false, true, false);
        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass(VAULT_T1_ID, address(mockVaultT1), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, false, false, true, true);
    }

    function test_pauseDex_class1_supplyOnly_skips() public {
        _setUserClass(address(mockDex), 1);

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(DEX_ID, address(mockDex), true, false, false, false);
        vm.expectEmit(true, false, false, true);
        emit LogSkipDexUserClass(DEX_ID, address(mockDex), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, false, false, false);
    }

    function test_pauseDex_class1_borrowOnly_skips() public {
        _setUserClass(address(mockDex), 1);

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(DEX_ID, address(mockDex), false, false, true, false);
        vm.expectEmit(true, false, false, true);
        emit LogSkipDexUserClass(DEX_ID, address(mockDex), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, false, false, true, true, false);
    }
}
