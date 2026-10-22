// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FluidPauseAuthDex } from "contracts/config/pauseAuth/pauseAuthDex.sol";
import { IFluidDexT1 } from "contracts/protocols/dex/interfaces/iDexT1.sol";
import { IFluidDexT1Admin } from "contracts/protocols/dex/interfaces/iDexT1Admin.sol";
import { Structs as AdminModuleStructs } from "contracts/protocols/dex/poolT1/adminModule/structs.sol";
import { IFluidVault } from "contracts/protocols/vault/interfaces/iVault.sol";
import { IFluidOracle } from "contracts/oracleV2/interfaces/iFluidOracle.sol";
import { ErrorTypes as DexErrorTypes } from "contracts/protocols/dex/errorTypes.sol";
import { DexSlotsLink } from "contracts/libraries/dexSlotsLink.sol";
import { BigMathMinified } from "contracts/libraries/bigMathMinified.sol";
import { AddressCalcs } from "contracts/libraries/addressCalcs.sol";

interface IFluidDexFactoryAuth {
    function setGlobalAuth(address globalAuth_, bool allowed_) external;
}

interface IVaultT4Liquidate {
    function liquidate(
        uint256 token0DebtAmt_,
        uint256 token1DebtAmt_,
        uint256 debtSharesMin_,
        uint256 colPerUnitDebt_,
        uint256 token0ColAmtPerUnitShares_,
        uint256 token1ColAmtPerUnitShares_,
        address to_,
        bool absorb_
    )
        external
        payable
        returns (uint256 actualDebtShares_, uint256 actualColShares_, uint256 token0Col_, uint256 token1Col_);
}

interface IVaultT4Operate {
    function operate(
        uint256 nftId_,
        int256 newColToken0_,
        int256 newColToken1_,
        int256 colSharesMinMax_,
        int256 newDebtToken0_,
        int256 newDebtToken1_,
        int256 debtSharesMinMax_,
        address to_
    ) external payable returns (uint256, int256, int256);
}

