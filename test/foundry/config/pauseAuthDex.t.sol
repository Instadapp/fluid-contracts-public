// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidPauseAuthDex } from "contracts/config/pauseAuth/pauseAuthDex.sol";
import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { IFluidVault } from "contracts/protocols/vault/interfaces/iVault.sol";

// ==================== Mock contracts ====================

contract MockLiquidity {

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
contract MockDexPool {
    uint256 public immutable DEX_ID;
    bool public swapPaused;
    uint256 public pauseUserCallCount;
    uint256 public unpauseUserCallCount;

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

    function pauseUser(address user_, bool pauseSupply_, bool pauseBorrow_) external {
        pauseUserCallCount++;
        lastPauseUserCall = PauseUserCall(user_, pauseSupply_, pauseBorrow_);
        if (pauseSupply_) {
            bytes32 slot_ = keccak256(abi.encode(user_, uint256(3)));
            _storageSlots[slot_] = (_storageSlots[slot_] | 2) & ~uint256(1);
        }
        if (pauseBorrow_) {
            bytes32 slot_ = keccak256(abi.encode(user_, uint256(5)));
            _storageSlots[slot_] = (_storageSlots[slot_] | 2) & ~uint256(1);
        }
        emit UserPaused(user_, pauseSupply_, pauseBorrow_);
    }

    function unpauseUser(address user_, bool unpauseSupply_, bool unpauseBorrow_) external {
        unpauseUserCallCount++;
        lastUnpauseUserCall = PauseUserCall(user_, unpauseSupply_, unpauseBorrow_);
        if (unpauseSupply_) {
            bytes32 slot_ = keccak256(abi.encode(user_, uint256(3)));
            _storageSlots[slot_] = _storageSlots[slot_] | 1;
        }
        if (unpauseBorrow_) {
            bytes32 slot_ = keccak256(abi.encode(user_, uint256(5)));
            _storageSlots[slot_] = _storageSlots[slot_] | 1;
        }
        emit UserUnpaused(user_, unpauseSupply_, unpauseBorrow_);
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

// ==================== Tests ====================

// To test run:
// forge test -vvv --match-path test/foundry/config/pauseAuthDex.t.sol
contract PauseAuthDexTest is Test {
    FluidPauseAuthDex public pauseAuthDex;

    MockLiquidity public mockLiquidity;
    MockVaultFactory public mockVaultFactory;
    MockDexFactory public mockDexFactory;
    MockSmartLendingFactory public mockSmartLendingFactory;
    MockDexPool public mockDexPool;
    MockDexPool public mockDexPool2;

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    address public unauthorizedUser = makeAddr("unauthorizedUser");
    address public smartLending = makeAddr("smartLending");
    address public smartLending2 = makeAddr("smartLending2");
    address public someUser = makeAddr("someUser");

    uint256 public constant DEX_ID_1 = 1;
    uint256 public constant DEX_ID_2 = 2;
    uint256 public constant DEX_ID_NO_SL = 3;

    MockVaultT1 public mockVaultT1;
    MockVaultNewer public mockVaultSupplyDex;
    MockVaultNewer public mockVaultBorrowDex;
    MockVaultNewer public mockVaultBothDex;
    MockVaultNewer public mockVaultSameDex;
    MockVaultNewer public mockVaultNoDex;
    MockRevertingVault public mockRevertingVault;
    MockDexPool public mockDexPoolNoSL;

    uint256 public constant VAULT_T1_ID = 1;
    uint256 public constant VAULT_SUPPLY_DEX_ID = 2;
    uint256 public constant VAULT_BORROW_DEX_ID = 3;
    uint256 public constant VAULT_BOTH_DEX_ID = 4;
    uint256 public constant VAULT_SAME_DEX_ID = 5;
    uint256 public constant VAULT_NO_DEX_ID = 6;
    uint256 public constant VAULT_REVERTING_ID = 7;
    uint256 public constant UNREGISTERED_VAULT_ID = 999;

    event LogSetPauseAuthContract(address indexed pauseAuthContract);

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
        mockSmartLendingFactory.setSmartLending(DEX_ID_1, smartLending);
        mockSmartLendingFactory.setSmartLending(DEX_ID_2, smartLending2);
        // DEX_ID_NO_SL has no smart lending (returns address(0))

        pauseAuthDex = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory)
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
        mockRevertingVault = new MockRevertingVault();

        // Register vaults
        mockVaultFactory.setVault(VAULT_T1_ID, address(mockVaultT1));
        mockVaultFactory.setVault(VAULT_SUPPLY_DEX_ID, address(mockVaultSupplyDex));
        mockVaultFactory.setVault(VAULT_BORROW_DEX_ID, address(mockVaultBorrowDex));
        mockVaultFactory.setVault(VAULT_BOTH_DEX_ID, address(mockVaultBothDex));
        mockVaultFactory.setVault(VAULT_SAME_DEX_ID, address(mockVaultSameDex));
        mockVaultFactory.setVault(VAULT_NO_DEX_ID, address(mockVaultNoDex));
        mockVaultFactory.setVault(VAULT_REVERTING_ID, address(mockRevertingVault));

        // Set up DEX storage so _dexUserNeedsToggle pre-checks pass for pause operations.
        // Value 1 = defined + unpaused (bit 0 = 1). Supply mapping slot = 3, borrow mapping slot = 5.
        // mockDexPool (DEX_ID_1) users:
        mockDexPool.setStorageSlot(keccak256(abi.encode(address(mockVaultSupplyDex), uint256(3))), 1);
        mockDexPool.setStorageSlot(keccak256(abi.encode(address(mockVaultBothDex), uint256(3))), 1);
        mockDexPool.setStorageSlot(keccak256(abi.encode(address(mockVaultSameDex), uint256(3))), 1);
        mockDexPool.setStorageSlot(keccak256(abi.encode(address(mockVaultSameDex), uint256(5))), 1);
        mockDexPool.setStorageSlot(keccak256(abi.encode(smartLending, uint256(3))), 1);
        // mockDexPool2 (DEX_ID_2) users:
        mockDexPool2.setStorageSlot(keccak256(abi.encode(address(mockVaultBorrowDex), uint256(5))), 1);
        mockDexPool2.setStorageSlot(keccak256(abi.encode(address(mockVaultBothDex), uint256(5))), 1);
        mockDexPool2.setStorageSlot(keccak256(abi.encode(smartLending2, uint256(3))), 1);
    }

    // ==================== Constructor tests ====================

    function test_deployment() public view {
        assertEq(address(pauseAuthDex.LIQUIDITY()), address(mockLiquidity));
        assertEq(address(pauseAuthDex.VAULT_FACTORY()), address(mockVaultFactory));
        assertEq(address(pauseAuthDex.DEX_FACTORY()), address(mockDexFactory));
        assertEq(address(pauseAuthDex.SMART_LENDING_FACTORY()), address(mockSmartLendingFactory));
        assertEq(pauseAuthDex.TEAM_MULTISIG(), TEAM_MULTISIG);
        assertEq(pauseAuthDex.pauseAuthContract(), address(this));
    }

    function test_constructor_revertZeroLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        new FluidPauseAuthDex(
            address(0),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory)
        );
    }

    function test_constructor_revertZeroVaultFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        new FluidPauseAuthDex(
            address(mockLiquidity),
            address(0),
            address(mockDexFactory),
            address(mockSmartLendingFactory)
        );
    }

    function test_constructor_revertZeroDexFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(0),
            address(mockSmartLendingFactory)
        );
    }

    function test_constructor_revertZeroSmartLendingFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        new FluidPauseAuthDex(address(mockLiquidity), address(mockVaultFactory), address(mockDexFactory), address(0));
    }

    // ==================== Admin: setPauseAuthContract ====================

    function test_setPauseAuthContract() public {
        FluidPauseAuthDex fresh_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory)
        );
        assertEq(fresh_.pauseAuthContract(), address(0));

        address newPauseAuth_ = makeAddr("newPauseAuth");

        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuthContract(newPauseAuth_);

        vm.prank(TEAM_MULTISIG);
        fresh_.setPauseAuthContract(newPauseAuth_);
        assertEq(fresh_.pauseAuthContract(), newPauseAuth_);
    }

    function test_setPauseAuthContract_revertNotMultisig() public {
        FluidPauseAuthDex fresh_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockSmartLendingFactory)
        );

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
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
            address(mockSmartLendingFactory)
        );

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        fresh_.setPauseAuthContract(address(0));
    }

    // ==================== pauseSwapAndArbitrage ====================

    function test_pauseSwapAndArbitrage() public {
        (address dex_, bool alreadySet_) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertFalse(alreadySet_);
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

        (address dex_, bool alreadySet_) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertTrue(alreadySet_);
    }

    // ==================== unpauseSwapAndArbitrage ====================

    function test_unpauseSwapAndArbitrage() public {
        pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertTrue(mockDexPool.swapPaused());

        (address dex_, bool alreadySet_) = pauseAuthDex.unpauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertFalse(alreadySet_);
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
        (address dex_, bool alreadySet_) = pauseAuthDex.unpauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertTrue(alreadySet_);
    }

    // ==================== pauseVault ====================

    function test_pauseVault_supplyDex() public {
        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .pauseVault(VAULT_SUPPLY_DEX_ID, true, false);
        assertEq(vault_, address(mockVaultSupplyDex));
        assertTrue(actedSupply_);
        assertFalse(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        (address user, bool supply, bool borrow) = mockDexPool.lastPauseUserCall();
        assertEq(user, address(mockVaultSupplyDex));
        assertTrue(supply);
        assertFalse(borrow);
    }

    function test_pauseVault_borrowDex() public {
        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .pauseVault(VAULT_BORROW_DEX_ID, false, true);
        assertEq(vault_, address(mockVaultBorrowDex));
        assertFalse(actedSupply_);
        assertTrue(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        (address user, bool supply, bool borrow) = mockDexPool2.lastPauseUserCall();
        assertEq(user, address(mockVaultBorrowDex));
        assertFalse(supply);
        assertTrue(borrow);
    }

    function test_pauseVault_bothDex() public {
        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .pauseVault(VAULT_BOTH_DEX_ID, true, true);
        assertEq(vault_, address(mockVaultBothDex));
        assertTrue(actedSupply_);
        assertTrue(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        (address supplyUser, bool supplyS, bool supplyB) = mockDexPool.lastPauseUserCall();
        assertEq(supplyUser, address(mockVaultBothDex));
        assertTrue(supplyS);
        assertFalse(supplyB);

        (address borrowUser, bool borrowS, bool borrowB) = mockDexPool2.lastPauseUserCall();
        assertEq(borrowUser, address(mockVaultBothDex));
        assertFalse(borrowS);
        assertTrue(borrowB);
    }

    function test_pauseVault_sameDex_mergesCalls() public {
        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .pauseVault(VAULT_SAME_DEX_ID, true, true);
        assertEq(vault_, address(mockVaultSameDex));
        assertTrue(actedSupply_);
        assertTrue(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        (address user, bool supply, bool borrow) = mockDexPool.lastPauseUserCall();
        assertEq(user, address(mockVaultSameDex));
        assertTrue(supply);
        assertTrue(borrow);
        assertEq(mockDexPool.pauseUserCallCount(), 1);
    }

    function test_pauseVault_onlySupply() public {
        (address vault_, bool actedSupply_, bool actedBorrow_, , ) = pauseAuthDex.pauseVault(
            VAULT_BOTH_DEX_ID,
            true,
            false
        );
        assertEq(vault_, address(mockVaultBothDex));
        assertTrue(actedSupply_);
        assertFalse(actedBorrow_);

        (address supplyUser, bool supplyS, ) = mockDexPool.lastPauseUserCall();
        assertEq(supplyUser, address(mockVaultBothDex));
        assertTrue(supplyS);

        (address borrowUser, , ) = mockDexPool2.lastPauseUserCall();
        assertEq(borrowUser, address(0));
    }

    function test_pauseVault_onlyBorrow() public {
        (address vault_, bool actedSupply_, bool actedBorrow_, , ) = pauseAuthDex.pauseVault(
            VAULT_BOTH_DEX_ID,
            false,
            true
        );
        assertEq(vault_, address(mockVaultBothDex));
        assertFalse(actedSupply_);
        assertTrue(actedBorrow_);

        (address supplyUser, , ) = mockDexPool.lastPauseUserCall();
        assertEq(supplyUser, address(0));

        (address borrowUser, bool borrowS, bool borrowB) = mockDexPool2.lastPauseUserCall();
        assertEq(borrowUser, address(mockVaultBothDex));
        assertFalse(borrowS);
        assertTrue(borrowB);
    }

    function test_pauseVault_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseVault(VAULT_NO_DEX_ID, false, false);
    }

    function test_pauseVault_revertZeroVaultAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseVault(UNREGISTERED_VAULT_ID, true, false);
    }

    function test_pauseVault_silentReturnT1Vault() public {
        uint256 callCountBefore1 = mockDexPool.pauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .pauseVault(VAULT_T1_ID, true, true);
        assertEq(vault_, address(mockVaultT1));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.pauseUserCallCount(), callCountBefore2);
    }

    function test_pauseVault_silentReturnNoDex() public {
        uint256 callCountBefore1 = mockDexPool.pauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .pauseVault(VAULT_NO_DEX_ID, true, true);
        assertEq(vault_, address(mockVaultNoDex));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.pauseUserCallCount(), callCountBefore2);
    }

    function test_pauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.pauseVault(VAULT_SUPPLY_DEX_ID, true, false);
    }

    function test_pauseVault_silentNoOpWhenIsDexReverts() public {
        MockRevertingDexFactory revertingDexFactory_ = new MockRevertingDexFactory();
        revertingDexFactory_.setDex(DEX_ID_1, address(mockDexPool));

        FluidPauseAuthDex pauseAuthDex_ = new FluidPauseAuthDex(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(revertingDexFactory_),
            address(mockSmartLendingFactory)
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuthDex_.setPauseAuthContract(address(this));

        uint256 callCountBefore = mockDexPool.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedBorrow_, , ) = pauseAuthDex_.pauseVault(
            VAULT_SUPPLY_DEX_ID,
            true,
            false
        );
        assertEq(vault_, address(mockVaultSupplyDex));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);

        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore);
    }

    function test_pauseVault_silentReturnRevertingVault() public {
        uint256 callCountBefore1 = mockDexPool.pauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.pauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .pauseVault(VAULT_REVERTING_ID, true, true);
        assertEq(vault_, address(mockRevertingVault));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        assertEq(mockDexPool.pauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.pauseUserCallCount(), callCountBefore2);
    }

    function test_pauseVault_skipsAlreadyPaused() public {
        pauseAuthDex.pauseVault(VAULT_SUPPLY_DEX_ID, true, false);

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .pauseVault(VAULT_SUPPLY_DEX_ID, true, false);
        assertEq(vault_, address(mockVaultSupplyDex));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);
        assertTrue(supplySkipped_);
        assertFalse(borrowSkipped_);
    }

    // ==================== unpauseVault ====================

    function test_unpauseVault_supplyDex() public {
        pauseAuthDex.pauseVault(VAULT_SUPPLY_DEX_ID, true, false);

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .unpauseVault(VAULT_SUPPLY_DEX_ID, true, false);
        assertEq(vault_, address(mockVaultSupplyDex));
        assertTrue(actedSupply_);
        assertFalse(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        (address user, bool supply, bool borrow) = mockDexPool.lastUnpauseUserCall();
        assertEq(user, address(mockVaultSupplyDex));
        assertTrue(supply);
        assertFalse(borrow);
    }

    function test_unpauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.unpauseVault(VAULT_SUPPLY_DEX_ID, true, false);
    }

    function test_unpauseVault_borrowDex() public {
        pauseAuthDex.pauseVault(VAULT_BORROW_DEX_ID, false, true);

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .unpauseVault(VAULT_BORROW_DEX_ID, false, true);
        assertEq(vault_, address(mockVaultBorrowDex));
        assertFalse(actedSupply_);
        assertTrue(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        (address user, bool supply, bool borrow) = mockDexPool2.lastUnpauseUserCall();
        assertEq(user, address(mockVaultBorrowDex));
        assertFalse(supply);
        assertTrue(borrow);
    }

    function test_unpauseVault_bothDex() public {
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, true, true);

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .unpauseVault(VAULT_BOTH_DEX_ID, true, true);
        assertEq(vault_, address(mockVaultBothDex));
        assertTrue(actedSupply_);
        assertTrue(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        (address supplyUser, bool supplyS, bool supplyB) = mockDexPool.lastUnpauseUserCall();
        assertEq(supplyUser, address(mockVaultBothDex));
        assertTrue(supplyS);
        assertFalse(supplyB);

        (address borrowUser, bool borrowS, bool borrowB) = mockDexPool2.lastUnpauseUserCall();
        assertEq(borrowUser, address(mockVaultBothDex));
        assertFalse(borrowS);
        assertTrue(borrowB);
    }

    function test_unpauseVault_sameDex_mergesCalls() public {
        pauseAuthDex.pauseVault(VAULT_SAME_DEX_ID, true, true);

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .unpauseVault(VAULT_SAME_DEX_ID, true, true);
        assertEq(vault_, address(mockVaultSameDex));
        assertTrue(actedSupply_);
        assertTrue(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        (address user, bool supply, bool borrow) = mockDexPool.lastUnpauseUserCall();
        assertEq(user, address(mockVaultSameDex));
        assertTrue(supply);
        assertTrue(borrow);
        assertEq(mockDexPool.unpauseUserCallCount(), 1);
    }

    function test_unpauseVault_onlyBorrow() public {
        pauseAuthDex.pauseVault(VAULT_BOTH_DEX_ID, false, true);

        (address vault_, bool actedSupply_, bool actedBorrow_, , ) = pauseAuthDex.unpauseVault(
            VAULT_BOTH_DEX_ID,
            false,
            true
        );
        assertEq(vault_, address(mockVaultBothDex));
        assertFalse(actedSupply_);
        assertTrue(actedBorrow_);

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
        pauseAuthDex.unpauseVault(VAULT_NO_DEX_ID, false, false);
    }

    function test_unpauseVault_revertZeroVaultAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseVault(UNREGISTERED_VAULT_ID, true, false);
    }

    function test_unpauseVault_silentReturnT1Vault() public {
        uint256 callCountBefore1 = mockDexPool.unpauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.unpauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .unpauseVault(VAULT_T1_ID, true, true);
        assertEq(vault_, address(mockVaultT1));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        assertEq(mockDexPool.unpauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.unpauseUserCallCount(), callCountBefore2);
    }

    function test_unpauseVault_silentReturnNoDex() public {
        uint256 callCountBefore1 = mockDexPool.unpauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.unpauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .unpauseVault(VAULT_NO_DEX_ID, true, true);
        assertEq(vault_, address(mockVaultNoDex));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

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
            address(mockSmartLendingFactory)
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuthDex_.setPauseAuthContract(address(this));

        uint256 callCountBefore = mockDexPool.unpauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedBorrow_, , ) = pauseAuthDex_.unpauseVault(
            VAULT_SUPPLY_DEX_ID,
            true,
            false
        );
        assertEq(vault_, address(mockVaultSupplyDex));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);

        assertEq(mockDexPool.unpauseUserCallCount(), callCountBefore);
    }

    function test_unpauseVault_silentReturnRevertingVault() public {
        uint256 callCountBefore1 = mockDexPool.unpauseUserCallCount();
        uint256 callCountBefore2 = mockDexPool2.unpauseUserCallCount();

        (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_) = pauseAuthDex
            .unpauseVault(VAULT_REVERTING_ID, true, true);
        assertEq(vault_, address(mockRevertingVault));
        assertFalse(actedSupply_);
        assertFalse(actedBorrow_);
        assertFalse(supplySkipped_);
        assertFalse(borrowSkipped_);

        assertEq(mockDexPool.unpauseUserCallCount(), callCountBefore1);
        assertEq(mockDexPool2.unpauseUserCallCount(), callCountBefore2);
    }

    // ==================== pauseSmartLending ====================

    function test_pauseSmartLending() public {
        (address dex_, address smartLending_, bool alreadySet_) = pauseAuthDex.pauseSmartLending(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertEq(smartLending_, smartLending);
        assertFalse(alreadySet_);

        (address user, bool supply, bool borrow) = mockDexPool.lastPauseUserCall();
        assertEq(user, smartLending);
        assertTrue(supply);
        assertFalse(borrow);
    }

    function test_pauseSmartLending_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.pauseSmartLending(DEX_ID_1);
    }

    function test_pauseSmartLending_correctDexAndSmartLendingResolution() public {
        (address dex_, address smartLending_, bool alreadySet_) = pauseAuthDex.pauseSmartLending(DEX_ID_2);
        assertEq(dex_, address(mockDexPool2));
        assertEq(smartLending_, smartLending2);
        assertFalse(alreadySet_);

        (address user, bool supply, ) = mockDexPool2.lastPauseUserCall();
        assertEq(user, smartLending2);
        assertTrue(supply);
    }

    function test_pauseSmartLending_revertZeroSmartLendingAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseSmartLending(DEX_ID_NO_SL);
    }

    function test_pauseSmartLending_skipsAlreadyPaused() public {
        pauseAuthDex.pauseSmartLending(DEX_ID_1);

        (address dex_, address smartLending_, bool alreadySet_) = pauseAuthDex.pauseSmartLending(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertEq(smartLending_, smartLending);
        assertTrue(alreadySet_);
    }

    // ==================== unpauseSmartLending ====================

    function test_unpauseSmartLending() public {
        pauseAuthDex.pauseSmartLending(DEX_ID_1);

        (address dex_, address smartLending_, bool alreadySet_) = pauseAuthDex.unpauseSmartLending(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertEq(smartLending_, smartLending);
        assertFalse(alreadySet_);

        (address user, bool supply, bool borrow) = mockDexPool.lastUnpauseUserCall();
        assertEq(user, smartLending);
        assertTrue(supply);
        assertFalse(borrow);
    }

    function test_unpauseSmartLending_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.unpauseSmartLending(DEX_ID_1);
    }

    function test_unpauseSmartLending_revertZeroSmartLendingAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseSmartLending(DEX_ID_NO_SL);
    }

    // ==================== pauseUser ====================

    function test_pauseUser() public {
        address dex_ = pauseAuthDex.pauseUser(DEX_ID_1, someUser, true, true);
        assertEq(dex_, address(mockDexPool));

        (address user, bool supply, bool borrow) = mockDexPool.lastPauseUserCall();
        assertEq(user, someUser);
        assertTrue(supply);
        assertTrue(borrow);
    }

    function test_pauseUser_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, true, false);
    }

    function test_pauseUser_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(DEX_ID_1, someUser, false, false);
    }

    function test_pauseUser_revertInvalidDexId() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.pauseUser(999, someUser, true, false);
    }

    // ==================== unpauseUser ====================

    function test_unpauseUser() public {
        address dex_ = pauseAuthDex.unpauseUser(DEX_ID_1, someUser, true, true);
        assertEq(dex_, address(mockDexPool));

        (address user, bool supply, bool borrow) = mockDexPool.lastUnpauseUserCall();
        assertEq(user, someUser);
        assertTrue(supply);
        assertTrue(borrow);
    }

    function test_unpauseUser_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__Unauthorized));
        pauseAuthDex.unpauseUser(DEX_ID_1, someUser, true, false);
    }

    function test_unpauseUser_revertBothFlagsFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseUser(DEX_ID_1, someUser, false, false);
    }

    function test_unpauseUser_revertInvalidDexId() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthDex__InvalidParams)
        );
        pauseAuthDex.unpauseUser(999, someUser, true, false);
    }

    // ==================== Edge cases ====================

    function test_canCallAnyDexId() public {
        (address dex1_, ) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex1_, address(mockDexPool));
        assertTrue(mockDexPool.swapPaused());

        (address dex2_, ) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_2);
        assertEq(dex2_, address(mockDexPool2));
        assertTrue(mockDexPool2.swapPaused());
    }

    function test_pauseAndUnpauseSwap_fullCycle() public {
        (address dex_, bool alreadySet_) = pauseAuthDex.pauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertFalse(alreadySet_);
        assertTrue(mockDexPool.swapPaused());

        (dex_, alreadySet_) = pauseAuthDex.unpauseSwapAndArbitrage(DEX_ID_1);
        assertEq(dex_, address(mockDexPool));
        assertFalse(alreadySet_);
        assertFalse(mockDexPool.swapPaused());
    }
}
