// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidPauseAuth } from "contracts/config/pauseAuth/main.sol";
import { FluidPauseAuthLiquidity } from "contracts/config/pauseAuth/pauseAuthLiquidity.sol";
import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { IFluidVault } from "contracts/protocols/vault/interfaces/iVault.sol";
import { IFluidVaultT1 } from "contracts/protocols/vault/interfaces/iVaultT1.sol";
import { IFluidDexT1 } from "contracts/protocols/dex/interfaces/iDexT1.sol";
import { IFluidLiquidityAdmin } from "contracts/liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "contracts/libraries/liquiditySlotsLink.sol";

// ==================== Mock contracts ====================

contract MockLiquidity {
    event PauseUserCalled(address user, address[] supplyTokens, address[] borrowTokens);
    event UnpauseUserCalled(address user, address[] supplyTokens, address[] borrowTokens);
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

    function pauseUser(address user_, address[] calldata supplyTokens_, address[] calldata borrowTokens_) external {
        emit PauseUserCalled(user_, supplyTokens_, borrowTokens_);
    }

    function unpauseUser(address user_, address[] calldata supplyTokens_, address[] calldata borrowTokens_) external {
        emit UnpauseUserCalled(user_, supplyTokens_, borrowTokens_);
    }

    function pauseTokens(address[] calldata tokens_) external {
        emit PauseTokenCalled(tokens_);
    }

    function unpauseTokens(address[] calldata tokens_) external {
        emit UnpauseTokenCalled(tokens_);
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
    event PauseVaultCalled(uint256 vaultId, bool pauseSupply, bool pauseBorrow);
    event UnpauseVaultCalled(uint256 vaultId, bool unpauseSupply, bool unpauseBorrow);
    event PauseSwapAndArbitrageCalled(uint256 dexId);
    event UnpauseSwapAndArbitrageCalled(uint256 dexId);
    event PauseSmartLendingCalled(uint256 dexId);
    event UnpauseSmartLendingCalled(uint256 dexId);
    event PauseUserCalled(uint256 dexId, address user, bool pauseSupply, bool pauseBorrow);
    event UnpauseUserCalled(uint256 dexId, address user, bool unpauseSupply, bool unpauseBorrow);

    address internal _swapDexResult;
    bool internal _swapAlreadySet;
    address internal _smartLendingDexResult;
    address internal _smartLendingResult;
    bool internal _smartLendingAlreadySet;
    address internal _userDexResult;

    function setSwapResult(address dex_, bool alreadySet_) external {
        _swapDexResult = dex_;
        _swapAlreadySet = alreadySet_;
    }

    function setSmartLendingResult(address dex_, address smartLending_, bool alreadySet_) external {
        _smartLendingDexResult = dex_;
        _smartLendingResult = smartLending_;
        _smartLendingAlreadySet = alreadySet_;
    }

    function setUserResult(address dex_) external {
        _userDexResult = dex_;
    }

    function pauseVault(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseBorrow_
    ) external returns (address, bool, bool, bool, bool) {
        emit PauseVaultCalled(vaultId_, pauseSupply_, pauseBorrow_);
        return (address(0), false, false, false, false);
    }

    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupply_,
        bool unpauseBorrow_
    ) external returns (address, bool, bool, bool, bool) {
        emit UnpauseVaultCalled(vaultId_, unpauseSupply_, unpauseBorrow_);
        return (address(0), false, false, false, false);
    }

    function pauseSwapAndArbitrage(uint256 dexId_) external returns (address, bool) {
        emit PauseSwapAndArbitrageCalled(dexId_);
        return (_swapDexResult, _swapAlreadySet);
    }

    function unpauseSwapAndArbitrage(uint256 dexId_) external returns (address, bool) {
        emit UnpauseSwapAndArbitrageCalled(dexId_);
        return (_swapDexResult, _swapAlreadySet);
    }

    function pauseSmartLending(uint256 dexId_) external returns (address, address, bool) {
        emit PauseSmartLendingCalled(dexId_);
        return (_smartLendingDexResult, _smartLendingResult, _smartLendingAlreadySet);
    }

    function unpauseSmartLending(uint256 dexId_) external returns (address, address, bool) {
        emit UnpauseSmartLendingCalled(dexId_);
        return (_smartLendingDexResult, _smartLendingResult, _smartLendingAlreadySet);
    }

    function pauseUser(uint256 dexId_, address user_, bool pauseSupply_, bool pauseBorrow_) external returns (address) {
        emit PauseUserCalled(dexId_, user_, pauseSupply_, pauseBorrow_);
        return _userDexResult;
    }

    function unpauseUser(
        uint256 dexId_,
        address user_,
        bool unpauseSupply_,
        bool unpauseBorrow_
    ) external returns (address) {
        emit UnpauseUserCalled(dexId_, user_, unpauseSupply_, unpauseBorrow_);
        return _userDexResult;
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

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    address public class1Auth = makeAddr("class1Auth");
    address public class2Auth = makeAddr("class2Auth");
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
    event LogPauseVault(uint256 indexed vaultId, address vault, bool pausedSupply, bool pausedBorrow);
    event LogUnpauseVault(uint256 indexed vaultId, address vault, bool unpausedSupply, bool unpausedBorrow);
    event LogPauseDex(uint256 indexed dexId, address dex, bool pausedSupply, bool pausedBorrow);
    event LogUnpauseDex(uint256 indexed dexId, address dex, bool unpausedSupply, bool unpausedBorrow);
    event LogPauseUser(address indexed user, address[] supplyTokens, address[] borrowTokens);
    event LogUnpauseUser(address indexed user, address[] supplyTokens, address[] borrowTokens);
    event LogPauseToken(address[] tokens);
    event LogUnpauseToken(address[] tokens);
    event LogSetPauseAuth(address indexed pauseAuth, uint256 authClass);
    event LogSetNotPausableVaultId(uint256 indexed vaultId, bool notPausable);
    event LogSetNotPausableDexId(uint256 indexed dexId, bool notPausable);
    event LogSkipVaultAlreadySet(
        uint256 indexed vaultId,
        address vault,
        bool wantsPaused,
        bool setSupplySkipped,
        bool setBorrowSkipped
    );
    event LogSkipDexAlreadySet(
        uint256 indexed dexId,
        address dex,
        bool wantsPaused,
        bool setSupplySkipped,
        bool setBorrowSkipped
    );
    event LogSkipVaultUserClass1(uint256 indexed vaultId, address vault);
    event LogSkipDexUserClass1(uint256 indexed dexId, address dex);
    event LogSkipTokenNotPausable(address indexed token);
    event LogSkipTokenAlreadySet(address indexed token, bool wantsPaused);
    event LogSetNotPausableToken(address indexed token, bool notPausable);
    event LogPauseSwapAndArbitrage(uint256 indexed dexId, address dex);
    event LogUnpauseSwapAndArbitrage(uint256 indexed dexId, address dex);
    event LogSkipSwapAndArbitrageAlreadySet(uint256 indexed dexId, address dex, bool wantsPaused);
    event LogPauseSmartLending(uint256 indexed dexId, address dex, address smartLending);
    event LogUnpauseSmartLending(uint256 indexed dexId, address dex, address smartLending);
    event LogSkipSmartLendingAlreadySet(uint256 indexed dexId, address dex, address smartLending, bool wantsPaused);
    event LogPauseDexUser(uint256 indexed dexId, address dex, address user, bool pauseSupply, bool pauseBorrow);
    event LogUnpauseDexUser(uint256 indexed dexId, address dex, address user, bool unpauseSupply, bool unpauseBorrow);

    // Events from MockPauseAuthDex
    event PauseVaultCalled(uint256 vaultId, bool pauseSupply, bool pauseBorrow);
    event UnpauseVaultCalled(uint256 vaultId, bool unpauseSupply, bool unpauseBorrow);

    function setUp() public {
        mockLiquidity = new MockLiquidity();
        mockVaultFactory = new MockVaultFactory();
        mockDexFactory = new MockDexFactory();
        mockPauseAuthLiquidity = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory)
        );
        mockPauseAuthDex = new MockPauseAuthDex();

        pauseAuth = new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex)
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

    /// @dev Sets the LL exchangePricesAndConfig for a token so it appears paused or unpaused.
    function _setTokenPauseState(address token_, bool paused_) internal {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            token_
        );
        uint256 value_ = paused_ ? uint256(1) << 255 : uint256(0);
        mockLiquidity.setStorageValue(slot_, value_);
    }

    // ==================== Constructor tests ====================

    function test_deployment() public view {
        assertEq(address(pauseAuth.LIQUIDITY()), address(mockLiquidity));
        assertEq(address(pauseAuth.VAULT_FACTORY()), address(mockVaultFactory));
        assertEq(address(pauseAuth.DEX_FACTORY()), address(mockDexFactory));
        assertEq(address(pauseAuth.PAUSE_AUTH_LIQUIDITY()), address(mockPauseAuthLiquidity));
        assertEq(address(pauseAuth.PAUSE_AUTH_DEX()), address(mockPauseAuthDex));
        assertEq(pauseAuth.TEAM_MULTISIG(), TEAM_MULTISIG);
    }

    function test_constructor_revertZeroLiquidity() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuth(
            address(0),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex)
        );
    }

    function test_constructor_revertZeroVaultFactory() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuth(
            address(mockLiquidity),
            address(0),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex)
        );
    }

    function test_constructor_revertZeroDexFactory() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(0),
            address(mockPauseAuthLiquidity),
            address(mockPauseAuthDex)
        );
    }

    function test_constructor_revertZeroPauseAuthLiquidity() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(0),
            address(mockPauseAuthDex)
        );
    }

    function test_constructor_revertZeroPauseAuthDex() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuth(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory),
            address(mockPauseAuthLiquidity),
            address(0)
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
        pauseAuth.setPauseAuth(class1Auth, 3);
    }

    function test_setPauseAuth_revertNotMultisig() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.setPauseAuth(class1Auth, 1);
    }

    function test_setPauseAuth_revertZeroAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
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
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
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
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.setNotPausableDexId(DEX_ID, true);
    }

    function test_setNotPausableDexId_revertInvalidDexId() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.setNotPausableDexId(UNREGISTERED_DEX_ID, true);
    }

    // ==================== removeClass1PauseAuth ====================

    function test_removeClass1PauseAuth_byClass2() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setPauseAuth(class2Auth, 2);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuth(class1Auth, 0);

        vm.prank(class2Auth);
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
        vm.stopPrank();

        vm.prank(unauthorizedUser);
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
        vm.stopPrank();

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.removeClass1PauseAuth(class2Auth);
    }

    function test_removeClass1PauseAuth_revertZeroAddress() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
        vm.stopPrank();

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.removeClass1PauseAuth(address(0));
    }

    // ==================== Class separation tests ====================

    function test_class1_canPause() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_class1_cannotUnpause() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_class2_canPause() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        vm.prank(class2Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_class2_canUnpause() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        vm.prank(class2Auth);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_class1_canPauseDex() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_class1_cannotUnpauseDex() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_class2_canUnpauseDex() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        vm.prank(class2Auth);
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    // ==================== pauseVault ====================

    function test_pauseVault_multisig_T1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_multisig_newerVault() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_NEWER_ID, true, true);
    }

    function test_pauseVault_multisig_dexBackedVault() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true);
    }

    function test_pauseVault_class1Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_revertNotPauseAuth() public {
        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);
        vm.stopPrank();

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_revertZeroVaultAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVault(UNREGISTERED_VAULT_ID, true, true);
    }

    function test_pauseVault_T1_callsLiquidityCorrectly() public {
        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_newer_callsLiquidityCorrectly() public {
        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = DAI;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultNewer), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_NEWER_ID, true, true);
    }

    function test_pauseVault_dexBacked_excludesDexTokens() public {
        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.pauseUser,
                (address(mockVaultNewerDexBacked), expectedSupply, expectedBorrow)
            )
        );

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseVault, (VAULT_DEX_BACKED_ID, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true);
    }

    function test_pauseVault_anyClassCanCall() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setPauseAuth(class2Auth, 2);
        vm.stopPrank();

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);

        vm.prank(class2Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_onlySupply() public {
        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](0);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, false);
    }

    function test_pauseVault_onlyBorrow() public {
        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, false, true);
    }

    function test_pauseVault_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVault(VAULT_T1_ID, false, false);
    }

    function test_pauseVault_dexBacked_supplyOnlyCallsPauseAuthDex() public {
        // Supply is on DEX, borrow is on LL. Pausing supply only → no LL call, only PAUSE_AUTH_DEX call.
        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseVault, (VAULT_DEX_BACKED_ID, true, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, false);
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
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseVault(VAULT_T1_ID, address(mockVaultT1), true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_unpauseVault_class2Auth() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        vm.prank(class2Auth);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_unpauseVault_revertClass1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_unpauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_unpauseVault_revertZeroVaultAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVault(UNREGISTERED_VAULT_ID, true, true);
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
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockVaultNewer), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_NEWER_ID, true, true);
    }

    function test_unpauseVault_dexBacked_excludesDexTokens() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = USDC;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(
                IFluidLiquidityAdmin.unpauseUser,
                (address(mockVaultNewerDexBacked), expectedSupply, expectedBorrow)
            )
        );

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.unpauseVault, (VAULT_DEX_BACKED_ID, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_DEX_BACKED_ID, true, true);
    }

    function test_unpauseVault_onlySupply() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](0);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, false);
    }

    function test_unpauseVault_onlyBorrow() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, false, true);
    }

    function test_unpauseVault_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVault(VAULT_T1_ID, false, false);
    }

    function test_unpauseVault_dexBacked_supplyOnlyCallsPauseAuthDex() public {
        // Supply is on DEX, borrow is on LL. Unpausing supply only → no LL call, only PAUSE_AUTH_DEX call.
        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.unpauseVault, (VAULT_DEX_BACKED_ID, true, false))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_DEX_BACKED_ID, true, false);
    }

    function test_unpauseVault_revertInvalidVaultConstants() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVault(VAULT_REVERTING_ID, true, true);
    }

    // ==================== pauseDex ====================

    function test_pauseDex_multisig() public {
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockDex), expectedTokens, expectedTokens))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(DEX_ID, address(mockDex), true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_class1Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableDexId(DEX_ID, true);
        vm.stopPrank();

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_revertZeroDexAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseDex(UNREGISTERED_DEX_ID, true, true, false);
    }

    function test_pauseDex_onlySmartCol() public {
        mockDex.setDexVariables2(1);

        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;
        address[] memory expectedBorrow = new address[](0);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockDex), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_onlySmartDebt() public {
        mockDex.setDexVariables2(2);

        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockDex), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_neitherSmartColNorDebt() public {
        mockDex.setDexVariables2(0);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_filterSupplyOnly() public {
        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;
        address[] memory expectedBorrow = new address[](0);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockDex), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, false, false);
    }

    function test_pauseDex_filterBorrowOnly() public {
        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockDex), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, false, true, false);
    }

    function test_pauseDex_swapAndArbitrage_forwardsToDexModule() public {
        mockPauseAuthDex.setSwapResult(address(mockDex), false);

        vm.expectCall(address(mockPauseAuthDex), abi.encodeCall(MockPauseAuthDex.pauseSwapAndArbitrage, (DEX_ID)));

        vm.expectEmit(true, false, false, true);
        emit LogPauseSwapAndArbitrage(DEX_ID, address(mockDex));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, false, false, true);
    }

    function test_pauseDex_swapAndArbitrage_emitsSkipWhenAlreadySet() public {
        mockPauseAuthDex.setSwapResult(address(mockDex), true);

        vm.expectEmit(true, false, false, true);
        emit LogSkipSwapAndArbitrageAlreadySet(DEX_ID, address(mockDex), true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, false, false, true);
    }

    function test_pauseDex_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseDex(DEX_ID, false, false, false);
    }

    // ==================== unpauseDex ====================

    function test_unpauseDex_multisig() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockDex), expectedTokens, expectedTokens))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseDex(DEX_ID, address(mockDex), true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_class2Auth() public {
        _setAllTokensPausedAtLL();

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        vm.prank(class2Auth);
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_revertClass1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
        pauseAuth.setNotPausableDexId(DEX_ID, true);
        vm.stopPrank();

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_revertZeroDexAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseDex(UNREGISTERED_DEX_ID, true, true, false);
    }

    function test_unpauseDex_onlySmartCol() public {
        _setAllTokensPausedAtLL();
        mockDex.setDexVariables2(1);

        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;
        address[] memory expectedBorrow = new address[](0);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockDex), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_onlySmartDebt() public {
        _setAllTokensPausedAtLL();
        mockDex.setDexVariables2(2);

        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockDex), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_neitherSmartColNorDebt() public {
        mockDex.setDexVariables2(0);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_filterSupplyOnly() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = WETH;
        address[] memory expectedBorrow = new address[](0);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockDex), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, false, false);
    }

    function test_unpauseDex_filterBorrowOnly() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](2);
        expectedBorrow[0] = WSTETH;
        expectedBorrow[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockDex), expectedSupply, expectedBorrow))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, false, true, false);
    }

    function test_unpauseDex_swapAndArbitrage_forwardsToDexModule() public {
        mockPauseAuthDex.setSwapResult(address(mockDex), false);

        vm.expectCall(address(mockPauseAuthDex), abi.encodeCall(MockPauseAuthDex.unpauseSwapAndArbitrage, (DEX_ID)));

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseSwapAndArbitrage(DEX_ID, address(mockDex));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, false, false, true);
    }

    function test_unpauseDex_swapAndArbitrage_emitsSkipWhenAlreadySet() public {
        mockPauseAuthDex.setSwapResult(address(mockDex), true);

        vm.expectEmit(true, false, false, true);
        emit LogSkipSwapAndArbitrageAlreadySet(DEX_ID, address(mockDex), false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, false, false, true);
    }

    function test_unpauseDex_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseDex(DEX_ID, false, false, false);
    }

    // ==================== pauseUser (pass-through) ====================

    function test_pauseUser_multisig() public {
        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (user, supplyTokens, borrowTokens))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseUser(user, supplyTokens, borrowTokens);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseUserLiquidity(user, supplyTokens, borrowTokens);
    }

    function test_pauseUser_revertPauseAuth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = WETH;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseUserLiquidity(user, supplyTokens, borrowTokens);
    }

    function test_pauseUser_revertUnauthorized() public {
        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](0);

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseUserLiquidity(user, supplyTokens, borrowTokens);
    }

    function test_pauseUserDex_multisig() public {
        address user = makeAddr("dexUser");
        mockPauseAuthDex.setUserResult(address(mockDex));

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseUser, (DEX_ID, user, true, false))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseDexUser(DEX_ID, address(mockDex), user, true, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseUserDex(DEX_ID, user, true, false);
    }

    function test_pauseUserDex_revertUnauthorized() public {
        address user = makeAddr("dexUser");

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseUserDex(DEX_ID, user, true, false);
    }

    // ==================== unpauseUser (pass-through) ====================

    function test_unpauseUser_multisig() public {
        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (user, supplyTokens, borrowTokens))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseUser(user, supplyTokens, borrowTokens);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseUserLiquidity(user, supplyTokens, borrowTokens);
    }

    function test_unpauseUser_revertPauseAuth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = WETH;

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseUserLiquidity(user, supplyTokens, borrowTokens);
    }

    function test_unpauseUser_revertUnauthorized() public {
        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](0);

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseUserLiquidity(user, supplyTokens, borrowTokens);
    }

    function test_unpauseUserDex_multisig() public {
        address user = makeAddr("dexUser");
        mockPauseAuthDex.setUserResult(address(mockDex));

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.unpauseUser, (DEX_ID, user, false, true))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseDexUser(DEX_ID, address(mockDex), user, false, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseUserDex(DEX_ID, user, false, true);
    }

    function test_unpauseUserDex_revertUnauthorized() public {
        address user = makeAddr("dexUser");

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseUserDex(DEX_ID, user, false, true);
    }

    // ==================== smart lending ====================

    function test_pauseSmartLending_forwardsToDexModule() public {
        address smartLending = makeAddr("smartLending");
        mockPauseAuthDex.setSmartLendingResult(address(mockDex), smartLending, false);

        vm.expectCall(address(mockPauseAuthDex), abi.encodeCall(MockPauseAuthDex.pauseSmartLending, (DEX_ID)));

        vm.expectEmit(true, false, false, true);
        emit LogPauseSmartLending(DEX_ID, address(mockDex), smartLending);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseSmartLending(DEX_ID);
    }

    function test_pauseSmartLending_emitsSkipWhenAlreadySet() public {
        address smartLending = makeAddr("smartLending");
        mockPauseAuthDex.setSmartLendingResult(address(mockDex), smartLending, true);

        vm.expectEmit(true, false, false, true);
        emit LogSkipSmartLendingAlreadySet(DEX_ID, address(mockDex), smartLending, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseSmartLending(DEX_ID);
    }

    function test_unpauseSmartLending_forwardsToDexModule() public {
        address smartLending = makeAddr("smartLending");
        mockPauseAuthDex.setSmartLendingResult(address(mockDex), smartLending, false);

        vm.expectCall(address(mockPauseAuthDex), abi.encodeCall(MockPauseAuthDex.unpauseSmartLending, (DEX_ID)));

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseSmartLending(DEX_ID, address(mockDex), smartLending);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseSmartLending(DEX_ID);
    }

    function test_unpauseSmartLending_emitsSkipWhenAlreadySet() public {
        address smartLending = makeAddr("smartLending");
        mockPauseAuthDex.setSmartLendingResult(address(mockDex), smartLending, true);

        vm.expectEmit(true, false, false, true);
        emit LogSkipSmartLendingAlreadySet(DEX_ID, address(mockDex), smartLending, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseSmartLending(DEX_ID);
    }

    // ==================== pauseTokens / unpauseTokens ====================

    function test_pauseTokens_multisig() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens)));

        vm.expectEmit(false, false, false, true);
        emit LogPauseToken(tokens);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseTokens(tokens);
    }

    function test_pauseTokens_class1Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens)));

        vm.prank(class1Auth);
        pauseAuth.pauseTokens(tokens);
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

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens)));

        vm.expectEmit(false, false, false, true);
        emit LogUnpauseToken(tokens);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_class2Auth() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        _setTokenPauseState(USDC, true);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens)));

        vm.prank(class2Auth);
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
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.setNotPausableToken(USDC, true);
    }

    function test_setNotPausableToken_revertZeroAddress() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.setNotPausableToken(address(0), true);
    }

    function test_pauseTokens_skipsNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableToken(USDC, true);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        address[] memory expected = new address[](1);
        expected[0] = WETH;

        vm.expectEmit(true, false, false, false);
        emit LogSkipTokenNotPausable(USDC);

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (expected)));

        vm.prank(class1Auth);
        pauseAuth.pauseTokens(tokens);
    }

    function test_pauseTokens_skipsAllNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableToken(USDC, true);
        vm.stopPrank();

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectEmit(true, false, false, false);
        emit LogSkipTokenNotPausable(USDC);

        vm.prank(class1Auth);
        pauseAuth.pauseTokens(tokens);
        // no call to LIQUIDITY.pauseTokens — all tokens were skipped
    }

    function test_pauseTokens_multisigBypassesNotPausable() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(USDC, true);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens)));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseTokens(tokens);
    }

    function test_unpauseTokens_skipsNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
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

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (expected)));

        vm.prank(class2Auth);
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_skipsAllNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
        pauseAuth.setNotPausableToken(USDC, true);
        vm.stopPrank();

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectEmit(true, false, false, false);
        emit LogSkipTokenNotPausable(USDC);

        vm.prank(class2Auth);
        pauseAuth.unpauseTokens(tokens);
    }

    function test_unpauseTokens_multisigBypassesNotPausable() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(USDC, true);

        _setTokenPauseState(USDC, true);

        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens)));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseTokens(tokens);
    }

    // ==================== token LL state skip ====================

    function test_pauseTokens_skipsAlreadyPaused() public {
        _setTokenPauseState(USDC, true); // USDC already paused at LL

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        address[] memory expected = new address[](1);
        expected[0] = WETH;

        vm.expectEmit(true, false, false, true);
        emit LogSkipTokenAlreadySet(USDC, true);

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (expected)));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseTokens(tokens);
    }

    function test_pauseTokens_skipsAllAlreadyPaused() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectEmit(true, false, false, true);
        emit LogSkipTokenAlreadySet(USDC, true);
        vm.expectEmit(true, false, false, true);
        emit LogSkipTokenAlreadySet(WETH, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseTokens(tokens);
        // no call to LIQUIDITY.pauseTokens — all tokens already paused
    }

    function test_unpauseTokens_skipsAlreadyUnpaused() public {
        // USDC and WETH default to 0 (unpaused) in mock

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectEmit(true, false, false, true);
        emit LogSkipTokenAlreadySet(USDC, false);
        vm.expectEmit(true, false, false, true);
        emit LogSkipTokenAlreadySet(WETH, false);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseTokens(tokens);
        // no call to LIQUIDITY.unpauseTokens — all tokens already unpaused
    }

    function test_unpauseTokens_skipsAlreadyUnpausedPartial() public {
        _setTokenPauseState(WETH, true); // only WETH is paused

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        address[] memory expected = new address[](1);
        expected[0] = WETH;

        vm.expectEmit(true, false, false, true);
        emit LogSkipTokenAlreadySet(USDC, false);

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (expected)));

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
        pauseAuth.pauseVaults(vaultIds, _boolArray(2, true), _boolArray(2, true));
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
        pauseAuth.pauseVaults(vaultIds, _boolArray(2, true), _boolArray(2, true));
    }

    function test_pauseVaults_revertNoSidesSelected() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVaults(vaultIds, _boolArray(1, false), _boolArray(1, false));
    }

    function test_unpauseVaults_batch() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        _setAllTokensPausedAtLL();

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.prank(class2Auth);
        pauseAuth.unpauseVaults(vaultIds, _boolArray(2, true), _boolArray(2, true));
    }

    function test_unpauseVaults_revertClass1() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVaults(vaultIds, _boolArray(1, true), _boolArray(1, true));
    }

    function test_pauseVaults_skipsAlreadyPausedAtLL() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, 1);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), false, true);

        vm.prank(class1Auth);
        pauseAuth.pauseVaults(vaultIds, _boolArray(1, true), _boolArray(1, true));
    }

    function test_pauseVaults_skipsFullyPausedAtLL() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultAlreadySet(VAULT_T1_ID, address(mockVaultT1), true, true, true);

        vm.prank(class1Auth);
        pauseAuth.pauseVaults(vaultIds, _boolArray(1, true), _boolArray(1, true));
    }

    function test_unpauseVaults_skipsNotPausedAtLL() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, 1); // supply paused, borrow not paused
        _setUserData(address(mockVaultT1), WETH, 1, 1); // neither paused

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_T1_ID;

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseVault(VAULT_T1_ID, address(mockVaultT1), true, false);

        vm.prank(class2Auth);
        pauseAuth.unpauseVaults(vaultIds, _boolArray(1, true), _boolArray(1, true));
    }

    // ==================== batch array length mismatch ====================

    function test_pauseVaults_revertArrayLengthMismatch() public {
        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVaults(vaultIds, _boolArray(1, true), _boolArray(2, true));
    }

    function test_unpauseVaults_revertArrayLengthMismatch() public {
        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVaults(vaultIds, _boolArray(2, true), _boolArray(1, true));
    }

    function test_pauseDexes_revertArrayLengthMismatch() public {
        uint256[] memory dexIds = new uint256[](1);
        dexIds[0] = DEX_ID;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseDexes(dexIds, _boolArray(2, true), _boolArray(1, true), _boolArray(1, true));
    }

    function test_unpauseDexes_revertArrayLengthMismatch() public {
        uint256[] memory dexIds = new uint256[](1);
        dexIds[0] = DEX_ID;

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseDexes(dexIds, _boolArray(1, true), _boolArray(2, true), _boolArray(1, true));
    }

    // ==================== pauseDexes / unpauseDexes (batch) ====================

    function test_pauseDexes_batch() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory dexIds = new uint256[](1);
        dexIds[0] = DEX_ID;

        vm.prank(class1Auth);
        pauseAuth.pauseDexes(dexIds, _boolArray(1, true), _boolArray(1, true), _boolArray(1, false));
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
        pauseAuth.pauseDexes(dexIds, _boolArray(2, true), _boolArray(2, true), _boolArray(2, false));
    }

    function test_unpauseDexes_batch() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);

        _setAllTokensPausedAtLL();

        uint256[] memory dexIds = new uint256[](1);
        dexIds[0] = DEX_ID;

        vm.prank(class2Auth);
        pauseAuth.unpauseDexes(dexIds, _boolArray(1, true), _boolArray(1, true), _boolArray(1, false));
    }

    // ==================== Edge cases ====================

    function test_revokePauseAuth_thenRevert() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 0);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_revokeVaultId_thenRevertNotPausable() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseAuth_revertNotPausableVaultId() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableVaultId(VAULT_NEWER_ID, true);
        vm.stopPrank();

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_NEWER_ID, true, true);
    }

    function test_pauseAuth_revertNotPausableDexId() public {
        uint256 otherDexId = 997;
        mockDexFactory.setDex(otherDexId, address(mockDex));

        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setNotPausableDexId(otherDexId, true);
        vm.stopPrank();

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, true, true, false);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseDex(otherDexId, true, true, false);
    }

    function test_class2RemovesClass1_thenClass1CannotPause() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);
        pauseAuth.setPauseAuth(class2Auth, 2);
        vm.stopPrank();

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);

        vm.prank(class2Auth);
        pauseAuth.removeClass1PauseAuth(class1Auth);

        vm.prank(class1Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_revertInvalidVaultConstants() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVault(VAULT_REVERTING_ID, true, true);
    }

    function test_pauseVault_revertNewerVaultInvalidConstants() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.pauseVault(VAULT_NEWER_REVERTING_ID, true, true);
    }

    function test_unpauseVault_revertNewerVaultInvalidConstants() public {
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuth.unpauseVault(VAULT_NEWER_REVERTING_ID, true, true);
    }

    function test_unpauseVault_revertNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class2Auth, 2);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);
        vm.stopPrank();

        vm.prank(class2Auth);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
    }

    // ==================== TEAM_MULTISIG bypasses notPausable ====================

    function test_pauseVault_multisig_bypassesNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), true, true);

        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
        vm.stopPrank();
    }

    function test_unpauseVault_multisig_bypassesNotPausable() public {
        _setAllTokensPausedAtLL();

        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setNotPausableVaultId(VAULT_T1_ID, true);

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseVault(VAULT_T1_ID, address(mockVaultT1), true, true);

        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
        vm.stopPrank();
    }

    function test_pauseDex_multisig_bypassesNotPausable() public {
        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setNotPausableDexId(DEX_ID, true);

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(DEX_ID, address(mockDex), true, true);

        pauseAuth.pauseDex(DEX_ID, true, true, false);
        vm.stopPrank();
    }

    function test_unpauseDex_multisig_bypassesNotPausable() public {
        _setAllTokensPausedAtLL();

        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setNotPausableDexId(DEX_ID, true);

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseDex(DEX_ID, address(mockDex), true, true);

        pauseAuth.unpauseDex(DEX_ID, true, true, false);
        vm.stopPrank();
    }

    // ==================== Class 1 user skip (vault) ====================

    function test_pauseVault_skipsClass1Vault() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass1(VAULT_T1_ID, address(mockVaultT1));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_class1_noPauseUserCall() public {
        _setUserClass(address(mockVaultT1), 1);

        // Expect that LIQUIDITY.pauseUser is NOT called
        vm.prank(TEAM_MULTISIG);
        vm.recordLogs();
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 pauseUserSig = keccak256("PauseUserCalled(address,address[],address[])");
        for (uint256 i; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != pauseUserSig, "PauseUserCalled should not be emitted for class 1");
        }
    }

    function test_pauseVault_class1Auth_skipsClass1Vault() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass1(VAULT_T1_ID, address(mockVaultT1));

        vm.prank(class1Auth);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_class1_dexBackedStillForwards() public {
        _setUserClass(address(mockVaultNewerDexBacked), 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass1(VAULT_DEX_BACKED_ID, address(mockVaultNewerDexBacked));

        vm.expectCall(
            address(mockPauseAuthDex),
            abi.encodeCall(MockPauseAuthDex.pauseVault, (VAULT_DEX_BACKED_ID, true, true))
        );

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_DEX_BACKED_ID, true, true);
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
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseVault(VAULT_T1_ID, address(mockVaultT1), true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_class0_notSkipped() public {
        _setUserClass(address(mockVaultT1), 0);

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_T1_ID, address(mockVaultT1), true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVaults_batch_class1Skipped() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = VAULT_T1_ID;
        vaultIds[1] = VAULT_NEWER_ID;

        // Vault T1 (class 1) should be skipped
        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass1(VAULT_T1_ID, address(mockVaultT1));

        // Vault Newer (class 0) should be paused normally
        address[] memory expectedSupply = new address[](2);
        expectedSupply[0] = WSTETH;
        expectedSupply[1] = DAI;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultNewer), expectedSupply, expectedBorrow))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseVault(VAULT_NEWER_ID, address(mockVaultNewer), true, true);

        vm.prank(class1Auth);
        pauseAuth.pauseVaults(vaultIds, _boolArray(2, true), _boolArray(2, true));
    }

    function test_pauseVault_class1_alreadyPausedAtLL_emitsAlreadySet() public {
        _setUserClass(address(mockVaultT1), 1);
        _setAllTokensPausedAtLL();

        // All LL tokens are already paused → filtered out before the class 1 check
        // so LogSkipVaultAlreadySet should fire (not LogSkipVaultUserClass1)
        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultAlreadySet(VAULT_T1_ID, address(mockVaultT1), true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, true);
    }

    // ==================== Class 1 user skip (DEX) ====================

    function test_pauseDex_skipsClass1Dex() public {
        _setUserClass(address(mockDex), 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipDexUserClass1(DEX_ID, address(mockDex));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_class1_noPauseUserCall() public {
        _setUserClass(address(mockDex), 1);

        vm.prank(TEAM_MULTISIG);
        vm.recordLogs();
        pauseAuth.pauseDex(DEX_ID, true, true, false);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 pauseUserSig = keccak256("PauseUserCalled(address,address[],address[])");
        for (uint256 i; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != pauseUserSig, "PauseUserCalled should not be emitted for class 1");
        }
    }

    function test_pauseDex_class1Auth_skipsClass1Dex() public {
        _setUserClass(address(mockDex), 1);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(class1Auth, 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipDexUserClass1(DEX_ID, address(mockDex));

        vm.prank(class1Auth);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_unpauseDex_class1_stillCallsLL() public {
        _setUserClass(address(mockDex), 1);
        _setAllTokensPausedAtLL();

        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockDex), expectedTokens, expectedTokens))
        );

        vm.expectEmit(true, false, false, true);
        emit LogUnpauseDex(DEX_ID, address(mockDex), true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseDex(DEX_ID, true, true, false);
    }

    function test_pauseDex_class0_notSkipped() public {
        _setUserClass(address(mockDex), 0);

        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockDex), expectedTokens, expectedTokens))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(DEX_ID, address(mockDex), true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
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

        // DEX 1 (class 1) should be skipped
        vm.expectEmit(true, false, false, true);
        emit LogSkipDexUserClass1(DEX_ID, address(mockDex));

        // DEX 2 (class 0) should be paused normally
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = USDC;
        expectedTokens[1] = DAI;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(otherDex), expectedTokens, expectedTokens))
        );

        vm.expectEmit(true, false, false, true);
        emit LogPauseDex(otherDexId, address(otherDex), true, true);

        vm.prank(class1Auth);
        pauseAuth.pauseDexes(dexIds, _boolArray(2, true), _boolArray(2, true), _boolArray(2, false));
    }

    function test_pauseDex_class1_alreadyPausedAtLL_emitsAlreadySet() public {
        _setUserClass(address(mockDex), 1);
        _setAllTokensPausedAtLL();

        vm.expectEmit(true, false, false, true);
        emit LogSkipDexAlreadySet(DEX_ID, address(mockDex), true, true, true);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, true, false);
    }

    function test_pauseVault_class1_supplyOnly_skips() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass1(VAULT_T1_ID, address(mockVaultT1));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, true, false);
    }

    function test_pauseVault_class1_borrowOnly_skips() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipVaultUserClass1(VAULT_T1_ID, address(mockVaultT1));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseVault(VAULT_T1_ID, false, true);
    }

    function test_pauseDex_class1_supplyOnly_skips() public {
        _setUserClass(address(mockDex), 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipDexUserClass1(DEX_ID, address(mockDex));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, true, false, false);
    }

    function test_pauseDex_class1_borrowOnly_skips() public {
        _setUserClass(address(mockDex), 1);

        vm.expectEmit(true, false, false, true);
        emit LogSkipDexUserClass1(DEX_ID, address(mockDex));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseDex(DEX_ID, false, true, false);
    }
}
