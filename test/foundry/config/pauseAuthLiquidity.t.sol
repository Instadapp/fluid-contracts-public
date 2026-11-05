// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BasicValidations } from "contracts/libraries/utils/basicValidations.sol";
import { LibsErrorTypes } from "contracts/libraries/errorTypes.sol";

import { FluidPauseAuthLiquidity } from "contracts/config/pauseAuth/pauseAuthLiquidity.sol";
import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { Error as LiquidityError } from "contracts/liquidity/error.sol";
import { ErrorTypes as LiquidityErrorTypes } from "contracts/liquidity/errorTypes.sol";
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
        if (userData_ == 0) {
            revert LiquidityError.FluidLiquidityError(LiquidityErrorTypes.AdminModule__UserNotDefined);
        }
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
        if (!pauseSupply_ && !pauseWithdraw_) {
            revert LiquidityError.FluidLiquidityError(LiquidityErrorTypes.AdminModule__InvalidParams);
        }
        emit PauseUserSupplyCalled(user_, tokens_, pauseSupply_, pauseWithdraw_);
        return _updateUserSupplyPause(user_, tokens_, pauseSupply_, pauseWithdraw_, false);
    }

    function pauseUserBorrow(
        address user_,
        address[] calldata tokens_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external returns (bool[] memory actedBorrow_, bool[] memory actedPayback_) {
        if (!pauseBorrow_ && !pausePayback_) {
            revert LiquidityError.FluidLiquidityError(LiquidityErrorTypes.AdminModule__InvalidParams);
        }
        emit PauseUserBorrowCalled(user_, tokens_, pauseBorrow_, pausePayback_);
        return _updateUserBorrowPause(user_, tokens_, pauseBorrow_, pausePayback_, false);
    }

    function unpauseUserSupply(
        address user_,
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_
    ) external returns (bool[] memory actedSupply_, bool[] memory actedWithdraw_) {
        if (!unpauseSupply_ && !unpauseWithdraw_) {
            revert LiquidityError.FluidLiquidityError(LiquidityErrorTypes.AdminModule__InvalidParams);
        }
        emit UnpauseUserSupplyCalled(user_, tokens_, unpauseSupply_, unpauseWithdraw_);
        return _updateUserSupplyPause(user_, tokens_, unpauseSupply_, unpauseWithdraw_, true);
    }

    function unpauseUserBorrow(
        address user_,
        address[] calldata tokens_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external returns (bool[] memory actedBorrow_, bool[] memory actedPayback_) {
        if (!unpauseBorrow_ && !unpausePayback_) {
            revert LiquidityError.FluidLiquidityError(LiquidityErrorTypes.AdminModule__InvalidParams);
        }
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

    function setVault(uint256 vaultId_, address vault_) external {
        _vaults[vaultId_] = vault_;
    }

    function getVaultAddress(uint256 vaultId_) external view returns (address) {
        return _vaults[vaultId_];
    }
}

contract MockDexFactory {
    mapping(uint256 => address) internal _dexes;

    function setDex(uint256 dexId_, address dex_) external {
        _dexes[dexId_] = dex_;
    }

    function getDexAddress(uint256 dexId_) external view returns (address) {
        return _dexes[dexId_];
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

contract MockRevertingConstantsDex {
    function constantsView() external pure {
        revert("mock dex constants revert");
    }
}

contract MockRevertingStorageDex {
    address public immutable TOKEN0;

    constructor(address token0_) {
        TOKEN0 = token0_;
    }

    function constantsView() external view returns (IFluidDexT1.ConstantViews memory cv_) {
        cv_.token0 = TOKEN0;
    }

    function readFromStorage(bytes32) external pure returns (uint256) {
        revert("mock dex storage revert");
    }
}

// ==================== Tests ====================

// To test run:
// forge test -vvv --match-path test/foundry/config/pauseAuthLiquidity.t.sol
contract PauseAuthLiquidityTest is Test {
    FluidPauseAuthLiquidity public pauseAuthLiquidity;

    MockLiquidity public mockLiquidity;
    MockVaultFactory public mockVaultFactory;
    MockDexFactory public mockDexFactory;

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    address public authGate;

    address public unauthorizedUser = makeAddr("unauthorizedUser");

    address public constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant WSTETH = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    MockVaultT1 public mockVaultT1;
    MockVaultNewer public mockVaultNewerDexBacked;
    MockDex public mockDex;

    uint256 public constant VAULT_T1_ID = 1;
    uint256 public constant VAULT_DEX_BACKED_ID = 2;
    uint256 public constant DEX_ID = 1;
    uint256 public constant UNREGISTERED_VAULT_ID = 999;
    uint256 public constant UNREGISTERED_DEX_ID = 998;
    uint256 public constant VAULT_UNCONFIGURED_ID = 3;
    uint256 public constant DEX_UNCONFIGURED_ID = 2;

    uint256 constant DEFINED_NOT_PAUSED = 1;
    uint256 constant DEFINED_AND_PAUSED = 1 | (uint256(1) << 255);

    event PauseUserSupplyCalled(address user, address[] tokens, bool pauseSupply, bool pauseWithdraw);
    event PauseUserBorrowCalled(address user, address[] tokens, bool pauseBorrow, bool pausePayback);
    event UnpauseUserSupplyCalled(address user, address[] tokens, bool unpauseSupply, bool unpauseWithdraw);
    event UnpauseUserBorrowCalled(address user, address[] tokens, bool unpauseBorrow, bool unpausePayback);
    event PauseTokenCalled(address[] tokens);
    event UnpauseTokenCalled(address[] tokens);
    event LogSetPauseAuthContract(address indexed pauseAuthContract);

    function setUp() public {
        mockLiquidity = new MockLiquidity();
        mockVaultFactory = new MockVaultFactory();
        mockDexFactory = new MockDexFactory();
        authGate = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(address(mockLiquidity), TEAM_MULTISIG, TEAM_MULTISIG2, makeAddr("teamTimelock"))
        );

        pauseAuthLiquidity = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            authGate
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuthLiquidity.setPauseAuthContract(address(this));

        // Deploy mock vaults and DEX
        mockVaultT1 = new MockVaultT1(USDC, WETH);
        address mockDexAddr = makeAddr("mockDexAddr");
        mockVaultNewerDexBacked = new MockVaultNewer(
            address(mockLiquidity), // liquidity
            mockDexAddr, // supply via DEX (not liquidity)
            address(mockLiquidity), // borrow via liquidity
            WSTETH,
            WETH, // supply tokens (excluded since supply is DEX)
            USDC,
            address(0) // borrow token (single)
        );
        mockDex = new MockDex(WSTETH, WETH, 3); // both supply and borrow enabled

        // Register in factories
        mockVaultFactory.setVault(VAULT_T1_ID, address(mockVaultT1));
        mockVaultFactory.setVault(VAULT_DEX_BACKED_ID, address(mockVaultNewerDexBacked));
        mockDexFactory.setDex(DEX_ID, address(mockDex));

        // Set up mock LL storage: defined and not paused for all vault/dex + token combos
        _setUserData(address(mockVaultT1), USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultNewerDexBacked), USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockDex), WSTETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockDex), WETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
    }

    // ==================== Helpers ====================

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

    function _setUserClass(address user_, uint256 class_) internal {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_CLASS_MAPPING_SLOT,
            user_
        );
        mockLiquidity.setStorageValue(slot_, class_);
    }

    function _setTokenPauseState(address token_, bool paused_) internal {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            token_
        );
        uint256 value_ = paused_ ? uint256(15) << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_PAUSE_MODE : uint256(0);
        mockLiquidity.setStorageValue(slot_, value_);
    }

    function _setAllTokensPausedAtLL() internal {
        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultNewerDexBacked), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockDex), WSTETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockDex), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
    }

    /// @dev Registers a T1 vault with no Liquidity supply or borrow row, mirroring mainnet vault 182.
    function _registerUnconfiguredVault() internal returns (address vault_) {
        vault_ = address(new MockVaultT1(DAI, WSTETH));
        mockVaultFactory.setVault(VAULT_UNCONFIGURED_ID, vault_);
    }

    /// @dev Registers a DEX with both sides enabled but no Liquidity rows.
    function _registerUnconfiguredDex() internal returns (address dex_) {
        dex_ = address(new MockDex(DAI, WSTETH, 3));
        mockDexFactory.setDex(DEX_UNCONFIGURED_ID, dex_);
    }

    // ==================== 1. Constructor tests ====================

    function test_deployment() public view {
        assertEq(address(pauseAuthLiquidity.LIQUIDITY()), address(mockLiquidity));
        assertEq(address(pauseAuthLiquidity.VAULT_FACTORY()), address(mockVaultFactory));
        assertEq(address(pauseAuthLiquidity.DEX_FACTORY()), address(mockDexFactory));
        assertEq(pauseAuthLiquidity.pauseAuthContract(), address(this));
        assertEq(address(pauseAuthLiquidity.AUTH_GATE()), authGate);
    }

    function test_constructor_revertZeroLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuthLiquidity(address(0), address(mockVaultFactory), address(mockDexFactory), authGate);
    }

    function test_constructor_revertZeroVaultFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuthLiquidity(address(mockLiquidity), address(0), address(mockDexFactory), authGate);
    }

    function test_constructor_revertZeroDexFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuthLiquidity(address(mockLiquidity), address(mockVaultFactory), address(0), authGate);
    }

    function test_constructor_RevertIfAuthGateForOtherLiquidity() public {
        address otherLiquidity_ = makeAddr("otherLiquidity");
        address otherAuthGate_ = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(otherLiquidity_, TEAM_MULTISIG, TEAM_MULTISIG2, makeAddr("teamTimelock"))
        );

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            otherAuthGate_
        );
    }

    // ==================== 2. setPauseAuthContract ====================

    function test_setPauseAuthContract_success() public {
        FluidPauseAuthLiquidity fresh = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            authGate
        );

        address newPauseAuth = makeAddr("newPauseAuth");

        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuthContract(newPauseAuth);

        vm.prank(TEAM_MULTISIG);
        fresh.setPauseAuthContract(newPauseAuth);

        assertEq(fresh.pauseAuthContract(), newPauseAuth);
    }

    function test_setPauseAuthContract_multisig2CanSet() public {
        FluidPauseAuthLiquidity fresh = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            authGate
        );

        vm.prank(TEAM_MULTISIG2);
        fresh.setPauseAuthContract(address(this));
        assertEq(fresh.pauseAuthContract(), address(this));
    }

    function test_setPauseAuthContract_revertNotMultisig() public {
        FluidPauseAuthLiquidity fresh = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            authGate
        );

        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        fresh.setPauseAuthContract(address(this));
    }

    function test_setPauseAuthContract_revertAlreadySet() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.setPauseAuthContract(makeAddr("anotherAddr"));
    }

    function test_setPauseAuthContract_revertZeroAddress() public {
        FluidPauseAuthLiquidity fresh = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            authGate
        );

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        fresh.setPauseAuthContract(address(0));
    }

    // ==================== 3. pauseVault ====================

    function test_pauseVault_T1_bothSides() public {
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, true, true);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseVault_T1_callsLiquidity() public {
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

        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_T1_onlySupply() public {
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, false, false);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockVaultT1), expectedSupply, true, true))
        );
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, false, false);
    }

    function test_pauseVault_T1_onlyBorrow() public {
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, false, false, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);

        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockVaultT1), expectedBorrow, true, true))
        );
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, false, false, true, true);
    }

    function test_pauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseVault_revertZeroVaultAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseVault(UNREGISTERED_VAULT_ID, true, true, true, true);
    }

    function test_pauseVault_revertNoSidesSelected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, false, false, false, false);
    }

    // ==================== 4. unpauseVault ====================

    function test_unpauseVault_T1_bothSides() public {
        _setAllTokensPausedAtLL();

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true, true, true);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseVault_T1_callsLiquidity() public {
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

        pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_unpauseVault_T1_onlySupply() public {
        _setAllTokensPausedAtLL();

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true, false, false);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseVault_T1_onlyBorrow() public {
        _setAllTokensPausedAtLL();

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, false, false, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_unpauseVault_revertZeroVaultAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.unpauseVault(UNREGISTERED_VAULT_ID, true, true, true, true);
    }

    function test_unpauseVault_revertNoSidesSelected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, false, false, false, false);
    }

    // ==================== 5. pauseDex ====================

    function test_pauseDex_bothSides() public {
        (
            address dex,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, true, true, true);

        assertEq(dex, address(mockDex));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseDex_callsLiquidity() public {
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

        pauseAuthLiquidity.pauseDex(DEX_ID, true, true, true, true);
    }

    function test_pauseDex_onlySupply() public {
        (
            address dex,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, true, false, false);

        assertEq(dex, address(mockDex));
        assertTrue(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseDex_onlyBorrow() public {
        (
            address dex,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, false, false, true, true);

        assertEq(dex, address(mockDex));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseDex_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.pauseDex(DEX_ID, true, true, true, true);
    }

    function test_pauseDex_revertZeroDexAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseDex(UNREGISTERED_DEX_ID, true, true, true, true);
    }

    function test_pauseDex_RevertIfDexConstantsRevert() public {
        uint256 dexId_ = 900;
        mockDexFactory.setDex(dexId_, address(new MockRevertingConstantsDex()));

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseDex(dexId_, true, true, true, true);
    }

    function test_pauseDex_RevertIfDexStorageReadReverts() public {
        uint256 dexId_ = 901;
        mockDexFactory.setDex(dexId_, address(new MockRevertingStorageDex(USDC)));

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseDex(dexId_, true, true, true, true);
    }

    function test_pauseDex_revertNoSidesSelected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseDex(DEX_ID, false, false, false, false);
    }

    // ==================== 6. unpauseDex ====================

    function test_unpauseDex_bothSides() public {
        _setAllTokensPausedAtLL();

        (
            address dex,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseDex(DEX_ID, true, true, true, true);

        assertEq(dex, address(mockDex));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseDex_callsLiquidity() public {
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

        pauseAuthLiquidity.unpauseDex(DEX_ID, true, true, true, true);
    }

    function test_unpauseDex_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.unpauseDex(DEX_ID, true, true, true, true);
    }

    function test_unpauseDex_revertZeroDexAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.unpauseDex(UNREGISTERED_DEX_ID, true, true, true, true);
    }

    function test_unpauseDex_revertNoSidesSelected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.unpauseDex(DEX_ID, false, false, false, false);
    }

    // ==================== 7. pauseTokens / unpauseTokens ====================

    function test_pauseTokens_success() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        pauseAuthLiquidity.pauseTokens(tokens, true, true, true, true);
    }

    function test_pauseTokens_callsLiquidity() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens, true, true, true, true))
        );

        pauseAuthLiquidity.pauseTokens(tokens, true, true, true, true);
    }

    function test_pauseTokens_alreadyPaused_stillCallsLiquidity() public {
        _setTokenPauseState(USDC, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens, true, true, true, true))
        );
        pauseAuthLiquidity.pauseTokens(tokens, true, true, true, true);
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
        pauseAuthLiquidity.pauseTokens(tokens, true, true, true, true);
    }

    function test_pauseTokens_revertUnauthorized() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.pauseTokens(tokens, true, true, true, true);
    }

    function test_unpauseTokens_success() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        pauseAuthLiquidity.unpauseTokens(tokens, true, true, true, true);
    }

    function test_unpauseTokens_callsLiquidity() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens, true, true, true, true))
        );

        pauseAuthLiquidity.unpauseTokens(tokens, true, true, true, true);
    }

    function test_unpauseTokens_alreadyUnpaused_stillCallsLiquidity() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens, true, true, true, true))
        );
        pauseAuthLiquidity.unpauseTokens(tokens, true, true, true, true);
    }

    function test_unpauseTokens_partiallyPaused_stillCallsLiquidity() public {
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens, true, true, true, true))
        );
        pauseAuthLiquidity.unpauseTokens(tokens, true, true, true, true);
    }

    function test_unpauseTokens_revertUnauthorized() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.unpauseTokens(tokens, true, true, true, true);
    }

    // ==================== 8. pauseUserSupply / pauseUserBorrow / unpause (pass-through) ====================

    function test_pauseUserSupply_passThrough() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        _setUserData(user, USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (user, tokens, true, true))
        );

        vm.expectEmit(false, false, false, true);
        emit PauseUserSupplyCalled(user, tokens, true, true);

        pauseAuthLiquidity.pauseUserSupply(user, tokens, true, true);
    }

    function test_pauseUserBorrow_passThrough() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;
        _setUserData(user, WETH, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (user, tokens, true, true))
        );

        vm.expectEmit(false, false, false, true);
        emit PauseUserBorrowCalled(user, tokens, true, true);

        pauseAuthLiquidity.pauseUserBorrow(user, tokens, true, true);
    }

    function test_pauseUserSupply_revertUnauthorized() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.pauseUserSupply(user, tokens, true, true);
    }

    function test_unpauseUserSupply_passThrough() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        _setUserData(user, USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (user, tokens, true, true))
        );

        vm.expectEmit(false, false, false, true);
        emit UnpauseUserSupplyCalled(user, tokens, true, true);

        pauseAuthLiquidity.unpauseUserSupply(user, tokens, true, true);
    }

    function test_unpauseUserBorrow_passThrough() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;
        _setUserData(user, WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (user, tokens, true, true))
        );

        vm.expectEmit(false, false, false, true);
        emit UnpauseUserBorrowCalled(user, tokens, true, true);

        pauseAuthLiquidity.unpauseUserBorrow(user, tokens, true, true);
    }

    function test_unpauseUserSupply_revertUnauthorized() public {
        address user = makeAddr("someUser");
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.unpauseUserSupply(user, tokens, true, true);
    }

    /// @dev unlike the vault and DEX paths, the pass-throughs do not drop undefined rows.
    function test_pauseUserSupply_passThroughUnfiltered_RevertIfRowUndefined() public {
        address[] memory tokens = new address[](1);
        tokens[0] = DAI;

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.AdminModule__UserNotDefined
            )
        );
        pauseAuthLiquidity.pauseUserSupply(makeAddr("undefinedUser"), tokens, true, true);
    }

    function test_pauseUserBorrow_passThroughUnfiltered_RevertIfRowUndefined() public {
        address[] memory tokens = new address[](1);
        tokens[0] = DAI;

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.AdminModule__UserNotDefined
            )
        );
        pauseAuthLiquidity.pauseUserBorrow(makeAddr("undefinedUser"), tokens, true, true);
    }

    // ==================== 9. Class 1 user skip ====================

    function test_pauseVault_skipsClass1User() public {
        _setUserClass(address(mockVaultT1), 1);

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, true, true);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 1);
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
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, true, true);
    }

    function test_pauseDex_skipsClass1User() public {
        _setUserClass(address(mockDex), 1);

        (
            address dex,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, true, true, true);

        assertEq(dex, address(mockDex));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 1);
    }

    function test_pauseDex_class1_stripsWithdrawPayback() public {
        _setUserClass(address(mockDex), 1);

        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;
        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), expectedSupply, true, false))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), expectedBorrow, true, false))
        );
        pauseAuthLiquidity.pauseDex(DEX_ID, true, true, true, true);
    }

    function test_mockLiquidity_pauseUserSupply_false_false_reverts() public {
        address[] memory t = new address[](1);
        t[0] = USDC;
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.AdminModule__InvalidParams
            )
        );
        mockLiquidity.pauseUserSupply(address(mockVaultT1), t, false, false);
    }

    function test_mockLiquidity_pauseUserBorrow_false_false_reverts() public {
        address[] memory t = new address[](1);
        t[0] = WETH;
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.AdminModule__InvalidParams
            )
        );
        mockLiquidity.pauseUserBorrow(address(mockVaultT1), t, false, false);
    }

    /// @dev Class 1 cannot pause withdraw; after stripping there is no valid supply-side pause — must not call LL with (false,false).
    function test_pauseVault_class1_withdrawOnly_skipsSupplyLiquidity() public {
        _setUserClass(address(mockVaultT1), 1);
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, false, true, false, false);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 1);
    }

    /// @dev Class 1 cannot pause payback; borrow-side flags become empty — must not call LL with (false,false).
    function test_pauseVault_class1_paybackOnly_skipsBorrowLiquidity() public {
        _setUserClass(address(mockVaultT1), 1);
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, false, false, false, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 1);
    }

    function test_unpauseVault_class1_stillCallsLL() public {
        _setUserClass(address(mockVaultT1), 1);
        _setAllTokensPausedAtLL();

        (, bool actedSupply, , bool actedBorrow, , uint256 skippedUserClass) = pauseAuthLiquidity.unpauseVault(
            VAULT_T1_ID,
            true,
            true,
            true,
            true
        );

        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseDex_class1_stillCallsLL() public {
        _setUserClass(address(mockDex), 1);
        _setAllTokensPausedAtLL();

        (, bool actedSupply, , bool actedBorrow, , uint256 skippedUserClass) = pauseAuthLiquidity.unpauseDex(
            DEX_ID,
            true,
            true,
            true,
            true
        );

        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    // ==================== 9b. Class 2 user skip ====================

    function test_pauseVault_class2_skipsBothSides() public {
        _setUserClass(address(mockVaultT1), 2);

        address[] memory supplyTokens_ = new address[](1);
        supplyTokens_[0] = USDC;
        address[] memory borrowTokens_ = new address[](1);
        borrowTokens_[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockVaultT1), supplyTokens_, true, true)),
            0
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockVaultT1), borrowTokens_, true, true)),
            0
        );

        (, bool actedSupply, , bool actedBorrow, , uint256 skippedUserClass) = pauseAuthLiquidity.pauseVault(
            VAULT_T1_ID,
            true,
            true,
            true,
            true
        );

        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 2);
    }

    /// @dev class 2 wins over the class 1 strip even for a supply-only request.
    function test_pauseVault_class2_supplyOnly_skips() public {
        _setUserClass(address(mockVaultT1), 2);

        (, bool actedSupply, , , , uint256 skippedUserClass) = pauseAuthLiquidity.pauseVault(
            VAULT_T1_ID,
            true,
            true,
            false,
            false
        );

        assertFalse(actedSupply);
        assertEq(skippedUserClass, 2);
    }

    function test_pauseDex_class2_skipsBothSides() public {
        _setUserClass(address(mockDex), 2);

        address[] memory tokens_ = new address[](2);
        tokens_[0] = WSTETH;
        tokens_[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), tokens_, true, true)),
            0
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), tokens_, true, true)),
            0
        );

        (, bool actedSupply, , bool actedBorrow, , uint256 skippedUserClass) = pauseAuthLiquidity.pauseDex(
            DEX_ID,
            true,
            true,
            true,
            true
        );

        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 2);
    }

    /// @dev the class gate guards pausing only, so class 2 must stay unpausable.
    function test_unpauseVault_class2_stillCallsLL() public {
        _setUserClass(address(mockVaultT1), 2);
        _setAllTokensPausedAtLL();

        (, bool actedSupply, , bool actedBorrow, , uint256 skippedUserClass) = pauseAuthLiquidity.unpauseVault(
            VAULT_T1_ID,
            true,
            true,
            true,
            true
        );

        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseDex_class2_stillCallsLL() public {
        _setUserClass(address(mockDex), 2);
        _setAllTokensPausedAtLL();

        (, bool actedSupply, , bool actedBorrow, , uint256 skippedUserClass) = pauseAuthLiquidity.unpauseDex(
            DEX_ID,
            true,
            true,
            true,
            true
        );

        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    // ==================== 10. Already-set skip ====================

    function test_pauseVault_supplyAlreadyPaused() public {
        // USDC supply already paused, WETH borrow not paused
        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_NOT_PAUSED);

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseVault_borrowAlreadyPaused() public {
        // USDC supply not paused, WETH borrow already paused
        _setUserData(address(mockVaultT1), WETH, DEFINED_NOT_PAUSED, DEFINED_AND_PAUSED);

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, true, true);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseVault_bothAlreadyPaused() public {
        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseVault_supplyAlreadyUnpaused() public {
        // USDC supply not paused, WETH borrow paused
        _setUserData(address(mockVaultT1), USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseVault_bothAlreadyUnpaused() public {
        // All tokens not paused (default state)
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseDex_alreadyPaused() public {
        _setUserData(address(mockDex), WSTETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockDex), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        (
            address dex,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, true, true, true);

        assertEq(dex, address(mockDex));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseDex_alreadyUnpaused() public {
        (
            address dex,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseDex(DEX_ID, true, true, true, true);

        assertEq(dex, address(mockDex));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    // ==================== 11. Newer vault with DEX-backed sides ====================

    function test_pauseVault_dexBacked_excludesSupply() public {
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);

        assertEq(vault, address(mockVaultNewerDexBacked));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseVault_dexBacked_callsLiquidityWithoutSupply() public {
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.pauseUserBorrow,
                (address(mockVaultNewerDexBacked), expectedBorrow, true, true)
            )
        );

        pauseAuthLiquidity.pauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);
    }

    function test_unpauseVault_dexBacked_excludesSupply() public {
        _setAllTokensPausedAtLL();

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseVault(VAULT_DEX_BACKED_ID, true, true, true, true);

        assertEq(vault, address(mockVaultNewerDexBacked));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseVault_dexBacked_supplyOnlyNoAction() public {
        // Supply is DEX-backed, pausing supply only should have no effect at LL
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_DEX_BACKED_ID, true, true, false, false);

        assertEq(vault, address(mockVaultNewerDexBacked));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseVault_dexBacked_borrowOnly() public {
        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_DEX_BACKED_ID, false, false, true, true);

        assertEq(vault, address(mockVaultNewerDexBacked));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    // ==================== 12. Protocols with no Liquidity rows ====================

    function test_pauseVault_unconfiguredVault_noOp() public {
        address unconfigured_ = _registerUnconfiguredVault();

        address[] memory supplyTokens_ = new address[](1);
        supplyTokens_[0] = DAI;
        address[] memory borrowTokens_ = new address[](1);
        borrowTokens_[0] = WSTETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (unconfigured_, supplyTokens_, true, true)),
            0
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (unconfigured_, borrowTokens_, true, true)),
            0
        );

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseVault(VAULT_UNCONFIGURED_ID, true, true, true, true);

        assertEq(vault, unconfigured_);
        assertFalse(actedSupply);
        assertFalse(actedWithdraw);
        assertFalse(actedBorrow);
        assertFalse(actedPayback);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseVault_unconfiguredVault_noOp() public {
        address unconfigured_ = _registerUnconfiguredVault();

        address[] memory supplyTokens_ = new address[](1);
        supplyTokens_[0] = DAI;
        address[] memory borrowTokens_ = new address[](1);
        borrowTokens_[0] = WSTETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserSupply, (unconfigured_, supplyTokens_, true, true)),
            0
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUserBorrow, (unconfigured_, borrowTokens_, true, true)),
            0
        );

        (
            address vault,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.unpauseVault(VAULT_UNCONFIGURED_ID, true, true, true, true);

        assertEq(vault, unconfigured_);
        assertFalse(actedSupply);
        assertFalse(actedWithdraw);
        assertFalse(actedBorrow);
        assertFalse(actedPayback);
        assertEq(skippedUserClass, 0);
    }

    function test_pauseVault_unconfiguredVaultInBatch_goodVaultStillActs() public {
        _registerUnconfiguredVault();

        uint256[] memory vaultIds_ = new uint256[](2);
        vaultIds_[0] = VAULT_UNCONFIGURED_ID;
        vaultIds_[1] = VAULT_T1_ID;

        bool[] memory acted_ = new bool[](2);
        for (uint256 i; i < vaultIds_.length; i++) {
            (, bool actedSupply_, , bool actedBorrow_, , ) = pauseAuthLiquidity.pauseVault(
                vaultIds_[i],
                true,
                true,
                true,
                true
            );
            acted_[i] = actedSupply_ || actedBorrow_;
        }

        assertFalse(acted_[0]);
        assertTrue(acted_[1]);
    }

    function test_unpauseVault_unconfiguredVaultInBatch_goodVaultStillActs() public {
        _setAllTokensPausedAtLL();
        _registerUnconfiguredVault();

        uint256[] memory vaultIds_ = new uint256[](2);
        vaultIds_[0] = VAULT_UNCONFIGURED_ID;
        vaultIds_[1] = VAULT_T1_ID;

        bool[] memory acted_ = new bool[](2);
        for (uint256 i; i < vaultIds_.length; i++) {
            (, bool actedSupply_, , bool actedBorrow_, , ) = pauseAuthLiquidity.unpauseVault(
                vaultIds_[i],
                true,
                true,
                true,
                true
            );
            acted_[i] = actedSupply_ || actedBorrow_;
        }

        assertFalse(acted_[0]);
        assertTrue(acted_[1]);
    }

    function test_pauseDex_unconfiguredDex_noOp() public {
        address unconfigured_ = _registerUnconfiguredDex();

        address[] memory tokens_ = new address[](2);
        tokens_[0] = DAI;
        tokens_[1] = WSTETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (unconfigured_, tokens_, true, true)),
            0
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (unconfigured_, tokens_, true, true)),
            0
        );

        (
            address dex,
            bool actedSupply,
            bool actedWithdraw,
            bool actedBorrow,
            bool actedPayback,
            uint256 skippedUserClass
        ) = pauseAuthLiquidity.pauseDex(DEX_UNCONFIGURED_ID, true, true, true, true);

        assertEq(dex, unconfigured_);
        assertFalse(actedSupply);
        assertFalse(actedWithdraw);
        assertFalse(actedBorrow);
        assertFalse(actedPayback);
        assertEq(skippedUserClass, 0);
    }

    function test_unpauseDex_unconfiguredDexInBatch_goodDexStillActs() public {
        _setAllTokensPausedAtLL();
        _registerUnconfiguredDex();

        uint256[] memory dexIds_ = new uint256[](2);
        dexIds_[0] = DEX_UNCONFIGURED_ID;
        dexIds_[1] = DEX_ID;

        bool[] memory acted_ = new bool[](2);
        for (uint256 i; i < dexIds_.length; i++) {
            (, bool actedSupply_, , bool actedBorrow_, , ) = pauseAuthLiquidity.unpauseDex(
                dexIds_[i],
                true,
                true,
                true,
                true
            );
            acted_[i] = actedSupply_ || actedBorrow_;
        }

        assertFalse(acted_[0]);
        assertTrue(acted_[1]);
    }

    function test_pauseVault_supplyRowMissing_borrowSideStillActs() public {
        _setUserData(address(mockVaultT1), USDC, 0, 0);

        address[] memory supplyTokens_ = new address[](1);
        supplyTokens_[0] = USDC;
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockVaultT1), supplyTokens_, true, true)),
            0
        );

        (, bool actedSupply, , bool actedBorrow, , ) = pauseAuthLiquidity.pauseVault(
            VAULT_T1_ID,
            true,
            true,
            true,
            true
        );

        assertFalse(actedSupply);
        assertTrue(actedBorrow);
    }

    function test_pauseDex_oneTokenRowMissing_callsLiquidityWithDefinedTokenOnly() public {
        _setUserData(address(mockDex), WETH, 0, 0);

        address[] memory expectedTokens_ = new address[](1);
        expectedTokens_[0] = WSTETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), expectedTokens_, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), expectedTokens_, true, true))
        );

        (, bool actedSupply, , bool actedBorrow, , uint256 skippedUserClass) = pauseAuthLiquidity.pauseDex(
            DEX_ID,
            true,
            true,
            true,
            true
        );

        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertEq(skippedUserClass, 0);
    }

    /// @dev the two sides filter against their own mapping slot, so one missing supply row must not
    ///      shrink the borrow-side array.
    function test_pauseDex_supplyRowMissing_borrowSideKeepsBothTokens() public {
        _setUserData(address(mockDex), WETH, 0, DEFINED_NOT_PAUSED);

        address[] memory supplyTokens_ = new address[](1);
        supplyTokens_[0] = WSTETH;
        address[] memory borrowTokens_ = new address[](2);
        borrowTokens_[0] = WSTETH;
        borrowTokens_[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserSupply, (address(mockDex), supplyTokens_, true, true))
        );
        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUserBorrow, (address(mockDex), borrowTokens_, true, true))
        );

        (, bool actedSupply, , bool actedBorrow, , ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, true, true, true);

        assertTrue(actedSupply);
        assertTrue(actedBorrow);
    }
}
