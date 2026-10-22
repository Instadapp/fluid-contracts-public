// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BasicValidations } from "contracts/libraries/utils/basicValidations.sol";
import { LibsErrorTypes } from "contracts/libraries/errorTypes.sol";

import { FluidPauseAuthDex } from "contracts/config/pauseAuth/pauseAuthDex.sol";
import { BigMathMinified } from "contracts/libraries/bigMathMinified.sol";
import { Structs as AdminModuleStructs } from "contracts/protocols/dex/poolT1/adminModule/structs.sol";
import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { IFluidVault } from "contracts/protocols/vault/interfaces/iVault.sol";
import { ErrorTypes as DexErrorTypes } from "contracts/protocols/dex/errorTypes.sol";

error Access__Unauthorized();

// ==================== Mock contracts ====================

contract MockLiquidity {
    // the auth gate reads the EIP-1967 admin slot for its governance check
    function readFromStorage(bytes32) external pure returns (uint256) {
        return 0;
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

contract MockRevertingDexFactory {
    mapping(uint256 => address) internal _dexes;

    function setDex(uint256 dexId_, address dex_) external {
        _dexes[dexId_] = dex_;
    }

    function getDexAddress(uint256 dexId_) external view returns (address) {
        return _dexes[dexId_];
    }

    function isDex(address) external pure returns (bool) {
        revert("mock isDex revert");
    }
}

contract MockSmartLendingFactory {
    mapping(uint256 => address) internal _smartLendings;

    function setSmartLending(uint256 dexId_, address smartLending_) external {
        _smartLendings[dexId_] = smartLending_;
    }

    function getSmartLendingAddress(uint256 dexId_) external view returns (address) {
        return _smartLendings[dexId_];
    }
}

/// @dev Mock DEX pool that records admin calls and tracks storage state for pre-checks.
///      Mirrors real DEX T1 pools: user pause is side-level only, tracked via bit 0 of the
///      user supply / borrow data slots (0 = whole side paused, 1 = side active).
contract MockDexPool {
    using BigMathMinified for uint256;

    error FluidDexError(uint256 errorId);

    uint256 public immutable DEX_ID;
    bool public swapPaused;
    uint256 public pauseUserCallCount;
    uint256 public unpauseUserCallCount;
    uint256 public updateUserBorrowConfigsCallCount;

    struct PauseUserCall {
        address user;
        bool supply;
        bool borrow;
    }
    PauseUserCall public lastPauseUserCall;
    PauseUserCall public lastUnpauseUserCall;

    mapping(bytes32 => uint256) internal _storageSlots;

    event SwapPaused();
    event SwapUnpaused();
    event UserPaused(address user, bool pauseSupply, bool pauseBorrow);
    event UserUnpaused(address user, bool unpauseSupply, bool unpauseBorrow);

    constructor(uint256 dexId_) {
        DEX_ID = dexId_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        return _storageSlots[slot_];
    }

    function setStorageSlot(bytes32 slot_, uint256 value_) external {
        _storageSlots[slot_] = value_;
    }

    function pauseSwapAndArbitrage() external {
        swapPaused = true;
        _storageSlots[bytes32(uint256(1))] = _storageSlots[bytes32(uint256(1))] | (uint256(1) << 255);
        emit SwapPaused();
    }

    function unpauseSwapAndArbitrage() external {
        swapPaused = false;
        _storageSlots[bytes32(uint256(1))] = _storageSlots[bytes32(uint256(1))] & ~(uint256(1) << 255);
        emit SwapUnpaused();
    }

    /// @dev bit 0 only; a row without config bits gets a marker at 162 so it stays non-zero like a real row
    function _storeSidePaused(bytes32 slot_, bool paused_) internal {
        uint256 data_ = _storageSlots[slot_] & ~uint256(1);
        if (data_ >> 162 == 0) {
            data_ |= uint256(1) << 162;
        }
        _storageSlots[slot_] = data_ | (paused_ ? 0 : 1);
    }

    /// @dev the pool admin's validations, bit 0 forced on, only bits 162-235 rewritten
    function updateUserBorrowConfigs(AdminModuleStructs.UserBorrowConfig[] memory configs_) external {
        updateUserBorrowConfigsCallCount++;
        for (uint256 i; i < configs_.length; i++) {
            AdminModuleStructs.UserBorrowConfig memory c_ = configs_[i];
            if (c_.baseDebtCeiling > c_.maxDebtCeiling || c_.expandDuration == 0) {
                revert FluidDexError(DexErrorTypes.DexT1Admin__InvalidParams);
            }
            if (c_.expandPercent > 0x3fff || c_.expandDuration > 0xffffff) {
                revert FluidDexError(DexErrorTypes.DexT1Admin__ConfigOverflow);
            }
            if (c_.baseDebtCeiling == 0 || c_.maxDebtCeiling == 0) {
                revert FluidDexError(DexErrorTypes.DexT1Admin__InvalidParams);
            }
            bytes32 slot_ = keccak256(abi.encode(c_.user, uint256(5)));
            _storageSlots[slot_] =
                (_storageSlots[slot_] & 0xfffff0000000000000000003ffffffffffffffffffffffffffffffffffffffff) |
                1 |
                (c_.expandPercent << 162) |
                (c_.expandDuration << 176) |
                (c_.baseDebtCeiling.toBigNumber(10, 8, BigMathMinified.ROUND_DOWN) << 200) |
                (c_.maxDebtCeiling.toBigNumber(10, 8, BigMathMinified.ROUND_DOWN) << 218);
        }
    }

    function pauseUser(address user_, bool pauseSupply_, bool pauseBorrow_) external {
        pauseUserCallCount++;
        lastPauseUserCall = PauseUserCall(user_, pauseSupply_, pauseBorrow_);
        if (pauseSupply_) {
            _storeSidePaused(keccak256(abi.encode(user_, uint256(3))), true);
        }
        if (pauseBorrow_) {
            _storeSidePaused(keccak256(abi.encode(user_, uint256(5))), true);
        }
        emit UserPaused(user_, pauseSupply_, pauseBorrow_);
    }

    function unpauseUser(address user_, bool unpauseSupply_, bool unpauseBorrow_) external {
        unpauseUserCallCount++;
        lastUnpauseUserCall = PauseUserCall(user_, unpauseSupply_, unpauseBorrow_);
        if (unpauseSupply_) {
            _storeSidePaused(keccak256(abi.encode(user_, uint256(3))), false);
        }
        if (unpauseBorrow_) {
            _storeSidePaused(keccak256(abi.encode(user_, uint256(5))), false);
        }
        emit UserUnpaused(user_, unpauseSupply_, unpauseBorrow_);
    }
}

/// @dev Mock DEX pool whose admin calls revert with a configurable payload, to exercise revert handling.
contract MockRevertingDexPool {
    error FluidDexError(uint256 errorId);

    bytes internal _revertData;
    bool internal _passThrough;

    mapping(bytes32 => uint256) internal _storageSlots;

    function setRevertData(bytes memory revertData_) external {
        _revertData = revertData_;
    }

    /// @dev admin calls succeed without storing, so a later call can be made to revert
    function setPassThrough(bool passThrough_) external {
        _passThrough = passThrough_;
    }

    function setStorageSlot(bytes32 slot_, uint256 value_) external {
        _storageSlots[slot_] = value_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        return _storageSlots[slot_];
    }

    function pauseUser(address, bool, bool) external view {
        _revertWithData();
    }

    function unpauseUser(address, bool, bool) external view {
        _revertWithData();
    }

    function updateUserBorrowConfigs(AdminModuleStructs.UserBorrowConfig[] memory) external view {
        _revertWithData();
    }

    function _revertWithData() internal view {
        if (_passThrough) {
            return;
        }
        bytes memory revertData_ = _revertData;
        assembly {
            revert(add(revertData_, 32), mload(revertData_))
        }
    }
}

/// @dev Mock T1 vault. Does NOT implement TYPE() — mirrors real T1 vaults.
///      T1 vaults always use Liquidity, so _getVaultDexes returns (address(0), address(0)).
contract MockVaultT1 {
    function constantsView()
        external
        pure
        returns (
            address,
            address,
            address,
            address,
            address,
            address,
            uint8,
            uint8,
            uint256,
            bytes32,
            bytes32,
            bytes32,
            bytes32
        )
    {
        return (
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
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
///      supply/borrow addresses can be Liquidity or DEX.
contract MockVaultNewer {
    address public immutable LIQUIDITY_ADDR;
    address public immutable SUPPLY_ADDR;
    address public immutable BORROW_ADDR;

    constructor(address liquidity_, address supply_, address borrow_) {
        LIQUIDITY_ADDR = liquidity_;
        SUPPLY_ADDR = supply_;
        BORROW_ADDR = borrow_;
    }

    function TYPE() external pure returns (uint256) {
        return 20000;
    }

    function constantsView() external view returns (IFluidVault.ConstantViews memory cv_) {
        cv_.liquidity = LIQUIDITY_ADDR;
        cv_.supply = SUPPLY_ADDR;
        cv_.borrow = BORROW_ADDR;
        cv_.vaultId = 2;
        cv_.vaultType = 2;
    }
}

contract MockRevertingVault {
    function constantsView() external pure {
        revert("mock revert");
    }
}

/// @dev Newer vault whose type resolves but whose constants do not — the only shape that reaches the
///      `_getVaultDexes` failure path, since a missing `TYPE()` is read as T1 and returns early.
contract MockVaultNewerReverting {
    function TYPE() external pure returns (uint256) {
        return 20000;
    }

    function constantsView() external pure {
        revert("mock newer vault revert");
    }
}

// ==================== Tests ====================

// To test run:
// forge test -vvv --match-path test/foundry/config/pauseAuthDex.t.sol
contract PauseAuthDexTest is Test {
    using BigMathMinified for uint256;

    FluidPauseAuthDex public pauseAuthDex;

    MockLiquidity public mockLiquidity;
    MockVaultFactory public mockVaultFactory;
    MockDexFactory public mockDexFactory;
    MockSmartLendingFactory public mockSmartLendingFactory;
    MockDexPool public mockDexPool;
    MockDexPool public mockDexPool2;

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    address public authGate;

    address public unauthorizedUser = makeAddr("unauthorizedUser");
    address public smartLending = makeAddr("smartLending");
    address public smartLending2 = makeAddr("smartLending2");
    address public someUser = makeAddr("someUser");

    uint256 public constant DEX_ID_1 = 1;
    uint256 public constant DEX_ID_2 = 2;
    uint256 public constant DEX_ID_NO_SL = 3;
    uint256 public constant DEX_ID_REVERTING = 4;

    MockRevertingDexPool public mockRevertingDexPool;

    MockVaultT1 public mockVaultT1;
    MockVaultNewer public mockVaultSupplyDex;
    MockVaultNewer public mockVaultBorrowDex;
    MockVaultNewer public mockVaultBothDex;
    MockVaultNewer public mockVaultSameDex;
    MockVaultNewer public mockVaultNoDex;
    MockVaultNewer public mockVaultNonDexSupply;
    MockRevertingVault public mockRevertingVault;
    MockVaultNewerReverting public mockVaultNewerReverting;
    MockDexPool public mockDexPoolNoSL;

    uint256 public constant VAULT_T1_ID = 1;
    uint256 public constant VAULT_SUPPLY_DEX_ID = 2;
    uint256 public constant VAULT_BORROW_DEX_ID = 3;
    uint256 public constant VAULT_BOTH_DEX_ID = 4;
    uint256 public constant VAULT_SAME_DEX_ID = 5;
    uint256 public constant VAULT_NO_DEX_ID = 6;
    uint256 public constant VAULT_REVERTING_ID = 7;
    uint256 public constant VAULT_NEWER_REVERTING_ID = 8;
    uint256 public constant VAULT_NON_DEX_SUPPLY_ID = 9;
    uint256 public constant UNREGISTERED_VAULT_ID = 999;

    event LogSetPauseAuthContract(address indexed pauseAuthContract);
    event LogFreezeDexUserBorrow(address indexed dex, address indexed user, uint256 snapshot);
    event LogRestoreDexUserBorrow(address indexed dex, address indexed user, uint256 snapshot);

    uint256 internal constant DEFAULT_EXPAND_PERCENT = 2000;
    uint256 internal constant DEFAULT_EXPAND_DURATION = 43_200;
    uint256 internal constant DEFAULT_BASE_DEBT_CEILING = 5_000e18;
    uint256 internal constant DEFAULT_MAX_DEBT_CEILING = 10_000e18;
    uint256 internal constant USER_BORROW_CONFIG_MASK = ((1 << 74) - 1) << 162;
    uint256 internal constant FREEZE_PERCENT = 1;
    uint256 internal constant FREEZE_DURATION = 0xffffff;
    uint256 internal constant FREEZE_BASE = 10;
    uint256 internal constant FREEZE_MAX = 20;

    function setUp() public {
        mockLiquidity = new MockLiquidity();
        mockVaultFactory = new MockVaultFactory();
        mockDexFactory = new MockDexFactory();
        mockSmartLendingFactory = new MockSmartLendingFactory();

        mockDexPool = new MockDexPool(DEX_ID_1);
        mockDexPool2 = new MockDexPool(DEX_ID_2);
        mockDexPoolNoSL = new MockDexPool(DEX_ID_NO_SL);

        mockDexFactory.setDex(DEX_ID_1, address(mockDexPool));
        mockDexFactory.setDex(DEX_ID_2, address(mockDexPool2));
        mockDexFactory.setDex(DEX_ID_NO_SL, address(mockDexPoolNoSL));

        mockRevertingDexPool = new MockRevertingDexPool();
        mockDexFactory.setDex(DEX_ID_REVERTING, address(mockRevertingDexPool));
        mockSmartLendingFactory.setSmartLending(DEX_ID_1, smartLending);
        mockSmartLendingFactory.setSmartLending(DEX_ID_2, smartLending2);
        // DEX_ID_NO_SL has no smart lending (returns address(0))

        authGate = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(address(mockLiquidity), TEAM_MULTISIG, TEAM_MULTISIG2, makeAddr("teamTimelock"))
        );
        pauseAuthDex = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory),
            authGate
        );

        // Set this test contract as the pauseAuthContract (locked-once)
        vm.prank(TEAM_MULTISIG);
        pauseAuthDex.setPauseAuthContract(address(this));

        // Deploy mock vaults
        mockVaultT1 = new MockVaultT1();
        mockVaultSupplyDex = new MockVaultNewer(
            address(mockLiquidity),
            address(mockDexPool), // supply via DEX
            address(mockLiquidity) // borrow via Liquidity
        );
        mockVaultBorrowDex = new MockVaultNewer(
            address(mockLiquidity),
            address(mockLiquidity), // supply via Liquidity
            address(mockDexPool2) // borrow via DEX
        );
        mockVaultBothDex = new MockVaultNewer(
            address(mockLiquidity),
            address(mockDexPool), // supply via DEX
            address(mockDexPool2) // borrow via DEX
        );
        mockVaultSameDex = new MockVaultNewer(
            address(mockLiquidity),
            address(mockDexPool), // supply via same DEX
            address(mockDexPool) // borrow via same DEX
        );
        mockVaultNoDex = new MockVaultNewer(
            address(mockLiquidity),
            address(mockLiquidity), // supply via Liquidity
            address(mockLiquidity) // borrow via Liquidity
        );
        // supply resolves to a deployed contract the DEX factory does not know
        mockVaultNonDexSupply = new MockVaultNewer(
            address(mockLiquidity),
            address(mockSmartLendingFactory),
            address(mockLiquidity)
        );
        mockRevertingVault = new MockRevertingVault();
        mockVaultNewerReverting = new MockVaultNewerReverting();

        // Register vaults
        mockVaultFactory.setVault(VAULT_T1_ID, address(mockVaultT1));
        mockVaultFactory.setVault(VAULT_SUPPLY_DEX_ID, address(mockVaultSupplyDex));
        mockVaultFactory.setVault(VAULT_BORROW_DEX_ID, address(mockVaultBorrowDex));
        mockVaultFactory.setVault(VAULT_BOTH_DEX_ID, address(mockVaultBothDex));
        mockVaultFactory.setVault(VAULT_SAME_DEX_ID, address(mockVaultSameDex));
        mockVaultFactory.setVault(VAULT_NO_DEX_ID, address(mockVaultNoDex));
        mockVaultFactory.setVault(VAULT_REVERTING_ID, address(mockRevertingVault));
        mockVaultFactory.setVault(VAULT_NEWER_REVERTING_ID, address(mockVaultNewerReverting));
        mockVaultFactory.setVault(VAULT_NON_DEX_SUPPLY_ID, address(mockVaultNonDexSupply));

        // Set up DEX storage so _dexUserSideChanges pre-checks pass for pause operations.
        // Supply rows: value 1 = defined + unpaused (bit 0 = 1). Borrow rows carry a full config so the
        // borrow-limit freeze has something to snapshot. Supply mapping slot = 3, borrow mapping slot = 5.
        // mockDexPool (DEX_ID_1) users:
        mockDexPool.setStorageSlot(keccak256(abi.encode(address(mockVaultSupplyDex), uint256(3))), 1);
        mockDexPool.setStorageSlot(keccak256(abi.encode(address(mockVaultBothDex), uint256(3))), 1);
        mockDexPool.setStorageSlot(keccak256(abi.encode(address(mockVaultSameDex), uint256(3))), 1);
        mockDexPool.setStorageSlot(
            keccak256(abi.encode(address(mockVaultSameDex), uint256(5))),
            _defaultBorrowRow(false)
        );
        mockDexPool.setStorageSlot(keccak256(abi.encode(smartLending, uint256(3))), 1);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(3))), 1);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), _defaultBorrowRow(false));
        // mockDexPool2 (DEX_ID_2) users:
        mockDexPool2.setStorageSlot(
            keccak256(abi.encode(address(mockVaultBorrowDex), uint256(5))),
            _defaultBorrowRow(false)
        );
        mockDexPool2.setStorageSlot(
            keccak256(abi.encode(address(mockVaultBothDex), uint256(5))),
            _defaultBorrowRow(false)
        );
        mockDexPool2.setStorageSlot(keccak256(abi.encode(smartLending2, uint256(3))), 1);
        // mockRevertingDexPool (DEX_ID_REVERTING) users:
        mockRevertingDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(3))), 1);
        mockRevertingDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), _defaultBorrowRow(false));
    }

    /// @dev DEX T1 user pause state is side-level: bit 0 = 0 means the whole side is paused.
    ///      A configured user always has non-zero data (config bits at 162+), mirrored via bit 162 here.
    function _encodeUserSideState(bool paused_) internal pure returns (uint256 data_) {
        data_ = (uint256(1) << 162) | (paused_ ? 0 : 1);
    }

    function _setDexUserSupplyPauseState(MockDexPool dex_, address user_, bool paused_) internal {
        dex_.setStorageSlot(keccak256(abi.encode(user_, uint256(3))), _encodeUserSideState(paused_));
    }

    function _setDexUserBorrowPauseState(MockDexPool dex_, address user_, bool paused_) internal {
        dex_.setStorageSlot(keccak256(abi.encode(user_, uint256(5))), _defaultBorrowRow(paused_));
    }

    /// @dev a user borrow word as the pool admin stores it
    function _encodeUserBorrowRow(
        bool paused_,
        uint256 expandPercent_,
        uint256 expandDuration_,
        uint256 baseDebtCeiling_,
        uint256 maxDebtCeiling_
    ) internal pure returns (uint256) {
        return
            (paused_ ? 0 : 1) |
            (expandPercent_ << 162) |
            (expandDuration_ << 176) |
            (baseDebtCeiling_.toBigNumber(10, 8, BigMathMinified.ROUND_DOWN) << 200) |
            (maxDebtCeiling_.toBigNumber(10, 8, BigMathMinified.ROUND_DOWN) << 218);
    }

    function _defaultBorrowRow(bool paused_) internal pure returns (uint256) {
        return
            _encodeUserBorrowRow(
                paused_,
                DEFAULT_EXPAND_PERCENT,
                DEFAULT_EXPAND_DURATION,
                DEFAULT_BASE_DEBT_CEILING,
                DEFAULT_MAX_DEBT_CEILING
            );
    }

    function _borrowRow(address dex_, address user_) internal view returns (uint256) {
        return MockDexPool(dex_).readFromStorage(keccak256(abi.encode(user_, uint256(5))));
    }

    function _decodeBigNumber(uint256 bigNumber_) internal pure returns (uint256) {
        return BigMathMinified.fromBigNumber(bigNumber_, 8, 0xFF);
    }

    /// @dev preset config bits: governance's parking values
    function _assertFrozenConfigBits(uint256 row_) internal pure {
        assertEq((row_ >> 162) & 0x3fff, FREEZE_PERCENT, "expandPercent");
        assertEq((row_ >> 176) & 0xffffff, FREEZE_DURATION, "expandDuration");
        assertEq(_decodeBigNumber((row_ >> 200) & 0x3ffff), FREEZE_BASE, "baseDebtCeiling");
        assertEq(_decodeBigNumber((row_ >> 218) & 0x3ffff), FREEZE_MAX, "maxDebtCeiling");
    }

    /// @dev freshly frozen: side open, preset config, rest of the word as before
    function _assertFrozenRow(address dex_, address user_, uint256 before_) internal view {
        uint256 row_ = _borrowRow(dex_, user_);
        assertEq(row_ & 1, 1, "frozen row must stay unpaused");
        _assertFrozenConfigBits(row_);
        assertEq(
            row_ & ~USER_BORROW_CONFIG_MASK,
            before_ & ~USER_BORROW_CONFIG_MASK,
            "non-config bits must be untouched"
        );
    }

    function _isDexUserSidePaused(MockDexPool dex_, address user_, bool isBorrow_) internal view returns (bool) {
        uint256 userData_ = dex_.readFromStorage(keccak256(abi.encode(user_, isBorrow_ ? uint256(5) : uint256(3))));
        return userData_ & 1 == 0;
    }

    function _assertDexUserSupplyPauseState(MockDexPool dex_, address user_, bool expectedPaused_) internal view {
        assertEq(_isDexUserSidePaused(dex_, user_, false), expectedPaused_);
    }

    function _assertDexUserBorrowPauseState(MockDexPool dex_, address user_, bool expectedPaused_) internal view {
        assertEq(_isDexUserSidePaused(dex_, user_, true), expectedPaused_);
    }

    /// @dev full side (3), or borrow alone (1) on the borrow side; the rest reverts
    function _isSideMaskAccepted(bool isBorrow_, uint256 requestMask_) internal pure returns (bool) {
        return requestMask_ == 3 || (isBorrow_ && requestMask_ == 1);
    }

    /// @dev the freeze never touches the bit and acts only on an open side; its restore needs a snapshot, which the
    ///      matrix never holds when it gets there
    function _expectedUserSideMask(
        bool isBorrow_,
        bool initialPaused_,
        uint256 requestMask_,
        bool wantsPaused_
    ) internal pure returns (bool finalPaused_, uint256 actedMask_) {
        if (requestMask_ == 3 && initialPaused_ != wantsPaused_) {
            return (wantsPaused_, 3);
        }
        if (isBorrow_ && requestMask_ == 1 && wantsPaused_ && !initialPaused_) {
            return (false, 1);
        }
        return (initialPaused_, 0);
    }

    function _callUserSidePause(
        bool isBorrow_,
        bool wantsPaused_,
        uint256 requestMask_
    ) internal returns (uint256 actedMask_) {
        bool primary_ = (requestMask_ & 1) == 1;
        bool secondary_ = (requestMask_ & 2) == 2;

        if (wantsPaused_) {
            if (isBorrow_) {
                (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseUser(
                    DEX_ID_1,
                    someUser,
                    false,
                    false,
                    primary_,
                    secondary_
                );
                return (actedBorrow_ ? 1 : 0) | (actedPayback_ ? 2 : 0);
            }

            (, bool actedSupply_, bool actedWithdraw_, , ) = pauseAuthDex.pauseUser(
                DEX_ID_1,
                someUser,
                primary_,
                secondary_,
                false,
                false
            );
            return (actedSupply_ ? 1 : 0) | (actedWithdraw_ ? 2 : 0);
        }

        if (isBorrow_) {
            (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseUser(
                DEX_ID_1,
                someUser,
                false,
                false,
                primary_,
                secondary_
            );
            return (actedBorrow_ ? 1 : 0) | (actedPayback_ ? 2 : 0);
        }

        (, bool actedSupply_, bool actedWithdraw_, , ) = pauseAuthDex.unpauseUser(
            DEX_ID_1,
            someUser,
            primary_,
            secondary_,
            false,
            false
        );
        return (actedSupply_ ? 1 : 0) | (actedWithdraw_ ? 2 : 0);
    }

    /// @dev mirrors `_callUserSidePause` but ignores the returns, so no ABI decode runs under expectRevert.
    function _callUserSidePauseDiscarding(bool isBorrow_, bool wantsPaused_, uint256 requestMask_) internal {
        bool primary_ = (requestMask_ & 1) == 1;
        bool secondary_ = (requestMask_ & 2) == 2;

        if (wantsPaused_) {
            if (isBorrow_) {
                pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, primary_, secondary_);
            } else {
                pauseAuthDex.pauseUser(DEX_ID_1, someUser, primary_, secondary_, false, false);
            }
            return;
        }

        if (isBorrow_) {
            pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, primary_, secondary_);
        } else {
            pauseAuthDex.unpauseUser(DEX_ID_1, someUser, primary_, secondary_, false, false);
        }
    }

    function _assertUserSidePauseMatrixCase(
        bool isBorrow_,
        bool wantsPaused_,
        bool initialPaused_,
        uint256 requestMask_
    ) internal {
        if (isBorrow_) {
            _setDexUserBorrowPauseState(mockDexPool, someUser, initialPaused_);
        } else {
            _setDexUserSupplyPauseState(mockDexPool, someUser, initialPaused_);
        }

        if (!_isSideMaskAccepted(isBorrow_, requestMask_)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    Error.FluidConfigError.selector,
                    ErrorTypes.PauseAuthDex__PartialSideNotSupported
                )
            );
            _callUserSidePauseDiscarding(isBorrow_, wantsPaused_, requestMask_);
            assertEq(_isDexUserSidePaused(mockDexPool, someUser, isBorrow_), initialPaused_);
            return;
        }

        uint256 rowBefore_ = _borrowRow(address(mockDexPool), someUser);
        uint256 callsBefore_ = wantsPaused_ ? mockDexPool.pauseUserCallCount() : mockDexPool.unpauseUserCallCount();
        uint256 configCallsBefore_ = mockDexPool.updateUserBorrowConfigsCallCount();
        (bool expectedFinalPaused_, uint256 expectedActedMask_) = _expectedUserSideMask(
            isBorrow_,
            initialPaused_,
            requestMask_,
            wantsPaused_
        );

        uint256 actedMask_ = _callUserSidePause(isBorrow_, wantsPaused_, requestMask_);
        assertEq(actedMask_, expectedActedMask_);
        assertEq(_isDexUserSidePaused(mockDexPool, someUser, isBorrow_), expectedFinalPaused_);

        bool freeze_ = isBorrow_ && requestMask_ == 1;
        uint256 callsAfter_ = wantsPaused_ ? mockDexPool.pauseUserCallCount() : mockDexPool.unpauseUserCallCount();
        assertEq(callsAfter_ - callsBefore_, (!freeze_ && expectedActedMask_ != 0) ? 1 : 0);
        assertEq(
            mockDexPool.updateUserBorrowConfigsCallCount() - configCallsBefore_,
            (freeze_ && expectedActedMask_ != 0) ? 1 : 0
        );
        if (freeze_ && expectedActedMask_ != 0) {
            _assertFrozenRow(address(mockDexPool), someUser, rowBefore_);
        }
    }

    function _assertUserSidePauseMatrix(bool isBorrow_, bool wantsPaused_) internal {
        for (uint256 initial_ = 0; initial_ < 2; initial_++) {
            for (uint256 requestMask_ = 1; requestMask_ < 4; requestMask_++) {
                _assertUserSidePauseMatrixCase(isBorrow_, wantsPaused_, initial_ == 1, requestMask_);
            }
        }
    }

    function _setDexUserPauseState(
        MockDexPool dex_,
        address user_,
        bool supplySidePaused_,
        bool borrowSidePaused_
    ) internal {
        _setDexUserSupplyPauseState(dex_, user_, supplySidePaused_);
        _setDexUserBorrowPauseState(dex_, user_, borrowSidePaused_);
    }

    function _expectedUserPauseMask(
        bool supplyPaused_,
        bool borrowPaused_,
        uint256 requestMask_,
        bool wantsPaused_
    ) internal pure returns (bool finalSupplyPaused_, bool finalBorrowPaused_, uint256 actedMask_) {
        uint256 sideActed_;
        (finalSupplyPaused_, sideActed_) = _expectedUserSideMask(false, supplyPaused_, requestMask_ & 3, wantsPaused_);
        actedMask_ = sideActed_;
        (finalBorrowPaused_, sideActed_) = _expectedUserSideMask(
            true,
            borrowPaused_,
            (requestMask_ >> 2) & 3,
            wantsPaused_
        );
        actedMask_ |= sideActed_ << 2;
    }

    function _callUserPause(bool wantsPaused_, uint256 requestMask_) internal returns (uint256 actedMask_) {
        bool supply_ = requestMask_ & 1 == 1;
        bool withdraw_ = requestMask_ & 2 == 2;
        bool borrow_ = requestMask_ & 4 == 4;
        bool payback_ = requestMask_ & 8 == 8;

        if (wantsPaused_) {
            (, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseUser(
                DEX_ID_1,
                someUser,
                supply_,
                withdraw_,
                borrow_,
                payback_
            );
            return (actedSupply_ ? 1 : 0) | (actedWithdraw_ ? 2 : 0) | (actedBorrow_ ? 4 : 0) | (actedPayback_ ? 8 : 0);
        }

        (, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseUser(
            DEX_ID_1,
            someUser,
            supply_,
            withdraw_,
            borrow_,
            payback_
        );
        return (actedSupply_ ? 1 : 0) | (actedWithdraw_ ? 2 : 0) | (actedBorrow_ ? 4 : 0) | (actedPayback_ ? 8 : 0);
    }

    /// @dev mirrors `_callUserPause` but ignores the returns, so no ABI decode runs under expectRevert.
    function _callUserPauseDiscarding(bool wantsPaused_, uint256 requestMask_) internal {
        bool supply_ = requestMask_ & 1 == 1;
        bool withdraw_ = requestMask_ & 2 == 2;
        bool borrow_ = requestMask_ & 4 == 4;
        bool payback_ = requestMask_ & 8 == 8;

        if (wantsPaused_) {
            pauseAuthDex.pauseUser(DEX_ID_1, someUser, supply_, withdraw_, borrow_, payback_);
        } else {
            pauseAuthDex.unpauseUser(DEX_ID_1, someUser, supply_, withdraw_, borrow_, payback_);
        }
    }

    /// @dev supply side full or not at all; borrow side additionally accepts borrow alone
    function _isAcceptedMask(uint256 requestMask_) internal pure returns (bool) {
        uint256 supplyHalf_ = requestMask_ & 3;
        uint256 borrowHalf_ = (requestMask_ >> 2) & 3;
        return (supplyHalf_ == 0 || supplyHalf_ == 3) && borrowHalf_ != 2;
    }

    function _assertUserPauseMatrixCase(bool wantsPaused_, uint256 initialMask_, uint256 requestMask_) internal {
        bool initialSupplyPaused_ = initialMask_ & 1 == 1;
        bool initialBorrowPaused_ = initialMask_ & 2 == 2;
        _setDexUserPauseState(mockDexPool, someUser, initialSupplyPaused_, initialBorrowPaused_);

        if (!_isAcceptedMask(requestMask_)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    Error.FluidConfigError.selector,
                    ErrorTypes.PauseAuthDex__PartialSideNotSupported
                )
            );
            _callUserPauseDiscarding(wantsPaused_, requestMask_);
            assertEq(_isDexUserSidePaused(mockDexPool, someUser, false), initialSupplyPaused_);
            assertEq(_isDexUserSidePaused(mockDexPool, someUser, true), initialBorrowPaused_);
            return;
        }

        uint256 rowBefore_ = _borrowRow(address(mockDexPool), someUser);
        uint256 callsBefore_ = wantsPaused_ ? mockDexPool.pauseUserCallCount() : mockDexPool.unpauseUserCallCount();
        uint256 configCallsBefore_ = mockDexPool.updateUserBorrowConfigsCallCount();
        (bool expectedSupplyPaused_, bool expectedBorrowPaused_, uint256 expectedActedMask_) = _expectedUserPauseMask(
            initialSupplyPaused_,
            initialBorrowPaused_,
            requestMask_,
            wantsPaused_
        );

        assertEq(_callUserPause(wantsPaused_, requestMask_), expectedActedMask_);
        assertEq(_isDexUserSidePaused(mockDexPool, someUser, false), expectedSupplyPaused_);
        assertEq(_isDexUserSidePaused(mockDexPool, someUser, true), expectedBorrowPaused_);

        // supply and a full borrow side go through the pause bit, borrow alone through the config
        bool freeze_ = wantsPaused_ && ((requestMask_ >> 2) & 3) == 1;
        bool pauseBitActed_ = (expectedActedMask_ & 3) != 0 || (!freeze_ && (expectedActedMask_ & 12) != 0);
        uint256 callsAfter_ = wantsPaused_ ? mockDexPool.pauseUserCallCount() : mockDexPool.unpauseUserCallCount();
        assertEq(callsAfter_ - callsBefore_, pauseBitActed_ ? 1 : 0);
        assertEq(
            mockDexPool.updateUserBorrowConfigsCallCount() - configCallsBefore_,
            (freeze_ && (expectedActedMask_ & 4) != 0) ? 1 : 0
        );
        if (freeze_ && (expectedActedMask_ & 4) != 0) {
            _assertFrozenRow(address(mockDexPool), someUser, rowBefore_);
        }
    }

    function _assertUserPauseMatrix(bool wantsPaused_) internal {
        for (uint256 initialMask_ = 0; initialMask_ < 4; initialMask_++) {
            for (uint256 requestMask_ = 1; requestMask_ < 16; requestMask_++) {
                _assertUserPauseMatrixCase(wantsPaused_, initialMask_, requestMask_);
            }
        }
    }

    // ==================== Constructor tests ====================

    function test_deployment() public view {
        assertEq(address(pauseAuthDex.LIQUIDITY()), address(mockLiquidity));
        assertEq(address(pauseAuthDex.VAULT_FACTORY()), address(mockVaultFactory));
        assertEq(address(pauseAuthDex.DEX_FACTORY()), address(mockDexFactory));
        assertEq(address(pauseAuthDex.SMART_LENDING_FACTORY()), address(mockSmartLendingFactory));
        assertEq(address(pauseAuthDex.AUTH_GATE()), authGate);
        assertEq(pauseAuthDex.pauseAuthContract(), address(this));
    }

    function test_constructor_revertZeroLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuthDex(
            address(0),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory),
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
        new FluidPauseAuthDex(
            address(mockLiquidity),
            address(0),
            address(mockDexFactory),
            address(mockSmartLendingFactory),
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
        new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(0),
            address(mockSmartLendingFactory),
            authGate
        );
    }

    function test_constructor_revertZeroSmartLendingFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
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

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory),
            otherAuthGate_
        );
    }

    // ==================== Admin: setPauseAuthContract ====================

    function test_setPauseAuthContract() public {
        FluidPauseAuthDex fresh_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory),
            authGate
        );
        assertEq(fresh_.pauseAuthContract(), address(0));

        address newPauseAuth_ = makeAddr("newPauseAuth");

        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuthContract(newPauseAuth_);

        vm.prank(TEAM_MULTISIG);
        fresh_.setPauseAuthContract(newPauseAuth_);
        assertEq(fresh_.pauseAuthContract(), newPauseAuth_);
    }

    function test_setPauseAuthContract_multisig2CanSet() public {
        FluidPauseAuthDex fresh_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory),
            authGate
        );

        vm.prank(TEAM_MULTISIG2);
        fresh_.setPauseAuthContract(address(this));
        assertEq(fresh_.pauseAuthContract(), address(this));
    }

    function test_setPauseAuthContract_revertNotMultisig() public {
        FluidPauseAuthDex fresh_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory),
            authGate
        );

        vm.prank(unauthorizedUser);
        vm.expectRevert(Access__Unauthorized.selector);
        fresh_.setPauseAuthContract(makeAddr("newPauseAuth"));
    }

    function test_setPauseAuthContract_revertAlreadySet() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.setPauseAuthContract(makeAddr("anotherAddr"));
    }

    function test_setPauseAuthContract_revertZeroAddress() public {
        FluidPauseAuthDex fresh_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory),
            authGate
        );

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        fresh_.setPauseAuthContract(address(0));
    }

    // ==================== pauseSwapAndArbitrage ====================

    function test_pauseSwapAndArbitrage() public {
        (address dex_, bool acted_) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertTrue(acted_);
        assertTrue(mockDexPool.swapPaused());
    }

    function test_pauseSwapAndArbitrage_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
    }

    function test_pauseSwapAndArbitrage_revertInvalidDexId() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseSwapAndArbitrage(999);
    }

    function test_pauseSwapAndArbitrage_skipsAlreadyPaused() public {
        pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertTrue(mockDexPool.swapPaused());

        (address dex_, bool acted_) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertFalse(acted_);
    }

    // ==================== unpauseSwapAndArbitrage ====================

    function test_unpauseSwapAndArbitrage() public {
        pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertTrue(mockDexPool.swapPaused());

        (address dex_, bool acted_) = pauseAuthDex.unpauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertTrue(acted_);
        assertFalse(mockDexPool.swapPaused());
    }

    function test_unpauseSwapAndArbitrage_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.unpauseSwapAndArbitrage(DEX_ID_1);
    }

    function test_unpauseSwapAndArbitrage_revertInvalidDexId() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseSwapAndArbitrage(999);
    }

    function test_unpauseSwapAndArbitrage_skipsAlreadyUnpaused() public {
        (address dex_, bool acted_) = pauseAuthDex.unpauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertFalse(acted_);
    }

    // ==================== pauseVault ====================

    function test_pauseVault_supplyDex() public {
        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);
        assertEq(vault_, address(mockVaultSupplyDex));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);

        (address user, bool supply, bool borrow) = mockDexPool.lastPauseUserCall();
        assertEq(user, address(mockVaultSupplyDex));
        assertTrue(supply);
        assertFalse(borrow);
    }

    function test_pauseVault_borrowDex() public {
        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_BORROW_DEX_ID, false, false, true, true);
        assertEq(vault_, address(mockVaultBorrowDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address user, bool supply, bool borrow) = mockDexPool2.lastPauseUserCall();
        assertEq(user, address(mockVaultBorrowDex));
        assertFalse(supply);
        assertTrue(borrow);
    }

    function test_pauseVault_bothDex() public {
        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_BOTH_DEX_ID, true, true, true, true);
        assertEq(vault_, address(mockVaultBothDex));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address supplyUser, bool supplyS, bool supplyB) = mockDexPool.lastPauseUserCall();
        assertEq(supplyUser, address(mockVaultBothDex));
        assertTrue(supplyS);
        assertFalse(supplyB);

        (address borrowUser, bool borrowS, bool borrowB) = mockDexPool2.lastPauseUserCall();
        assertEq(borrowUser, address(mockVaultBothDex));
        assertFalse(borrowS);
        assertTrue(borrowB);
    }

    function test_pauseVault_sameDex_callsEachSide() public {
        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_SAME_DEX_ID, true, true, true, true);
        assertEq(vault_, address(mockVaultSameDex));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address user, bool supply, bool borrow) = mockDexPool.lastPauseUserCall();
        assertEq(user, address(mockVaultSameDex));
        assertFalse(supply);
        assertTrue(borrow);
        assertEq(mockDexPool.pauseUserCallCount(), 2);
    }

    function test_pauseVault_onlySupply() public {
        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_BOTH_DEX_ID, true, true, false, false);
        assertEq(vault_, address(mockVaultBothDex));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertFalse(actedBorrow_);

        (address supplyUser, bool supplyS, ) = mockDexPool.lastPauseUserCall();
        assertEq(supplyUser, address(mockVaultBothDex));
        assertTrue(supplyS);

        (address borrowUser, , ) = mockDexPool2.lastPauseUserCall();
        assertEq(borrowUser, address(0));
    }

    function test_pauseVault_onlyBorrow() public {
        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_BOTH_DEX_ID, false, false, true, true);
        assertEq(vault_, address(mockVaultBothDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address supplyUser, , ) = mockDexPool.lastPauseUserCall();
        assertEq(supplyUser, address(0));

        (address borrowUser, bool borrowS, bool borrowB) = mockDexPool2.lastPauseUserCall();
        assertEq(borrowUser, address(mockVaultBothDex));
        assertFalse(borrowS);
        assertTrue(borrowB);
    }

    /// @dev borrow-only on a smart-debt leg is the limits freeze; the pause bit stays open
    function test_pauseVault_borrowOnlyFreezesDexLeg() public {
        address dex_ = address(mockDexPool2);
        address user_ = address(mockVaultBothDex);
        uint256 before_ = _borrowRow(dex_, user_);

        vm.expectEmit(true, true, true, true, address(pauseAuthDex));
        emit LogFreezeDexUserBorrow(dex_, user_, before_ & USER_BORROW_CONFIG_MASK);
        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_BOTH_DEX_ID, false, false, true, false);
        assertEq(vault_, user_);
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool2.pauseUserCallCount(), 0);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 0);
        _assertFrozenRow(dex_, user_, before_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(dex_, user_), before_ & USER_BORROW_CONFIG_MASK);
        assertTrue(pauseAuthDex.isDexUserBorrowFrozen(dex_, user_));
    }

    function test_pauseVault_RevertIfPaybackWithoutBorrow() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, false, false, false, true);
    }

    /// @dev T4 on one pool: supply side via the bit, borrow side via the config
    function test_pauseVault_sameDex_supplySidePauseWithBorrowFreeze() public {
        address dex_ = address(mockDexPool);
        address user_ = address(mockVaultSameDex);
        uint256 before_ = _borrowRow(dex_, user_);

        (, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseVault(
            VAULT_SAME_DEX_ID,
            true,
            true,
            true,
            false
        );
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertFalse(actedPayback_);

        (address pausedUser_, bool pausedSupply_, bool pausedBorrow_) = mockDexPool.lastPauseUserCall();
        assertEq(pausedUser_, user_);
        assertTrue(pausedSupply_);
        assertFalse(pausedBorrow_);
        assertTrue(_isDexUserSidePaused(mockDexPool, user_, false));
        _assertFrozenRow(dex_, user_, before_);
    }

    function test_pauseVault_RevertIfSupplyWithoutWithdraw() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, true, false, false, false);
    }

    /// @dev the tier-1 borrow-only shape must survive on every side that routes through Liquidity.
    function test_pauseVault_borrowOnlyNoDexLegDoesNotRevert() public {
        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseVault(
            VAULT_NO_DEX_ID,
            false,
            false,
            true,
            false
        );
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
    }

    function test_pauseVault_borrowOnlyLiquidityBorrowLegDoesNotRevert() public {
        uint256 callsBefore_ = mockDexPool.pauseUserCallCount();

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseVault(
            VAULT_SUPPLY_DEX_ID,
            false,
            false,
            true,
            false
        );
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
        assertEq(mockDexPool.pauseUserCallCount(), callsBefore_);
    }

    function test_pauseVault_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseVault(VAULT_NO_DEX_ID, false, false, false, false);
    }

    function test_pauseVault_revertZeroVaultAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseVault(UNREGISTERED_VAULT_ID, true, true, false, false);
    }

    function test_pauseVault_silentReturnT1Vault() public {
        uint256 callCountBefore1 = mockDexPool.pauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_T1_ID, true, true, true, true);
        assertEq(vault_, address(mockVaultT1));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.pauseUserCallCount(), callCountBefore2);
    }

    function test_pauseVault_silentReturnNoDex() public {
        uint256 callCountBefore1 = mockDexPool.pauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_NO_DEX_ID, true, true, true, true);
        assertEq(vault_, address(mockVaultNoDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.pauseUserCallCount(), callCountBefore2);
    }

    function test_pauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.pauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);
    }

    function test_pauseVault_silentNoOpWhenIsDexReverts() public {
        MockRevertingDexFactory revertingDexFactory_ = new MockRevertingDexFactory();
        revertingDexFactory_.setDex(DEX_ID_1, address(mockDexPool));

        FluidPauseAuthDex pauseAuthDex_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(revertingDexFactory_),
            address(mockSmartLendingFactory),
            authGate
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuthDex_.setPauseAuthContract(address(this));

        uint256 callCountBefore = mockDexPool.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex_
            .pauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);
        assertEq(vault_, address(mockVaultSupplyDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);

        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore);
    }

    function test_pauseVault_silentReturnRevertingVault() public {
        uint256 callCountBefore1 = mockDexPool.pauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_REVERTING_ID, true, true, true, true);
        assertEq(vault_, address(mockRevertingVault));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.pauseUserCallCount(), callCountBefore2);
    }

    function test_pauseVault_RevertIfNewerVaultConstantsRevert() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseVault(VAULT_NEWER_REVERTING_ID, true, true, false, false);
    }

    function test_unpauseVault_RevertIfNewerVaultConstantsRevert() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseVault(VAULT_NEWER_REVERTING_ID, true, true, false, false);
    }

    /// @dev a supply leg that is a contract but not a registered DEX must be skipped, not called — the
    ///      fixture has no pool interface at all, so any call to it would revert instead of returning false.
    function test_pauseVault_silentReturnNonDexSupplyLeg() public {
        assertFalse(mockDexFactory.isDex(address(mockSmartLendingFactory)));

        (address vault_, bool actedSupply_, bool actedWithdraw_, , ) = pauseAuthDex.pauseVault(
            VAULT_NON_DEX_SUPPLY_ID,
            true,
            true,
            false,
            false
        );

        assertEq(vault_, address(mockVaultNonDexSupply));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
    }

    function test_pauseVault_returnsFalseWhenAlreadyPaused() public {
        pauseAuthDex.pauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);
        assertEq(vault_, address(mockVaultSupplyDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
    }

    function test_pauseVault_undefinedDexLegSkips() public {
        mockDexPool.setStorageSlot(keccak256(abi.encode(address(mockVaultSupplyDex), uint256(3))), 0);

        uint256 callCountBefore = mockDexPool.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);
        assertEq(vault_, address(mockVaultSupplyDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore);
    }

    // ==================== unpauseVault ====================

    function test_unpauseVault_supplyDex() public {
        pauseAuthDex.pauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);
        assertEq(vault_, address(mockVaultSupplyDex));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);

        (address user, bool supply, bool borrow) = mockDexPool.lastUnpauseUserCall();
        assertEq(user, address(mockVaultSupplyDex));
        assertTrue(supply);
        assertFalse(borrow);
    }

    function test_unpauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.unpauseVault(VAULT_SUPPLY_DEX_ID, true, true, false, false);
    }

    function test_unpauseVault_borrowDex() public {
        pauseAuthDex.pauseVault(VAULT_BORROW_DEX_ID, false, false, true, true);

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_BORROW_DEX_ID, false, false, true, true);
        assertEq(vault_, address(mockVaultBorrowDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address user, bool supply, bool borrow) = mockDexPool2.lastUnpauseUserCall();
        assertEq(user, address(mockVaultBorrowDex));
        assertFalse(supply);
        assertTrue(borrow);
    }

    function test_unpauseVault_bothDex() public {
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, true, true, true, true);

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_BOTH_DEX_ID, true, true, true, true);
        assertEq(vault_, address(mockVaultBothDex));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address supplyUser, bool supplyS, bool supplyB) = mockDexPool.lastUnpauseUserCall();
        assertEq(supplyUser, address(mockVaultBothDex));
        assertTrue(supplyS);
        assertFalse(supplyB);

        (address borrowUser, bool borrowS, bool borrowB) = mockDexPool2.lastUnpauseUserCall();
        assertEq(borrowUser, address(mockVaultBothDex));
        assertFalse(borrowS);
        assertTrue(borrowB);
    }

    function test_unpauseVault_sameDex_callsEachSide() public {
        pauseAuthDex.pauseVault(VAULT_SAME_DEX_ID, true, true, true, true);

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_SAME_DEX_ID, true, true, true, true);
        assertEq(vault_, address(mockVaultSameDex));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address user, bool supply, bool borrow) = mockDexPool.lastUnpauseUserCall();
        assertEq(user, address(mockVaultSameDex));
        assertFalse(supply);
        assertTrue(borrow);
        assertEq(mockDexPool.unpauseUserCallCount(), 2);
    }

    function test_unpauseVault_borrowOnlyRestoresDexLeg() public {
        address dex_ = address(mockDexPool2);
        address user_ = address(mockVaultBothDex);
        uint256 before_ = _borrowRow(dex_, user_);
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, false, false, true, false);

        vm.expectEmit(true, true, true, true, address(pauseAuthDex));
        emit LogRestoreDexUserBorrow(dex_, user_, before_ & USER_BORROW_CONFIG_MASK);
        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_BOTH_DEX_ID, false, false, true, false);
        assertEq(vault_, user_);
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(_borrowRow(dex_, user_), before_);
        assertEq(mockDexPool2.unpauseUserCallCount(), 0);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(dex_, user_), 0);
        assertFalse(pauseAuthDex.isDexUserBorrowFrozen(dex_, user_));
    }

    /// @dev escalating to a pause keeps the snapshot; the whole-side unpause clears the bit and restores in one go
    function test_unpauseVault_wholeSideAlsoRestoresFreeze() public {
        address dex_ = address(mockDexPool2);
        address user_ = address(mockVaultBothDex);
        uint256 before_ = _borrowRow(dex_, user_);
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, false, false, true, false);
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, false, false, true, true);
        assertTrue(_isDexUserSidePaused(mockDexPool2, user_, true));
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(dex_, user_), before_ & USER_BORROW_CONFIG_MASK);

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseVault(
            VAULT_BOTH_DEX_ID,
            false,
            false,
            true,
            true
        );
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        assertEq(_borrowRow(dex_, user_), before_);
        assertEq(mockDexPool2.unpauseUserCallCount(), 1);
        assertEq(mockDexPool2.pauseUserCallCount(), 1);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(dex_, user_), 0);
    }

    function test_unpauseVault_onlyBorrow() public {
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, false, false, true, true);

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_BOTH_DEX_ID, false, false, true, true);
        assertEq(vault_, address(mockVaultBothDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address supplyUser, , ) = mockDexPool.lastUnpauseUserCall();
        assertEq(supplyUser, address(0));

        (address borrowUser, bool borrowS, bool borrowB) = mockDexPool2.lastUnpauseUserCall();
        assertEq(borrowUser, address(mockVaultBothDex));
        assertFalse(borrowS);
        assertTrue(borrowB);
    }

    function test_unpauseVault_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseVault(VAULT_NO_DEX_ID, false, false, false, false);
    }

    function test_unpauseVault_revertZeroVaultAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseVault(UNREGISTERED_VAULT_ID, true, true, false, false);
    }

    function test_unpauseVault_silentReturnT1Vault() public {
        uint256 callCountBefore1 = mockDexPool.unpauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.unpauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_T1_ID, true, true, true, true);
        assertEq(vault_, address(mockVaultT1));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool.unpauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.unpauseUserCallCount(), callCountBefore2);
    }

    function test_unpauseVault_silentReturnNoDex() public {
        uint256 callCountBefore1 = mockDexPool.unpauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.unpauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_NO_DEX_ID, true, true, true, true);
        assertEq(vault_, address(mockVaultNoDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool.unpauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.unpauseUserCallCount(), callCountBefore2);
    }

    function test_unpauseVault_silentNoOpWhenIsDexReverts() public {
        MockRevertingDexFactory revertingDexFactory_ = new MockRevertingDexFactory();
        revertingDexFactory_.setDex(DEX_ID_1, address(mockDexPool));

        FluidPauseAuthDex pauseAuthDex_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(revertingDexFactory_),
            address(mockSmartLendingFactory),
            authGate
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuthDex_.setPauseAuthContract(address(this));

        uint256 callCountBefore = mockDexPool.unpauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, ) = pauseAuthDex_.unpauseVault(
            VAULT_SUPPLY_DEX_ID,
            true,
            true,
            false,
            false
        );
        assertEq(vault_, address(mockVaultSupplyDex));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);

        assertEq(mockDexPool.unpauseUserCallCount(), callCountBefore);
    }

    function test_unpauseVault_silentReturnRevertingVault() public {
        uint256 callCountBefore1 = mockDexPool.unpauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.unpauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseVault(VAULT_REVERTING_ID, true, true, true, true);
        assertEq(vault_, address(mockRevertingVault));
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool.unpauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.unpauseUserCallCount(), callCountBefore2);
    }

    // ==================== pauseSmartLending ====================

    function test_pauseSmartLending() public {
        (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) = pauseAuthDex.pauseSmartLending(
            DEX_ID_1,
            true,
            true
        );
        assertEq(dex_, address(mockDexPool));
        assertEq(smartLending_, smartLending);
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);

        (address user, bool supply, bool borrow) = mockDexPool.lastPauseUserCall();
        assertEq(user, smartLending);
        assertTrue(supply);
        assertFalse(borrow);
    }

    function test_pauseSmartLending_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.pauseSmartLending(DEX_ID_1, true, true);
    }

    function test_pauseSmartLending_correctDexAndSmartLendingResolution() public {
        (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) = pauseAuthDex.pauseSmartLending(
            DEX_ID_2,
            true,
            true
        );
        assertEq(dex_, address(mockDexPool2));
        assertEq(smartLending_, smartLending2);
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);

        (address user, bool supply, ) = mockDexPool2.lastPauseUserCall();
        assertEq(user, smartLending2);
        assertTrue(supply);
    }

    function test_pauseSmartLending_RevertIfSupplyWithoutWithdraw() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.pauseSmartLending(DEX_ID_1, true, false);
    }

    function test_pauseSmartLending_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseSmartLending(DEX_ID_1, false, false);
    }

    function test_pauseSmartLending_revertZeroSmartLendingAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseSmartLending(DEX_ID_NO_SL, true, true);
    }

    function test_pauseSmartLending_skipsAlreadyPaused() public {
        pauseAuthDex.pauseSmartLending(DEX_ID_1, true, true);

        (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) = pauseAuthDex.pauseSmartLending(
            DEX_ID_1,
            true,
            true
        );
        assertEq(dex_, address(mockDexPool));
        assertEq(smartLending_, smartLending);
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
    }

    function test_pauseSmartLending_noRowSkips() public {
        mockDexPool.setStorageSlot(keccak256(abi.encode(smartLending, uint256(3))), 0);

        uint256 callCountBefore = mockDexPool.pauseUserCallCount();

        (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) = pauseAuthDex.pauseSmartLending(
            DEX_ID_1,
            true,
            true
        );
        assertEq(dex_, address(mockDexPool));
        assertEq(smartLending_, smartLending);
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore);
    }

    // ==================== unpauseSmartLending ====================

    function test_unpauseSmartLending() public {
        pauseAuthDex.pauseSmartLending(DEX_ID_1, true, true);

        (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) = pauseAuthDex
            .unpauseSmartLending(DEX_ID_1, true, true);
        assertEq(dex_, address(mockDexPool));
        assertEq(smartLending_, smartLending);
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);

        (address user, bool supply, bool borrow) = mockDexPool.lastUnpauseUserCall();
        assertEq(user, smartLending);
        assertTrue(supply);
        assertFalse(borrow);
    }

    function test_unpauseSmartLending_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.unpauseSmartLending(DEX_ID_1, true, true);
    }

    function test_unpauseSmartLending_RevertIfSupplyWithoutWithdraw() public {
        pauseAuthDex.pauseSmartLending(DEX_ID_1, true, true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.unpauseSmartLending(DEX_ID_1, true, false);
    }

    function test_unpauseSmartLending_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseSmartLending(DEX_ID_1, false, false);
    }

    function test_unpauseSmartLending_revertZeroSmartLendingAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseSmartLending(DEX_ID_NO_SL, true, true);
    }

    // ==================== pauseUser ====================

    function test_pauseUser() public {
        (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseUser(DEX_ID_1, someUser, true, true, true, true);
        assertEq(dex_, address(mockDexPool));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address user, bool supply, bool borrow) = mockDexPool.lastPauseUserCall();
        assertEq(user, someUser);
        assertTrue(supply);
        assertTrue(borrow);
    }

    function test_pauseUser_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, true, true, false, false);
    }

    function test_pauseUser_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, false, false);
    }

    function test_pauseUser_revertInvalidDexId() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(999, someUser, true, true, false, false);
    }

    function test_pauseUser_borrowOnlyFreezesLimits() public {
        address dex_ = address(mockDexPool);
        uint256 before_ = _borrowRow(dex_, someUser);

        vm.expectEmit(true, true, true, true, address(pauseAuthDex));
        emit LogFreezeDexUserBorrow(dex_, someUser, before_ & USER_BORROW_CONFIG_MASK);
        (address dexOut_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .pauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertEq(dexOut_, dex_);
        assertFalse(actedSupply_);
        assertFalse(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool.pauseUserCallCount(), 0);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 1);
        _assertFrozenRow(dex_, someUser, before_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(dex_, someUser), before_ & USER_BORROW_CONFIG_MASK);
        assertTrue(pauseAuthDex.isDexUserBorrowFrozen(dex_, someUser));
    }

    function test_pauseUser_RevertIfPaybackOnly() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, false, true);
    }

    function test_pauseUser_RevertIfSupplyOnly() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, true, false, false, false);
    }

    function test_pauseUser_RevertIfWithdrawOnly() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, true, false, false);
    }

    /// @dev shape is rejected before any state read, so an undefined user reverts the same way.
    function test_pauseUser_RevertIfPartialSideUndefinedUser() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, address(0xdead), true, false, false, false);
    }

    function test_pauseUser_fullBorrowSidePauses() public {
        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            true
        );

        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);
        _assertDexUserBorrowPauseState(mockDexPool, someUser, true);
        _assertDexUserSupplyPauseState(mockDexPool, someUser, false);

        (address user_, bool supply_, bool borrow_) = mockDexPool.lastPauseUserCall();
        assertEq(user_, someUser);
        assertFalse(supply_);
        assertTrue(borrow_);
        assertEq(mockDexPool.pauseUserCallCount(), 1);
    }

    function test_pauseUser_fullSupplySidePauses() public {
        (, bool actedSupply_, bool actedWithdraw_, , ) = pauseAuthDex.pauseUser(
            DEX_ID_1,
            someUser,
            true,
            true,
            false,
            false
        );

        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        _assertDexUserSupplyPauseState(mockDexPool, someUser, true);
        _assertDexUserBorrowPauseState(mockDexPool, someUser, false);

        (address user_, bool supply_, bool borrow_) = mockDexPool.lastPauseUserCall();
        assertEq(user_, someUser);
        assertTrue(supply_);
        assertFalse(borrow_);
        assertEq(mockDexPool.pauseUserCallCount(), 1);
    }

    function test_pauseUser_RevertIfUndefinedUser() public {
        address undefined_ = makeAddr("undefinedDexUser");
        assertEq(mockDexPool.readFromStorage(keccak256(abi.encode(undefined_, uint256(3)))), 0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, undefined_, true, true, false, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, undefined_, false, false, true, true);
    }

    function test_unpauseUser_RevertIfUndefinedUser() public {
        address undefined_ = makeAddr("undefinedDexUser");
        assertEq(mockDexPool.readFromStorage(keccak256(abi.encode(undefined_, uint256(5)))), 0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseUser(DEX_ID_1, undefined_, false, false, true, true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseUser(DEX_ID_1, undefined_, true, true, false, false);
    }

    function test_pauseUser_RevertIfRequestedSideHasNoRow() public {
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), 0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, true, true, true, true);
    }

    function test_pauseUser_RevertIfRequestedSupplySideHasNoRow() public {
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(3))), 0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, true, true, true, true);
    }

    // ==================== DEX revert handling ====================

    /// @dev the executor is a global auth on the factory, so an unregistered pool is a broken deployment
    function test_pauseUser_RevertIfDexNotAnAuth() public {
        bytes memory revertData_ = abi.encodeWithSelector(
            MockRevertingDexPool.FluidDexError.selector,
            DexErrorTypes.DexT1__NotAnAuth
        );
        mockRevertingDexPool.setRevertData(revertData_);

        vm.expectRevert(revertData_);
        pauseAuthDex.pauseUser(DEX_ID_REVERTING, someUser, true, true, true, true);
    }

    function test_unpauseUser_RevertIfDexNotAnAuth() public {
        _setRevertingDexUserSidesPaused();
        bytes memory revertData_ = abi.encodeWithSelector(
            MockRevertingDexPool.FluidDexError.selector,
            DexErrorTypes.DexT1__NotAnAuth
        );
        mockRevertingDexPool.setRevertData(revertData_);

        vm.expectRevert(revertData_);
        pauseAuthDex.unpauseUser(DEX_ID_REVERTING, someUser, true, true, true, true);
    }

    function test_pauseUser_RevertIfDexRevertsWithOtherDexErrorId() public {
        bytes memory revertData_ = abi.encodeWithSelector(
            MockRevertingDexPool.FluidDexError.selector,
            DexErrorTypes.DexT1__AlreadyEntered
        );
        mockRevertingDexPool.setRevertData(revertData_);

        vm.expectRevert(revertData_);
        pauseAuthDex.pauseUser(DEX_ID_REVERTING, someUser, true, true, true, true);
    }

    function test_unpauseUser_RevertIfDexRevertsWithOtherDexErrorId() public {
        _setRevertingDexUserSidesPaused();
        bytes memory revertData_ = abi.encodeWithSelector(
            MockRevertingDexPool.FluidDexError.selector,
            DexErrorTypes.DexT1__AlreadyEntered
        );
        mockRevertingDexPool.setRevertData(revertData_);

        vm.expectRevert(revertData_);
        pauseAuthDex.unpauseUser(DEX_ID_REVERTING, someUser, true, true, true, true);
    }

    function test_pauseUser_RevertIfDexRevertsWithNonFluidError() public {
        mockRevertingDexPool.setRevertData(abi.encodeWithSignature("Error(string)", "dex blew up"));

        vm.expectRevert("dex blew up");
        pauseAuthDex.pauseUser(DEX_ID_REVERTING, someUser, true, true, true, true);
    }

    function test_pauseUser_RevertIfDexRevertsWithoutData() public {
        mockRevertingDexPool.setRevertData("");

        (bool ok_, bytes memory returnData_) = address(pauseAuthDex).call(
            abi.encodeWithSelector(
                FluidPauseAuthDex.pauseUser.selector,
                DEX_ID_REVERTING,
                someUser,
                true,
                true,
                true,
                true
            )
        );

        assertFalse(ok_);
        assertEq(returnData_.length, 0);
    }

    function _setRevertingDexUserSidesPaused() internal {
        mockRevertingDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(3))), _encodeUserSideState(true));
        mockRevertingDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), _encodeUserSideState(true));
    }

    // ==================== unpauseUser ====================

    function test_unpauseUser() public {
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, true, true, true, true);

        (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseUser(DEX_ID_1, someUser, true, true, true, true);
        assertEq(dex_, address(mockDexPool));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        (address user, bool supply, bool borrow) = mockDexPool.lastUnpauseUserCall();
        assertEq(user, someUser);
        assertTrue(supply);
        assertTrue(borrow);
    }

    function test_unpauseUser_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.unpauseUser(DEX_ID_1, someUser, true, true, false, false);
    }

    function test_unpauseUser_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, false, false);
    }

    function test_unpauseUser_revertInvalidDexId() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseUser(999, someUser, true, true, false, false);
    }

    function test_unpauseUser_supplySidePaused_unpauseBothActs() public {
        _setDexUserSupplyPauseState(mockDexPool, someUser, true);

        (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = pauseAuthDex
            .unpauseUser(DEX_ID_1, someUser, true, true, false, false);

        assertEq(dex_, address(mockDexPool));
        assertTrue(actedSupply_);
        assertTrue(actedWithdraw_);
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
        _assertDexUserSupplyPauseState(mockDexPool, someUser, false);
        assertEq(mockDexPool.unpauseUserCallCount(), 1);
    }

    function test_unpauseUser_RevertIfWithdrawOnly() public {
        _setDexUserSupplyPauseState(mockDexPool, someUser, true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, true, false, false);
    }

    function test_unpauseUser_RevertIfSupplyOnly() public {
        _setDexUserSupplyPauseState(mockDexPool, someUser, true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.unpauseUser(DEX_ID_1, someUser, true, false, false, false);
    }

    function test_unpauseUser_borrowOnlyRestoresLimits() public {
        address dex_ = address(mockDexPool);
        uint256 before_ = _borrowRow(dex_, someUser);
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, false);

        vm.expectEmit(true, true, true, true, address(pauseAuthDex));
        emit LogRestoreDexUserBorrow(dex_, someUser, before_ & USER_BORROW_CONFIG_MASK);
        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            false
        );
        assertTrue(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(_borrowRow(dex_, someUser), before_);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 2);
        assertEq(mockDexPool.unpauseUserCallCount(), 0);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(dex_, someUser), 0);
        assertFalse(pauseAuthDex.isDexUserBorrowFrozen(dex_, someUser));
    }

    function test_unpauseUser_RevertIfPaybackOnly() public {
        _setDexUserBorrowPauseState(mockDexPool, someUser, true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__PartialSideNotSupported)
        );
        pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, false, true);
    }

    function test_pauseUser_supplySide_allPauseStateCombinations() public {
        _assertUserSidePauseMatrix(false, true);
    }

    function test_pauseUser_borrowSide_allPauseStateCombinations() public {
        _assertUserSidePauseMatrix(true, true);
    }

    function test_unpauseUser_supplySide_allPauseStateCombinations() public {
        _assertUserSidePauseMatrix(false, false);
    }

    function test_unpauseUser_borrowSide_allPauseStateCombinations() public {
        _assertUserSidePauseMatrix(true, false);
    }

    function test_pauseUser_allFourFlagCombinations() public {
        _assertUserPauseMatrix(true);
    }

    function test_unpauseUser_allFourFlagCombinations() public {
        _assertUserPauseMatrix(false);
    }

    // ==================== Borrow-limit freeze semantics ====================

    function _freezeSomeUser() internal returns (uint256 before_) {
        before_ = _borrowRow(address(mockDexPool), someUser);
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, false);
    }

    function test_pauseUser_freezeIsIdempotent() public {
        uint256 before_ = _freezeSomeUser();

        (, , , bool actedBorrow_, ) = pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertFalse(actedBorrow_);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 1);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), before_ & USER_BORROW_CONFIG_MASK);
    }

    /// @dev a paused side already blocks more than the freeze would
    function test_pauseUser_freezeSkipsPausedSide() public {
        _setDexUserBorrowPauseState(mockDexPool, someUser, true);
        uint256 before_ = _borrowRow(address(mockDexPool), someUser);

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            false
        );
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 0);
        assertEq(_borrowRow(address(mockDexPool), someUser), before_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);
    }

    function test_pauseUser_freezeRevertIfUndefinedUser() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, address(0xdead), false, false, true, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseUser(DEX_ID_1, address(0xdead), false, false, true, false);
    }

    /// @dev the preset with no snapshot is a governance-parked user: not ours, nothing to restore
    function test_pauseUser_freezeSkipsPresetParkedWithoutSnapshot() public {
        uint256 parked_ = _encodeUserBorrowRow(false, FREEZE_PERCENT, FREEZE_DURATION, FREEZE_BASE, FREEZE_MAX);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), parked_);

        (, , , bool actedBorrow_, ) = pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertFalse(actedBorrow_);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 0);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);
        assertFalse(pauseAuthDex.isDexUserBorrowFrozen(address(mockDexPool), someUser));

        (, , , actedBorrow_, ) = pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertFalse(actedBorrow_);
        assertEq(_borrowRow(address(mockDexPool), someUser), parked_);
    }

    /// @dev no special case for a max already below the preset's: the preset is written as is
    function test_pauseUser_freezeAppliesPresetOverLowerMax() public {
        uint256 row_ = _encodeUserBorrowRow(false, DEFAULT_EXPAND_PERCENT, DEFAULT_EXPAND_DURATION, 5, 5);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), row_);

        (, , , bool actedBorrow_, ) = pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertTrue(actedBorrow_);
        _assertFrozenRow(address(mockDexPool), someUser, row_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), row_ & USER_BORROW_CONFIG_MASK);
    }

    /// @dev a direct rewrite while frozen (marker gone) is the newest real config, so it becomes the snapshot
    function test_pauseUser_freezeAfterExternalRewriteResnapshots() public {
        uint256 first_ = _freezeSomeUser();
        uint256 rewritten_ = _encodeUserBorrowRow(false, 1000, 3600, 1_000e18, 2_000e18);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), rewritten_);

        (, , , bool actedBorrow_, ) = pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertTrue(actedBorrow_);
        _assertFrozenRow(address(mockDexPool), someUser, rewritten_);
        assertEq(
            pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser),
            rewritten_ & USER_BORROW_CONFIG_MASK
        );
        assertTrue((first_ & USER_BORROW_CONFIG_MASK) != (rewritten_ & USER_BORROW_CONFIG_MASK));

        pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertEq(_borrowRow(address(mockDexPool), someUser), rewritten_);
    }

    /// @dev a FluidLimitsAuthDex nudge of the dust values is a config change like any other: the unpause keeps it
    function test_unpauseUser_dropsSnapshotIfFrozenConfigNudged() public {
        _freezeSomeUser();
        uint256 nudged_ = _encodeUserBorrowRow(false, FREEZE_PERCENT, FREEZE_DURATION, 12, 24);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), nudged_);
        assertFalse(pauseAuthDex.isDexUserBorrowFrozen(address(mockDexPool), someUser));

        (, , , bool actedBorrow_, ) = pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertFalse(actedBorrow_);
        assertEq(_borrowRow(address(mockDexPool), someUser), nudged_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 1);
    }

    function test_pauseUser_freezeRevertIfDexNotAnAuth() public {
        bytes memory revertData_ = abi.encodeWithSelector(
            MockRevertingDexPool.FluidDexError.selector,
            DexErrorTypes.DexT1__NotAnAuth
        );
        mockRevertingDexPool.setRevertData(revertData_);

        vm.expectRevert(revertData_);
        pauseAuthDex.pauseUser(DEX_ID_REVERTING, someUser, false, false, true, false);
    }

    function test_pauseUser_freezeRevertIfDexRevertsWithOtherDexErrorId() public {
        mockRevertingDexPool.setRevertData(
            abi.encodeWithSelector(MockRevertingDexPool.FluidDexError.selector, DexErrorTypes.DexT1Admin__InvalidParams)
        );

        vm.expectRevert(
            abi.encodeWithSelector(MockRevertingDexPool.FluidDexError.selector, DexErrorTypes.DexT1Admin__InvalidParams)
        );
        pauseAuthDex.pauseUser(DEX_ID_REVERTING, someUser, false, false, true, false);
    }

    function test_unpauseUser_restoreWithoutSnapshotNoOps() public {
        uint256 before_ = _borrowRow(address(mockDexPool), someUser);

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            false
        );
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 0);
        assertEq(_borrowRow(address(mockDexPool), someUser), before_);
    }

    /// @dev a direct rewrite behind the freeze is the newest config, so the unpause keeps it and drops the snapshot
    function test_unpauseUser_dropsSnapshotIfFrozenConfigChanged() public {
        _freezeSomeUser();
        uint256 rewritten_ = _encodeUserBorrowRow(false, 1000, 3600, 1_000e18, 2_000e18);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), rewritten_);
        assertFalse(pauseAuthDex.isDexUserBorrowFrozen(address(mockDexPool), someUser));

        (, , , bool actedBorrow_, ) = pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertFalse(actedBorrow_);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), 1);
        assertEq(_borrowRow(address(mockDexPool), someUser), rewritten_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);

        // a fresh freeze then comes back to the rewritten config
        (, , , actedBorrow_, ) = pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertTrue(actedBorrow_);
        (, , , actedBorrow_, ) = pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertTrue(actedBorrow_);
        assertEq(_borrowRow(address(mockDexPool), someUser), rewritten_);
    }

    function test_unpauseUser_borrowOnlyDropsSnapshotOnPausedSide() public {
        _freezeSomeUser();
        uint256 rewritten_ = _encodeUserBorrowRow(false, 1000, 3600, 1_000e18, 2_000e18);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), rewritten_);
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, true);

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            false
        );
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
        assertTrue(_isDexUserSidePaused(mockDexPool, someUser, true));
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);
    }

    function test_unpauseUser_wholeSideDropsSnapshotIfFrozenConfigChanged() public {
        uint256 before_ = _freezeSomeUser();
        uint256 rewritten_ = _encodeUserBorrowRow(false, 1000, 3600, 1_000e18, 2_000e18);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), rewritten_);

        pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, true);
        assertTrue(_isDexUserSidePaused(mockDexPool, someUser, true));

        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), before_ & USER_BORROW_CONFIG_MASK);

        uint256 configCalls_ = mockDexPool.updateUserBorrowConfigsCallCount();
        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            true
        );
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);
        assertFalse(_isDexUserSidePaused(mockDexPool, someUser, true));
        assertEq(
            _borrowRow(address(mockDexPool), someUser) & USER_BORROW_CONFIG_MASK,
            rewritten_ & USER_BORROW_CONFIG_MASK
        );
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), configCalls_);
        assertFalse(pauseAuthDex.isDexUserBorrowFrozen(address(mockDexPool), someUser));
    }

    function test_unpauseUser_wholeSideDropsSnapshotOnOpenSide() public {
        uint256 before_ = _freezeSomeUser();
        uint256 rewritten_ = _encodeUserBorrowRow(false, 1000, 3600, 1_000e18, 2_000e18);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), rewritten_);

        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), before_ & USER_BORROW_CONFIG_MASK);

        uint256 unpauseCalls_ = mockDexPool.unpauseUserCallCount();
        uint256 configCalls_ = mockDexPool.updateUserBorrowConfigsCallCount();
        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            true
        );
        assertFalse(actedBorrow_);
        assertFalse(actedPayback_);
        assertEq(mockDexPool.unpauseUserCallCount(), unpauseCalls_);
        assertEq(mockDexPool.updateUserBorrowConfigsCallCount(), configCalls_);
        assertEq(_borrowRow(address(mockDexPool), someUser), rewritten_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);
    }

    /// @dev the config write force-enables the side, so restoring under a pause must re-pause
    function test_unpauseUser_restoreRePausesPausedSide() public {
        uint256 before_ = _freezeSomeUser();
        mockDexPool.pauseUser(someUser, false, true);
        assertTrue(_isDexUserSidePaused(mockDexPool, someUser, true));

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            false
        );
        assertTrue(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(mockDexPool.pauseUserCallCount(), 2);
        (address rePausedUser_, bool rePausedSupply_, bool rePausedBorrow_) = mockDexPool.lastPauseUserCall();
        assertEq(rePausedUser_, someUser);
        assertFalse(rePausedSupply_);
        assertTrue(rePausedBorrow_);
        assertTrue(_isDexUserSidePaused(mockDexPool, someUser, true));
        assertEq(_borrowRow(address(mockDexPool), someUser) | 1, before_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);
    }

    /// @dev the restore has its own admin call; its reverts bubble too, leaving the snapshot untouched
    function test_unpauseUser_restoreRevertIfDexReverts() public {
        mockRevertingDexPool.setPassThrough(true);
        uint256 before_ = _borrowRow(address(mockDexPool), someUser);
        mockRevertingDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), before_);
        (, , , bool actedBorrow_, ) = pauseAuthDex.pauseUser(DEX_ID_REVERTING, someUser, false, false, true, false);
        assertTrue(actedBorrow_);
        // pass-through stores nothing; mirror what a real pool would hold
        mockRevertingDexPool.setStorageSlot(
            keccak256(abi.encode(someUser, uint256(5))),
            _encodeUserBorrowRow(false, FREEZE_PERCENT, FREEZE_DURATION, FREEZE_BASE, FREEZE_MAX)
        );
        mockRevertingDexPool.setPassThrough(false);
        bytes memory revertData_ = abi.encodeWithSelector(
            MockRevertingDexPool.FluidDexError.selector,
            DexErrorTypes.DexT1__NotAnAuth
        );
        mockRevertingDexPool.setRevertData(revertData_);

        vm.expectRevert(revertData_);
        pauseAuthDex.unpauseUser(DEX_ID_REVERTING, someUser, false, false, true, false);
        assertEq(
            pauseAuthDex.dexUserBorrowSnapshot(address(mockRevertingDexPool), someUser),
            before_ & USER_BORROW_CONFIG_MASK
        );
    }

    function test_pauseUser_fullSidePauseKeepsSnapshot() public {
        uint256 before_ = _freezeSomeUser();

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseUser(
            DEX_ID_1,
            someUser,
            false,
            false,
            true,
            true
        );
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);
        assertTrue(_isDexUserSidePaused(mockDexPool, someUser, true));
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), before_ & USER_BORROW_CONFIG_MASK);
        // the pause bit flip must not disturb the frozen config
        uint256 row_ = _borrowRow(address(mockDexPool), someUser);
        assertEq(row_ & 1, 0);
        _assertFrozenConfigBits(row_);
    }

    /// @dev stored limits are BigNumber-rounded already, so freeze + restore is bit-exact
    function test_fuzz_freezeRestore_roundTrip(
        uint16 expandPercent_,
        uint24 expandDuration_,
        uint128 baseDebtCeiling_,
        uint128 maxDebtCeiling_
    ) public {
        expandPercent_ = uint16(bound(expandPercent_, 0, 0x3fff));
        expandDuration_ = uint24(bound(expandDuration_, 1, 0xffffff));
        maxDebtCeiling_ = uint128(bound(maxDebtCeiling_, 1, type(uint128).max));
        baseDebtCeiling_ = uint128(bound(baseDebtCeiling_, 1, maxDebtCeiling_));
        // the preset itself is skipped as already frozen
        vm.assume(
            !(expandPercent_ == FREEZE_PERCENT &&
                expandDuration_ == FREEZE_DURATION &&
                baseDebtCeiling_ == FREEZE_BASE &&
                maxDebtCeiling_ == FREEZE_MAX)
        );

        uint256 row_ = _encodeUserBorrowRow(false, expandPercent_, expandDuration_, baseDebtCeiling_, maxDebtCeiling_);
        mockDexPool.setStorageSlot(keccak256(abi.encode(someUser, uint256(5))), row_);

        (, , , bool actedBorrow_, ) = pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertTrue(actedBorrow_);
        _assertFrozenRow(address(mockDexPool), someUser, row_);

        (, , , actedBorrow_, ) = pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false, true, false);
        assertTrue(actedBorrow_);
        assertEq(_borrowRow(address(mockDexPool), someUser), row_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(address(mockDexPool), someUser), 0);
    }

    // ==================== Edge cases ====================

    function test_canCallAnyDexId() public {
        (address dex1_, bool acted1_) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex1_, address(mockDexPool));
        assertTrue(acted1_);
        assertTrue(mockDexPool.swapPaused());

        (address dex2_, bool acted2_) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_2);
        assertEq(dex2_, address(mockDexPool2));
        assertTrue(acted2_);
        assertTrue(mockDexPool2.swapPaused());
    }

    function test_pauseAndUnpauseSwap_fullCycle() public {
        (address dex_, bool acted_) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertTrue(acted_);
        assertTrue(mockDexPool.swapPaused());

        (dex_, acted_) = pauseAuthDex.unpauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertTrue(acted_);
        assertFalse(mockDexPool.swapPaused());
    }
}