// To test run:
// forge test -vvv --match-path test/foundry/config/pauseAuthDexFork.t.sol
/// @dev live pool: the preset blocks a DEX borrow, payback still goes through, restore is bit-exact
contract PauseAuthDexForkTest is Test {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC");

    address internal constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address internal constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;
    address internal constant TIMELOCK = 0x2386DC45AdDed673317eF068992F19421B481F4c;
    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    address internal constant VAULT_FACTORY = 0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d;
    address internal constant DEX_FACTORY = 0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085;
    address internal constant SMART_LENDING_FACTORY = 0xe57227C7d5900165344b190fc7aa580bceb53B9B;

    address internal constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;
    address internal constant VAULT_WSTETH_ETH_T4 = 0x528CF7DBBff878e02e48E83De5097F8071af768D;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    uint256 internal constant USER_BORROW_CONFIG_MASK = ((1 << 74) - 1) << 162;
    uint256 internal constant BORROW_AMOUNT = 1e15;

    FluidPauseAuthDex internal pauseAuthDex;
    uint256 internal vaultId;

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 21680552);

        address authGate_ = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, makeAddr("teamTimelock"))
        );
        pauseAuthDex = new FluidPauseAuthDex(LIQUIDITY, VAULT_FACTORY, DEX_FACTORY, SMART_LENDING_FACTORY, authGate_);

        vm.prank(TEAM_MULTISIG);
        pauseAuthDex.setPauseAuthContract(address(this));
        vm.prank(TIMELOCK);
        IFluidDexFactoryAuth(DEX_FACTORY).setGlobalAuth(address(pauseAuthDex), true);

        vaultId = IFluidVault(VAULT_WSTETH_ETH_T4).VAULT_ID();
    }

    function _borrowWord() internal view returns (uint256) {
        return
            IFluidDexT1(DEX_WSTETH_ETH).readFromStorage(
                DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT, VAULT_WSTETH_ETH_T4)
            );
    }

    function _borrowAsVault() internal {
        vm.prank(VAULT_WSTETH_ETH_T4);
        IFluidDexT1(DEX_WSTETH_ETH).borrow(BORROW_AMOUNT, 0, type(uint256).max, address(this));
    }

    function _freeze() internal returns (uint256 before_) {
        before_ = _borrowWord();
        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.pauseVault(vaultId, false, false, true, false);
        assertTrue(actedBorrow_);
        assertFalse(actedPayback_);
    }

    function test_fork_pauseVault_borrowOnlyBlocksNewBorrowsOnly() public {
        // positive control: the same borrow goes through before the freeze
        uint256 snapshotId_ = vm.snapshot();
        _borrowAsVault();
        vm.revertTo(snapshotId_);

        uint256 before_ = _freeze();

        uint256 live_ = _borrowWord();
        assertEq(live_ & 1, 1, "side must stay open");
        assertEq((live_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & 0x3fff, 1);
        assertEq((live_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & 0xffffff, 0xffffff);
        assertEq(
            BigMathMinified.fromBigNumber(
                (live_ >> DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & 0x3ffff,
                8,
                0xFF
            ),
            10
        );
        assertEq(
            BigMathMinified.fromBigNumber((live_ >> DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & 0x3ffff, 8, 0xFF),
            20
        );
        assertEq(
            live_ & ~USER_BORROW_CONFIG_MASK,
            before_ & ~USER_BORROW_CONFIG_MASK,
            "amount, limit, timestamp untouched"
        );
        assertEq(
            pauseAuthDex.dexUserBorrowSnapshot(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4),
            before_ & USER_BORROW_CONFIG_MASK
        );
        assertTrue(pauseAuthDex.isDexUserBorrowFrozen(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4));

        vm.expectRevert(
            abi.encodeWithSelector(IFluidDexT1.FluidDexError.selector, DexErrorTypes.DexT1__DebtLimitReached)
        );
        _borrowAsVault();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @dev through the vault: repayment accepted while frozen, new debt refused. The repayment ratchets the
    ///      pool's stored limit down to the dust max, so after the restore borrowing stays blocked until the
    ///      limit expands past the debt again — the documented cost of the dust max (SPEC §11).
    function test_fork_pauseVault_borrowOnlyKeepsPaybackOpen() public {
        deal(WSTETH, address(this), 2e18);
        IERC20(WSTETH).approve(VAULT_WSTETH_ETH_T4, type(uint256).max);
        (uint256 nftId_, , ) = IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(
            0,
            1e18,
            0,
            1,
            1e17,
            0,
            int256(1e30),
            address(this)
        );

        uint256 before_ = _freeze();

        IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(nftId_, 0, 0, 0, -5e16, 0, -1, address(this));
        assertEq(
            BigMathMinified.fromBigNumber(
                (_borrowWord() >> DexSlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) & 0xffffffffffffffff,
                8,
                0xFF
            ),
            20,
            "payback while frozen ratchets the stored limit to the dust max"
        );

        vm.expectRevert(
            abi.encodeWithSelector(IFluidDexT1.FluidDexError.selector, DexErrorTypes.DexT1__DebtLimitReached)
        );
        IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(nftId_, 0, 0, 0, 1e16, 0, int256(1e30), address(this));

        pauseAuthDex.unpauseVault(vaultId, false, false, true, false);
        _assertBorrowableAfterFullExpansion(nftId_, before_);
    }

    /// @dev the ramp is bounded by one full expansion of the restored config, never longer
    function _assertBorrowableAfterFullExpansion(uint256 nftId_, uint256 before_) internal {
        uint256 duration_ = (before_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & 0xffffff;
        uint256 percent_ = (before_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & 0x3fff;
        // limit climbs by percent of debt per duration, so reaching the debt takes 1e4/percent of them
        vm.warp(block.timestamp + (duration_ * 10000) / percent_ + duration_);
        IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(nftId_, 0, 0, 0, 1e16, 0, int256(1e30), address(this));
    }

    function test_fork_unpauseVault_borrowOnlyRestoresConfigBitForBit() public {
        uint256 before_ = _freeze();

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseVault(vaultId, false, false, true, false);
        assertTrue(actedBorrow_);
        assertFalse(actedPayback_);

        assertEq(_borrowWord(), before_);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4), 0);
        assertFalse(pauseAuthDex.isDexUserBorrowFrozen(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4));

        _borrowAsVault();
    }

    function test_fork_pauseVault_borrowOnlyTwiceIsNoOp() public {
        uint256 before_ = _freeze();

        (, , , bool actedBorrow_, ) = pauseAuthDex.pauseVault(vaultId, false, false, true, false);
        assertFalse(actedBorrow_);
        assertEq(
            pauseAuthDex.dexUserBorrowSnapshot(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4),
            before_ & USER_BORROW_CONFIG_MASK
        );
    }

    function test_fork_unpauseVault_wholeSideAfterConfigChangeReopensPayback() public {
        deal(WSTETH, address(this), 2e18);
        IERC20(WSTETH).approve(VAULT_WSTETH_ETH_T4, type(uint256).max);
        (uint256 nftId_, , ) = IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(
            0,
            1e18,
            0,
            1,
            1e17,
            0,
            int256(1e30),
            address(this)
        );

        uint256 before_ = _freeze();

        AdminModuleStructs.UserBorrowConfig[] memory configs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        configs_[0] = AdminModuleStructs.UserBorrowConfig(
            VAULT_WSTETH_ETH_T4,
            (before_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & 0x3fff,
            (before_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & 0xffffff,
            BigMathMinified.fromBigNumber(
                (before_ >> DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & 0x3ffff,
                8,
                0xFF
            ),
            BigMathMinified.fromBigNumber(
                (before_ >> DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & 0x3ffff,
                8,
                0xFF
            ) * 2
        );
        vm.prank(TIMELOCK);
        IFluidDexT1Admin(DEX_WSTETH_ETH).updateUserBorrowConfigs(configs_);

        uint256 governanceWord_ = _borrowWord();
        assertFalse(pauseAuthDex.isDexUserBorrowFrozen(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4));
        assertTrue(pauseAuthDex.dexUserBorrowSnapshot(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4) != 0);

        pauseAuthDex.pauseVault(vaultId, false, false, true, true);
        assertEq(_borrowWord() & 1, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IFluidDexT1.FluidDexError.selector, DexErrorTypes.DexT1__UserDebtInNotOn)
        );
        IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(nftId_, 0, 0, 0, -5e16, 0, -1, address(this));

        (, , , bool actedBorrow_, bool actedPayback_) = pauseAuthDex.unpauseVault(vaultId, false, false, true, true);
        assertTrue(actedBorrow_);
        assertTrue(actedPayback_);

        assertEq(_borrowWord() & 1, 1);
        assertEq(_borrowWord() & USER_BORROW_CONFIG_MASK, governanceWord_ & USER_BORROW_CONFIG_MASK);
        assertEq(pauseAuthDex.dexUserBorrowSnapshot(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4), 0);

        IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(nftId_, 0, 0, 0, -5e16, 0, -1, address(this));
    }

    /// @dev debt just under the 95% CF, so this position becomes the vault's top tick and a small price move reaches it
    function _openLeveragedPosition() internal returns (uint256 nftId_) {
        deal(WSTETH, address(this), 3e18);
        IERC20(WSTETH).approve(VAULT_WSTETH_ETH_T4, type(uint256).max);
        (nftId_, , ) = IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(
            0,
            2e18,
            0,
            1,
            1.895e18,
            0,
            int256(1e30),
            address(this)
        );
    }

    /// @dev 3% below the real price: past the CF/threshold gap without also crossing the max-limit that forces an absorb
    function _shockOraclePrice() internal {
        IFluidVault.ConstantViews memory constants_ = IFluidVault(VAULT_WSTETH_ETH_T4).constantsView();
        uint256 vaultVariables2_ = IFluidVault(VAULT_WSTETH_ETH_T4).readFromStorage(bytes32(uint256(1)));
        address oracle_ = AddressCalcs.addressCalc(constants_.deployer, (vaultVariables2_ >> 92) & 0x3fffffff);
        uint256 price_ = IFluidOracle(oracle_).getExchangeRateLiquidate();
        vm.mockCall(
            oracle_,
            abi.encodeWithSelector(IFluidOracle.getExchangeRateLiquidate.selector),
            abi.encode((price_ * 970) / 1000)
        );
    }

    function _liquidateSmall()
        internal
        returns (uint256 actualDebtShares_, uint256 actualColShares_, uint256 token0Col_)
    {
        (actualDebtShares_, actualColShares_, token0Col_, ) = IVaultT4Liquidate(VAULT_WSTETH_ETH_T4).liquidate(
            1e16,
            0,
            0,
            0,
            1e14,
            0,
            address(this),
            false
        );
    }

    function test_fork_liquidate_worksWhileFrozen() public {
        _openLeveragedPosition();
        _freeze();
        _shockOraclePrice();

        (uint256 actualDebtShares_, uint256 actualColShares_, uint256 token0Col_) = _liquidateSmall();
        assertTrue(actualDebtShares_ > 0 && actualColShares_ > 0 && token0Col_ > 0);
    }

    function test_fork_liquidate_revertsUnderWholeSidePause() public {
        _openLeveragedPosition();
        pauseAuthDex.pauseVault(vaultId, false, false, true, true);
        _shockOraclePrice();

        vm.expectRevert(
            abi.encodeWithSelector(IFluidDexT1.FluidDexError.selector, DexErrorTypes.DexT1__UserDebtInNotOn)
        );
        _liquidateSmall();
    }

    function test_fork_liquidate_worksAfterRestoreDuringRamp() public {
        uint256 nftId_ = _openLeveragedPosition();
        _freeze();

        IVaultT4Operate(VAULT_WSTETH_ETH_T4).operate(nftId_, 0, 0, 0, -1e15, 0, -1, address(this));
        pauseAuthDex.unpauseVault(vaultId, false, false, true, false);

        vm.expectRevert(
            abi.encodeWithSelector(IFluidDexT1.FluidDexError.selector, DexErrorTypes.DexT1__DebtLimitReached)
        );
        _borrowAsVault();

        _shockOraclePrice();

        (uint256 actualDebtShares_, uint256 actualColShares_, uint256 token0Col_) = _liquidateSmall();
        assertTrue(actualDebtShares_ > 0 && actualColShares_ > 0 && token0Col_ > 0);
    }
}
