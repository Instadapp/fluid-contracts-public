// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { Structs } from "contracts/liquidity/adminModule/structs.sol";
import { BigMathMinified } from "contracts/libraries/bigMathMinified.sol";
import { FluidLimitsAuthDex } from "contracts/config/limitsAuthDex/main.sol";
import { IFluidLiquidity } from "contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "contracts/protocols/dex/poolT1/adminModule/structs.sol";

interface IFluidDexFactory {
    function setDexAuth(address dex_, address dexAuth_, bool allowed_) external;
}

// To test run:
// forge test -vvv --match-path test/foundry/config/limitsAuthDex.t.sol
contract LimitsAuthDexTest is Test {
    using BigMathMinified for uint256;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC");

    address public immutable TEAM_MULTISIG_MAINNET = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public immutable TEAM_MULTISIG_MAINNET2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    address internal constant TIMELOCK = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address internal constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;

    address internal constant VAULT_WSTETH_ETH_T4 = 0x528CF7DBBff878e02e48E83De5097F8071af768D;

    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    uint256 internal constant SMALL_COEFFICIENT_SIZE = 10;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    IFluidDexFactory internal constant DEX_FACTORY_MAINNET =
        IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    FluidLimitsAuthDex public fluidLimitsAuthDex;

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 21680552);
        _deployNewHandler();
    }

    function _deployNewHandler() internal {
        fluidLimitsAuthDex = new FluidLimitsAuthDex();

        // authorize handler at liquidity
        Structs.AddressBool[] memory updateAuthsParams = new Structs.AddressBool[](1);
        updateAuthsParams[0] = Structs.AddressBool(address(fluidLimitsAuthDex), true);

        vm.startPrank(TIMELOCK);
        DEX_FACTORY_MAINNET.setDexAuth(DEX_WSTETH_ETH, address(fluidLimitsAuthDex), true);
        vm.stopPrank();
    }

    function test_SetUserWithdrawLimit() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET2);
        vm.deal(TEAM_MULTISIG_MAINNET2, 1 ether);

        AdminModuleStructs.UserSupplyConfig memory oldUserSupplyConfigs_ = fluidLimitsAuthDex.getUserSupplyConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        emit log_named_uint("Base withdrawal limit", oldUserSupplyConfigs_.baseWithdrawalLimit);
        emit log_named_uint("Expand percentage", oldUserSupplyConfigs_.expandPercent);
        emit log_named_uint("Expand duration", oldUserSupplyConfigs_.expandDuration);

        // reduce withdrawal limit by 10%
        uint256 baseLimit_ = (oldUserSupplyConfigs_.baseWithdrawalLimit * 90) / 100;

        // set user withdraw limit
        fluidLimitsAuthDex.setUserWithdrawLimit(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, baseLimit_, false);

        vm.stopPrank();

        // get user supply data from dex
        AdminModuleStructs.UserSupplyConfig memory newUserSupplyConfigs_ = fluidLimitsAuthDex.getUserSupplyConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        baseLimit_ = baseLimit_.toBigNumber(SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);
        baseLimit_ = BigMathMinified.fromBigNumber(baseLimit_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        assertEq(newUserSupplyConfigs_.baseWithdrawalLimit, baseLimit_);
        assertEq(newUserSupplyConfigs_.expandPercent, oldUserSupplyConfigs_.expandPercent);
        assertEq(newUserSupplyConfigs_.expandDuration, oldUserSupplyConfigs_.expandDuration);
    }

    function test_RevertIfExceedAllowedPercentageChange() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        AdminModuleStructs.UserSupplyConfig memory oldUserSupplyConfigs_ = fluidLimitsAuthDex.getUserSupplyConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        uint256 baseLimit_ = (oldUserSupplyConfigs_.baseWithdrawalLimit * 75) / 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.LimitsAuth__ExceedAllowedPercentageChange
            )
        );
        fluidLimitsAuthDex.setUserWithdrawLimit(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, baseLimit_, false);

        // ignore when flag true
        fluidLimitsAuthDex.setUserWithdrawLimit(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, baseLimit_, true);
        vm.stopPrank();
    }
    function test_SetUserWithdrawLimitCooldown() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        AdminModuleStructs.UserSupplyConfig memory userSupplyConfigs_ = fluidLimitsAuthDex.getUserSupplyConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        fluidLimitsAuthDex.setUserWithdrawLimit(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4,
            (userSupplyConfigs_.baseWithdrawalLimit * 110) / 100,
            false
        );

        vm.warp(block.timestamp + 1);

        fluidLimitsAuthDex.setUserWithdrawLimit(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4,
            (userSupplyConfigs_.baseWithdrawalLimit * 120) / 100,
            false
        );

        vm.stopPrank();
    }

    function test_SetUserBorrowLimits() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        AdminModuleStructs.UserBorrowConfig memory oldUserBorrowConfigs_ = fluidLimitsAuthDex.getUserBorrowConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        // reduce base borrow limit by 10%
        uint256 baseLimit_ = (oldUserBorrowConfigs_.baseDebtCeiling * 90) / 100;

        // reduce max borrow limit by 10%
        uint256 maxLimit_ = (oldUserBorrowConfigs_.maxDebtCeiling * 90) / 100;

        emit log_named_uint("Base borrow limit", baseLimit_);
        emit log_named_uint("Max borrow limit", maxLimit_);

        // set user borrow limit
        fluidLimitsAuthDex.setUserBorrowLimits(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, baseLimit_, maxLimit_);

        vm.stopPrank();

        // get user borrow data from dex
        AdminModuleStructs.UserBorrowConfig memory newUserBorrowConfigs_ = fluidLimitsAuthDex.getUserBorrowConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        baseLimit_ = baseLimit_.toBigNumber(SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);
        baseLimit_ = BigMathMinified.fromBigNumber(baseLimit_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        maxLimit_ = maxLimit_.toBigNumber(SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);
        maxLimit_ = BigMathMinified.fromBigNumber(maxLimit_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        assertEq(newUserBorrowConfigs_.baseDebtCeiling, baseLimit_);
        assertEq(newUserBorrowConfigs_.maxDebtCeiling, maxLimit_);
        assertEq(newUserBorrowConfigs_.expandPercent, oldUserBorrowConfigs_.expandPercent);
        assertEq(newUserBorrowConfigs_.expandDuration, oldUserBorrowConfigs_.expandDuration);
    }

    function test_SetUserBorrowLimitsKeepOldValues() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        AdminModuleStructs.UserBorrowConfig memory oldUserBorrowConfigs_ = fluidLimitsAuthDex.getUserBorrowConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        uint256 baseLimit_ = (oldUserBorrowConfigs_.baseDebtCeiling * 110) / 100;

        // set user borrow limit
        fluidLimitsAuthDex.setUserBorrowLimits(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, baseLimit_, 0);

        // get user borrow data from dex
        AdminModuleStructs.UserBorrowConfig memory newUserBorrowConfigs_ = fluidLimitsAuthDex.getUserBorrowConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        baseLimit_ = baseLimit_.toBigNumber(SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);
        baseLimit_ = BigMathMinified.fromBigNumber(baseLimit_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        assertEq(newUserBorrowConfigs_.baseDebtCeiling, baseLimit_);
        assertEq(newUserBorrowConfigs_.maxDebtCeiling, oldUserBorrowConfigs_.maxDebtCeiling);
        assertEq(newUserBorrowConfigs_.expandPercent, oldUserBorrowConfigs_.expandPercent);
        assertEq(newUserBorrowConfigs_.expandDuration, oldUserBorrowConfigs_.expandDuration);

        oldUserBorrowConfigs_ = fluidLimitsAuthDex.getUserBorrowConfig(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4);

        uint256 maxLimit_ = (oldUserBorrowConfigs_.maxDebtCeiling * 110) / 100;

        vm.warp(block.timestamp + 10 days);

        // set user borrow limit
        fluidLimitsAuthDex.setUserBorrowLimits(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, 0, maxLimit_);

        vm.stopPrank();

        // get user borrow data from dex
        newUserBorrowConfigs_ = fluidLimitsAuthDex.getUserBorrowConfig(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4);

        maxLimit_ = maxLimit_.toBigNumber(SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);
        maxLimit_ = BigMathMinified.fromBigNumber(maxLimit_, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

        assertEq(newUserBorrowConfigs_.baseDebtCeiling, oldUserBorrowConfigs_.baseDebtCeiling);
        assertEq(newUserBorrowConfigs_.maxDebtCeiling, maxLimit_);
        assertEq(newUserBorrowConfigs_.expandPercent, oldUserBorrowConfigs_.expandPercent);
        assertEq(newUserBorrowConfigs_.expandDuration, oldUserBorrowConfigs_.expandDuration);
    }

    function test_SetUserBorrowLimitsCooldown() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        AdminModuleStructs.UserBorrowConfig memory oldUserBorrowConfigs_ = fluidLimitsAuthDex.getUserBorrowConfig(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4
        );

        // set user borrow limit
        fluidLimitsAuthDex.setUserBorrowLimits(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4,
            (oldUserBorrowConfigs_.baseDebtCeiling * 110) / 100,
            0
        );

        vm.warp(block.timestamp + 1);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__CoolDownPending)
        );
        fluidLimitsAuthDex.setUserBorrowLimits(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4,
            (oldUserBorrowConfigs_.baseDebtCeiling * 120) / 100,
            0
        );

        vm.warp(block.timestamp + 5 days);
        fluidLimitsAuthDex.setUserBorrowLimits(
            DEX_WSTETH_ETH,
            VAULT_WSTETH_ETH_T4,
            (oldUserBorrowConfigs_.baseDebtCeiling * 120) / 100,
            0
        );

        vm.stopPrank();
    }

    function test_SetMaxBorrowShares() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);

        uint256 currentMaxBorrowShares_ = fluidLimitsAuthDex.getMaxBorrowShares(DEX_WSTETH_ETH);
        uint256 maxBorrowShares_ = (currentMaxBorrowShares_ * 110) / 100;
        fluidLimitsAuthDex.setMaxBorrowShares(DEX_WSTETH_ETH, maxBorrowShares_, true);

        vm.stopPrank();

        uint256 newMaxBorrowShares_ = fluidLimitsAuthDex.getMaxBorrowShares(DEX_WSTETH_ETH);
        assertEq(newMaxBorrowShares_, maxBorrowShares_);
    }

    function test_SetMaxSupplyShares() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);

        uint256 currentMaxSupplyShares_ = fluidLimitsAuthDex.getMaxSupplyShares(DEX_WSTETH_ETH);
        uint256 maxSupplyShares_ = (currentMaxSupplyShares_ * 110) / 100;
        fluidLimitsAuthDex.setMaxSupplyShares(DEX_WSTETH_ETH, maxSupplyShares_, true);

        vm.stopPrank();

        uint256 newMaxSupplyShares_ = fluidLimitsAuthDex.getMaxSupplyShares(DEX_WSTETH_ETH);
        assertEq(newMaxSupplyShares_, maxSupplyShares_);
    }

    function test_SetMaxShares() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);

        uint256 currentMaxSupplyShares_ = fluidLimitsAuthDex.getMaxSupplyShares(DEX_WSTETH_ETH);
        uint256 maxSupplyShares_ = (currentMaxSupplyShares_ * 110) / 100;
        uint256 currentMaxBorrowShares_ = fluidLimitsAuthDex.getMaxBorrowShares(DEX_WSTETH_ETH);
        uint256 maxBorrowShares_ = (currentMaxBorrowShares_ * 110) / 100;
        fluidLimitsAuthDex.setMaxShares(DEX_WSTETH_ETH, maxSupplyShares_, maxBorrowShares_, true);

        vm.stopPrank();

        uint256 newMaxBorrowShares_ = fluidLimitsAuthDex.getMaxBorrowShares(DEX_WSTETH_ETH);
        assertEq(newMaxBorrowShares_, maxBorrowShares_);

        uint256 newMaxSupplyShares_ = fluidLimitsAuthDex.getMaxSupplyShares(DEX_WSTETH_ETH);
        assertEq(newMaxSupplyShares_, maxSupplyShares_);
    }

    function _validateAllMaxSharesOnCooldown(address dex_) internal {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__CoolDownPending)
        );
        fluidLimitsAuthDex.setMaxShares(dex_, 10000000000000, 10000000000000, true);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__CoolDownPending)
        );
        fluidLimitsAuthDex.setMaxSupplyShares(dex_, 10000000000000, true);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__CoolDownPending)
        );
        fluidLimitsAuthDex.setMaxBorrowShares(dex_, 10000000000000, true);
    }

    function test_RevertIfMaxSharesCooldown() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        uint256 currentMaxSupplyShares_ = fluidLimitsAuthDex.getMaxSupplyShares(DEX_WSTETH_ETH);
        uint256 maxSupplyShares_ = (currentMaxSupplyShares_ * 110) / 100;
        uint256 currentMaxBorrowShares_ = fluidLimitsAuthDex.getMaxBorrowShares(DEX_WSTETH_ETH);
        uint256 maxBorrowShares_ = (currentMaxBorrowShares_ * 110) / 100;
        fluidLimitsAuthDex.setMaxShares(DEX_WSTETH_ETH, maxSupplyShares_, maxBorrowShares_, true);

        vm.warp(block.timestamp + 1);
        _validateAllMaxSharesOnCooldown(DEX_WSTETH_ETH);

        vm.warp(block.timestamp + 5 days);
        fluidLimitsAuthDex.setMaxBorrowShares(DEX_WSTETH_ETH, (maxBorrowShares_ * 110) / 100, true);
    }

    function test_RevertIfMaxBorrowSharesCooldown() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        uint256 currentMaxBorrowShares_ = fluidLimitsAuthDex.getMaxBorrowShares(DEX_WSTETH_ETH);
        uint256 maxBorrowShares_ = (currentMaxBorrowShares_ * 110) / 100;

        fluidLimitsAuthDex.setMaxBorrowShares(DEX_WSTETH_ETH, maxBorrowShares_, true);

        vm.warp(block.timestamp + 1);
        _validateAllMaxSharesOnCooldown(DEX_WSTETH_ETH);

        vm.warp(block.timestamp + 5 days);
        fluidLimitsAuthDex.setMaxBorrowShares(DEX_WSTETH_ETH, (maxBorrowShares_ * 110) / 100, true);
    }

    function test_RevertIfMaxSupplySharesCooldown() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        uint256 currentMaxSupplyShares_ = fluidLimitsAuthDex.getMaxSupplyShares(DEX_WSTETH_ETH);
        uint256 maxSupplyShares_ = (currentMaxSupplyShares_ * 110) / 100;

        fluidLimitsAuthDex.setMaxSupplyShares(DEX_WSTETH_ETH, maxSupplyShares_, true);

        vm.warp(block.timestamp + 1);
        _validateAllMaxSharesOnCooldown(DEX_WSTETH_ETH);

        vm.warp(block.timestamp + 5 days);
        fluidLimitsAuthDex.setMaxSupplyShares(DEX_WSTETH_ETH, (maxSupplyShares_ * 110) / 100, true);
    }

    function test_RevertIfMaxBorrowSharesExceedsMaxAllowedPercentage() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        uint256 currentMaxBorrowShares_ = fluidLimitsAuthDex.getMaxBorrowShares(DEX_WSTETH_ETH);
        uint256 maxBorrowShares_ = (currentMaxBorrowShares_ * 250) / 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.LimitsAuth__ExceedAllowedPercentageChange
            )
        );
        fluidLimitsAuthDex.setMaxBorrowShares(DEX_WSTETH_ETH, maxBorrowShares_, true);
    }

    function test_RevertIfMaxSupplySharesExceedsMaxAllowedPercentage() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        uint256 currentMaxSupplyShares_ = fluidLimitsAuthDex.getMaxSupplyShares(DEX_WSTETH_ETH);
        uint256 maxSupplyShares_ = (currentMaxSupplyShares_ * 250) / 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.LimitsAuth__ExceedAllowedPercentageChange
            )
        );
        fluidLimitsAuthDex.setMaxSupplyShares(DEX_WSTETH_ETH, maxSupplyShares_, true);
    }

    function test_RevertIfConfirmLiquidityLimitsCoverCapIsFalse() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);

        uint256 currentMaxBorrowShares_ = fluidLimitsAuthDex.getMaxBorrowShares(DEX_WSTETH_ETH);
        uint256 maxBorrowShares_ = (currentMaxBorrowShares_ * 110) / 100;
        uint256 currentMaxSupplyShares_ = fluidLimitsAuthDex.getMaxSupplyShares(DEX_WSTETH_ETH);
        uint256 maxSupplyShares_ = (currentMaxSupplyShares_ * 110) / 100;

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__InvalidParams));
        fluidLimitsAuthDex.setMaxBorrowShares(DEX_WSTETH_ETH, maxBorrowShares_, false);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__InvalidParams));
        fluidLimitsAuthDex.setMaxSupplyShares(DEX_WSTETH_ETH, maxSupplyShares_, false);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__InvalidParams));
        fluidLimitsAuthDex.setMaxShares(DEX_WSTETH_ETH, maxSupplyShares_, maxBorrowShares_, false);
    }

    function test_RevertIfNotMultisig() public {
        vm.startPrank(address(0xbeef));

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        fluidLimitsAuthDex.setMaxBorrowShares(DEX_WSTETH_ETH, 1000000000000000000, true);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        fluidLimitsAuthDex.setMaxSupplyShares(DEX_WSTETH_ETH, 1000000000000000000, true);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        fluidLimitsAuthDex.setMaxShares(DEX_WSTETH_ETH, 1000000000000000000, 1000000000000000000, true);

        // expect revert unauthorized for setUserBorrowLimits
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        fluidLimitsAuthDex.setUserBorrowLimits(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, 1000, 100);

        // expect revert unauthorized for setUserWithdrawLimit
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        fluidLimitsAuthDex.setUserWithdrawLimit(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, 1000, false);

        // expect revert unauthorized for setWithdrawalLimit
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        fluidLimitsAuthDex.setWithdrawalLimit(DEX_WSTETH_ETH, VAULT_WSTETH_ETH_T4, 1000);
    }
}
