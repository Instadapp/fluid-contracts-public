// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

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

// ==================== Tests ====================

// To test run:
// forge test -vvv --match-path test/foundry/config/pauseAuthLiquidity.t.sol
contract PauseAuthLiquidityTest is Test {
    FluidPauseAuthLiquidity public pauseAuthLiquidity;

    MockLiquidity public mockLiquidity;
    MockVaultFactory public mockVaultFactory;
    MockDexFactory public mockDexFactory;

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

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

    uint256 constant DEFINED_NOT_PAUSED = 1;
    uint256 constant DEFINED_AND_PAUSED = 1 | (uint256(1) << 255);

    event PauseUserCalled(address user, address[] supplyTokens, address[] borrowTokens);
    event UnpauseUserCalled(address user, address[] supplyTokens, address[] borrowTokens);
    event PauseTokenCalled(address[] tokens);
    event UnpauseTokenCalled(address[] tokens);
    event LogSetPauseAuthContract(address indexed pauseAuthContract);

    function setUp() public {
        mockLiquidity = new MockLiquidity();
        mockVaultFactory = new MockVaultFactory();
        mockDexFactory = new MockDexFactory();

        pauseAuthLiquidity = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory)
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
        uint256 value_ = paused_ ? uint256(1) << 255 : uint256(0);
        mockLiquidity.setStorageValue(slot_, value_);
    }

    function _setAllTokensPausedAtLL() internal {
        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultNewerDexBacked), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockDex), WSTETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockDex), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
    }

    // ==================== 1. Constructor tests ====================

    function test_deployment() public view {
        assertEq(address(pauseAuthLiquidity.LIQUIDITY()), address(mockLiquidity));
        assertEq(address(pauseAuthLiquidity.VAULT_FACTORY()), address(mockVaultFactory));
        assertEq(address(pauseAuthLiquidity.DEX_FACTORY()), address(mockDexFactory));
        assertEq(pauseAuthLiquidity.pauseAuthContract(), address(this));
        assertEq(pauseAuthLiquidity.TEAM_MULTISIG(), TEAM_MULTISIG);
    }

    function test_constructor_revertZeroLiquidity() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuthLiquidity(address(0), address(mockVaultFactory), address(mockDexFactory));
    }

    function test_constructor_revertZeroVaultFactory() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuthLiquidity(address(mockLiquidity), address(0), address(mockDexFactory));
    }

    function test_constructor_revertZeroDexFactory() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        new FluidPauseAuthLiquidity(address(mockLiquidity), address(mockVaultFactory), address(0));
    }

    // ==================== 2. setPauseAuthContract ====================

    function test_setPauseAuthContract_success() public {
        FluidPauseAuthLiquidity fresh = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory)
        );

        address newPauseAuth = makeAddr("newPauseAuth");

        vm.expectEmit(true, false, false, true);
        emit LogSetPauseAuthContract(newPauseAuth);

        vm.prank(TEAM_MULTISIG);
        fresh.setPauseAuthContract(newPauseAuth);

        assertEq(fresh.pauseAuthContract(), newPauseAuth);
    }

    function test_setPauseAuthContract_revertNotMultisig() public {
        FluidPauseAuthLiquidity fresh = new FluidPauseAuthLiquidity(
            address(mockLiquidity),
            address(mockVaultFactory),
            address(mockDexFactory)
        );

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
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
            address(mockDexFactory)
        );

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        fresh.setPauseAuthContract(address(0));
    }

    // ==================== 3. pauseVault ====================

    function test_pauseVault_T1_bothSides() public {
        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseVault_T1_callsLiquidity() public {
        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_T1_onlySupply() public {
        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, false);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](0);

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, false);
    }

    function test_pauseVault_T1_onlyBorrow() public {
        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, false, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);

        address[] memory expectedSupply = new address[](0);
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, false, true);
    }

    function test_pauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true);
    }

    function test_pauseVault_revertZeroVaultAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseVault(UNREGISTERED_VAULT_ID, true, true);
    }

    function test_pauseVault_revertNoSidesSelected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, false, false);
    }

    // ==================== 4. unpauseVault ====================

    function test_unpauseVault_T1_bothSides() public {
        _setAllTokensPausedAtLL();

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_unpauseVault_T1_callsLiquidity() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedSupply = new address[](1);
        expectedSupply[0] = USDC;
        address[] memory expectedBorrow = new address[](1);
        expectedBorrow[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockVaultT1), expectedSupply, expectedBorrow))
        );

        pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_unpauseVault_T1_onlySupply() public {
        _setAllTokensPausedAtLL();

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, false);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_unpauseVault_T1_onlyBorrow() public {
        _setAllTokensPausedAtLL();

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, false, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_unpauseVault_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true);
    }

    function test_unpauseVault_revertZeroVaultAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.unpauseVault(UNREGISTERED_VAULT_ID, true, true);
    }

    function test_unpauseVault_revertNoSidesSelected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, false, false);
    }

    // ==================== 5. pauseDex ====================

    function test_pauseDex_bothSides() public {
        (
            address dex,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, true);

        assertEq(dex, address(mockDex));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseDex_callsLiquidity() public {
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (address(mockDex), expectedTokens, expectedTokens))
        );

        pauseAuthLiquidity.pauseDex(DEX_ID, true, true);
    }

    function test_pauseDex_onlySupply() public {
        (
            address dex,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, false);

        assertEq(dex, address(mockDex));
        assertTrue(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseDex_onlyBorrow() public {
        (
            address dex,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, false, true);

        assertEq(dex, address(mockDex));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseDex_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.pauseDex(DEX_ID, true, true);
    }

    function test_pauseDex_revertZeroDexAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseDex(UNREGISTERED_DEX_ID, true, true);
    }

    function test_pauseDex_revertNoSidesSelected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.pauseDex(DEX_ID, false, false);
    }

    // ==================== 6. unpauseDex ====================

    function test_unpauseDex_bothSides() public {
        _setAllTokensPausedAtLL();

        (
            address dex,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.unpauseDex(DEX_ID, true, true);

        assertEq(dex, address(mockDex));
        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_unpauseDex_callsLiquidity() public {
        _setAllTokensPausedAtLL();

        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = WSTETH;
        expectedTokens[1] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (address(mockDex), expectedTokens, expectedTokens))
        );

        pauseAuthLiquidity.unpauseDex(DEX_ID, true, true);
    }

    function test_unpauseDex_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.unpauseDex(DEX_ID, true, true);
    }

    function test_unpauseDex_revertZeroDexAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.unpauseDex(UNREGISTERED_DEX_ID, true, true);
    }

    function test_unpauseDex_revertNoSidesSelected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__InvalidParams));
        pauseAuthLiquidity.unpauseDex(DEX_ID, false, false);
    }

    // ==================== 7. pauseTokens / unpauseTokens ====================

    function test_pauseTokens_success() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        (address[] memory filtered, address[] memory skipped) = pauseAuthLiquidity.pauseTokens(tokens);

        assertEq(filtered.length, 2);
        assertEq(filtered[0], USDC);
        assertEq(filtered[1], WETH);
        assertEq(skipped.length, 0);
    }

    function test_pauseTokens_callsLiquidity() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.pauseTokens, (tokens)));

        pauseAuthLiquidity.pauseTokens(tokens);
    }

    function test_pauseTokens_alreadyPaused() public {
        _setTokenPauseState(USDC, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        (address[] memory filtered, address[] memory skipped) = pauseAuthLiquidity.pauseTokens(tokens);

        assertEq(filtered.length, 1);
        assertEq(filtered[0], WETH);
        assertEq(skipped.length, 1);
        assertEq(skipped[0], USDC);
    }

    function test_pauseTokens_allAlreadyPaused() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        (address[] memory filtered, address[] memory skipped) = pauseAuthLiquidity.pauseTokens(tokens);

        assertEq(filtered.length, 0);
        assertEq(skipped.length, 2);
        assertEq(skipped[0], USDC);
        assertEq(skipped[1], WETH);
    }

    function test_pauseTokens_allAlreadyPaused_noLiquidityCall() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.recordLogs();
        pauseAuthLiquidity.pauseTokens(tokens);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 pauseTokenSig = keccak256("PauseTokenCalled(address[])");
        for (uint256 i; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != pauseTokenSig, "PauseTokenCalled should not be emitted");
        }
    }

    function test_pauseTokens_revertUnauthorized() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.pauseTokens(tokens);
    }

    function test_unpauseTokens_success() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        (address[] memory filtered, address[] memory skipped) = pauseAuthLiquidity.unpauseTokens(tokens);

        assertEq(filtered.length, 2);
        assertEq(filtered[0], USDC);
        assertEq(filtered[1], WETH);
        assertEq(skipped.length, 0);
    }

    function test_unpauseTokens_callsLiquidity() public {
        _setTokenPauseState(USDC, true);
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        vm.expectCall(address(mockLiquidity), abi.encodeCall(IFluidLiquidityAdmin.unpauseTokens, (tokens)));

        pauseAuthLiquidity.unpauseTokens(tokens);
    }

    function test_unpauseTokens_alreadyUnpaused() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        (address[] memory filtered, address[] memory skipped) = pauseAuthLiquidity.unpauseTokens(tokens);

        assertEq(filtered.length, 0);
        assertEq(skipped.length, 2);
        assertEq(skipped[0], USDC);
        assertEq(skipped[1], WETH);
    }

    function test_unpauseTokens_partiallyPaused() public {
        _setTokenPauseState(WETH, true);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        (address[] memory filtered, address[] memory skipped) = pauseAuthLiquidity.unpauseTokens(tokens);

        assertEq(filtered.length, 1);
        assertEq(filtered[0], WETH);
        assertEq(skipped.length, 1);
        assertEq(skipped[0], USDC);
    }

    function test_unpauseTokens_revertUnauthorized() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.unpauseTokens(tokens);
    }

    // ==================== 8. pauseUser / unpauseUser (pass-through) ====================

    function test_pauseUser_passThrough() public {
        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.pauseUser, (user, supplyTokens, borrowTokens))
        );

        vm.expectEmit(false, false, false, true);
        emit PauseUserCalled(user, supplyTokens, borrowTokens);

        pauseAuthLiquidity.pauseUser(user, supplyTokens, borrowTokens);
    }

    function test_pauseUser_revertUnauthorized() public {
        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](0);

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.pauseUser(user, supplyTokens, borrowTokens);
    }

    function test_unpauseUser_passThrough() public {
        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = WETH;

        vm.expectCall(
            address(mockLiquidity),
            abi.encodeCall(IFluidLiquidityAdmin.unpauseUser, (user, supplyTokens, borrowTokens))
        );

        vm.expectEmit(false, false, false, true);
        emit UnpauseUserCalled(user, supplyTokens, borrowTokens);

        pauseAuthLiquidity.unpauseUser(user, supplyTokens, borrowTokens);
    }

    function test_unpauseUser_revertUnauthorized() public {
        address user = makeAddr("someUser");
        address[] memory supplyTokens = new address[](1);
        supplyTokens[0] = USDC;
        address[] memory borrowTokens = new address[](0);

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        pauseAuthLiquidity.unpauseUser(user, supplyTokens, borrowTokens);
    }

    // ==================== 9. Class 1 user skip ====================

    function test_pauseVault_skipsClass1User() public {
        _setUserClass(address(mockVaultT1), 1);

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertTrue(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseVault_class1_noPauseUserCall() public {
        _setUserClass(address(mockVaultT1), 1);

        vm.recordLogs();
        pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 pauseUserSig = keccak256("PauseUserCalled(address,address[],address[])");
        for (uint256 i; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != pauseUserSig, "PauseUserCalled should not be emitted for class 1");
        }
    }

    function test_pauseDex_skipsClass1User() public {
        _setUserClass(address(mockDex), 1);

        (
            address dex,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, true);

        assertEq(dex, address(mockDex));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertTrue(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseDex_class1_noPauseUserCall() public {
        _setUserClass(address(mockDex), 1);

        vm.recordLogs();
        pauseAuthLiquidity.pauseDex(DEX_ID, true, true);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 pauseUserSig = keccak256("PauseUserCalled(address,address[],address[])");
        for (uint256 i; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != pauseUserSig, "PauseUserCalled should not be emitted for class 1");
        }
    }

    function test_unpauseVault_class1_stillCallsLL() public {
        _setUserClass(address(mockVaultT1), 1);
        _setAllTokensPausedAtLL();

        (, bool actedSupply, bool actedBorrow, bool skippedUserClass1, , ) = pauseAuthLiquidity.unpauseVault(
            VAULT_T1_ID,
            true,
            true
        );

        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
    }

    function test_unpauseDex_class1_stillCallsLL() public {
        _setUserClass(address(mockDex), 1);
        _setAllTokensPausedAtLL();

        (, bool actedSupply, bool actedBorrow, bool skippedUserClass1, , ) = pauseAuthLiquidity.unpauseDex(
            DEX_ID,
            true,
            true
        );

        assertTrue(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
    }

    // ==================== 10. Already-set skip ====================

    function test_pauseVault_supplyAlreadyPaused() public {
        // USDC supply already paused, WETH borrow not paused
        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_NOT_PAUSED);

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertTrue(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseVault_borrowAlreadyPaused() public {
        // USDC supply not paused, WETH borrow already paused
        _setUserData(address(mockVaultT1), WETH, DEFINED_NOT_PAUSED, DEFINED_AND_PAUSED);

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true);

        assertEq(vault, address(mockVaultT1));
        assertTrue(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertTrue(borrowAlreadySet);
    }

    function test_pauseVault_bothAlreadyPaused() public {
        _setUserData(address(mockVaultT1), USDC, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_T1_ID, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertTrue(supplyAlreadySet);
        assertTrue(borrowAlreadySet);
    }

    function test_unpauseVault_supplyAlreadyUnpaused() public {
        // USDC supply not paused, WETH borrow paused
        _setUserData(address(mockVaultT1), USDC, DEFINED_NOT_PAUSED, DEFINED_NOT_PAUSED);
        _setUserData(address(mockVaultT1), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertTrue(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_unpauseVault_bothAlreadyUnpaused() public {
        // All tokens not paused (default state)
        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.unpauseVault(VAULT_T1_ID, true, true);

        assertEq(vault, address(mockVaultT1));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertTrue(supplyAlreadySet);
        assertTrue(borrowAlreadySet);
    }

    function test_pauseDex_alreadyPaused() public {
        _setUserData(address(mockDex), WSTETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);
        _setUserData(address(mockDex), WETH, DEFINED_AND_PAUSED, DEFINED_AND_PAUSED);

        (
            address dex,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseDex(DEX_ID, true, true);

        assertEq(dex, address(mockDex));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertTrue(supplyAlreadySet);
        assertTrue(borrowAlreadySet);
    }

    function test_unpauseDex_alreadyUnpaused() public {
        (
            address dex,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.unpauseDex(DEX_ID, true, true);

        assertEq(dex, address(mockDex));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertTrue(supplyAlreadySet);
        assertTrue(borrowAlreadySet);
    }

    // ==================== 11. Newer vault with DEX-backed sides ====================

    function test_pauseVault_dexBacked_excludesSupply() public {
        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_DEX_BACKED_ID, true, true);

        assertEq(vault, address(mockVaultNewerDexBacked));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseVault_dexBacked_callsLiquidityWithoutSupply() public {
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

        pauseAuthLiquidity.pauseVault(VAULT_DEX_BACKED_ID, true, true);
    }

    function test_unpauseVault_dexBacked_excludesSupply() public {
        _setAllTokensPausedAtLL();

        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.unpauseVault(VAULT_DEX_BACKED_ID, true, true);

        assertEq(vault, address(mockVaultNewerDexBacked));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseVault_dexBacked_supplyOnlyNoAction() public {
        // Supply is DEX-backed, pausing supply only should have no effect at LL
        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_DEX_BACKED_ID, true, false);

        assertEq(vault, address(mockVaultNewerDexBacked));
        assertFalse(actedSupply);
        assertFalse(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }

    function test_pauseVault_dexBacked_borrowOnly() public {
        (
            address vault,
            bool actedSupply,
            bool actedBorrow,
            bool skippedUserClass1,
            bool supplyAlreadySet,
            bool borrowAlreadySet
        ) = pauseAuthLiquidity.pauseVault(VAULT_DEX_BACKED_ID, false, true);

        assertEq(vault, address(mockVaultNewerDexBacked));
        assertFalse(actedSupply);
        assertTrue(actedBorrow);
        assertFalse(skippedUserClass1);
        assertFalse(supplyAlreadySet);
        assertFalse(borrowAlreadySet);
    }
}
