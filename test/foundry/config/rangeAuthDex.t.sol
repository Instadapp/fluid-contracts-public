// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { BigMathMinified } from "contracts/libraries/bigMathMinified.sol";
import { FluidRangeAuthDex, IFluidDexT1Admin } from "contracts/config/rangeAuthDex/main.sol";
import { IFluidLiquidity } from "contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs } from "contracts/liquidity/adminModule/structs.sol";
import { Structs as AdminModuleStructs } from "contracts/protocols/dex/poolT1/adminModule/structs.sol";

error Access__Unauthorized();

interface IFluidDexFactory {
    function setDexAuth(address dex_, address dexAuth_, bool allowed_) external;
}

contract MockAuthGateZeroLiquidity {
    function LIQUIDITY() external pure returns (address) {}
}

contract MockAuthGateNoGetter {
    fallback() external {}
}

// To test run:
// forge test -vvv --match-path test/foundry/config/rangeAuthDex.t.sol
contract RangeAuthDexTest is Test {
    using BigMathMinified for uint256;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC");

    address public immutable TEAM_MULTISIG_MAINNET = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public immutable TEAM_MULTISIG_MAINNET2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    address internal constant TIMELOCK = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    uint256 internal constant SMALL_COEFFICIENT_SIZE = 10;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    IFluidDexFactory internal constant DEX_FACTORY_MAINNET =
        IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    FluidRangeAuthDex public fluidRangeAuthDex;

    address internal constant DEX_WEETH_ETH = 0x86f874212335Af27C41cDb855C2255543d1499cE;
    address internal constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;
    address internal constant DEX_WEETHS_ETH = 0x080574D224E960c272e005aA03EFbe793f317640;

    uint256 internal constant FOUR_DECIMALS = 1e4;

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 21690552);
        _deployNewHandler();
    }

    function _deployNewHandler() internal {
        address authGate_ = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(address(LIQUIDITY), TEAM_MULTISIG_MAINNET, TEAM_MULTISIG_MAINNET2, makeAddr("teamTimelock"))
        );
        fluidRangeAuthDex = new FluidRangeAuthDex(DEX_WSTETH_ETH, DEX_WEETH_ETH, authGate_);

        // authorize handler at liquidity
        Structs.AddressBool[] memory updateAuthsParams = new Structs.AddressBool[](1);
        updateAuthsParams[0] = Structs.AddressBool(address(fluidRangeAuthDex), true);

        vm.startPrank(TIMELOCK);
        DEX_FACTORY_MAINNET.setDexAuth(DEX_WSTETH_ETH, address(fluidRangeAuthDex), true);
        DEX_FACTORY_MAINNET.setDexAuth(DEX_WEETHS_ETH, address(fluidRangeAuthDex), true);
        DEX_FACTORY_MAINNET.setDexAuth(DEX_WEETH_ETH, address(fluidRangeAuthDex), true);
        vm.stopPrank();
    }

    function _setThresholdBaseline(
        address dex_,
        uint256 upper_,
        uint256 lower_
    ) internal returns (uint256 thresholdShiftTime_) {
        (, , thresholdShiftTime_) = fluidRangeAuthDex.getThresholdConfig(dex_);
        vm.prank(TIMELOCK);
        IFluidDexT1Admin(dex_).updateThresholdPercent(upper_, lower_, thresholdShiftTime_, 0);
    }

    function test_constructor_RevertIfAuthGateHasNoLiquidity() public {
        address gate_ = address(new MockAuthGateZeroLiquidity());
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidParams)
        );
        new FluidRangeAuthDex(DEX_WSTETH_ETH, DEX_WEETH_ETH, gate_);
    }

    function test_constructor_RevertIfAuthGateHasNoGetter() public {
        address gate_ = address(new MockAuthGateNoGetter());
        vm.expectRevert();
        new FluidRangeAuthDex(DEX_WSTETH_ETH, DEX_WEETH_ETH, gate_);
    }

    function test_RevertIfSetRangesNoChange() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (uint256 upperRangePercent_, uint256 lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__NoChange));
        fluidRangeAuthDex.setRanges(DEX_WEETHS_ETH, upperRangePercent_, lowerRangePercent_, 2 days);

        vm.stopPrank();
    }

    function test_RevertIfSetRangesByPercentageNoChange() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__NoChange));
        fluidRangeAuthDex.setRangesByPercentage(DEX_WEETHS_ETH, 0, 0, 2 days);

        vm.stopPrank();
    }

    function test_RevertIfSetThresholdConfigNoChange() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (
            uint256 upperThresholdPercent_,
            uint256 lowerThresholdPercent_,
            uint256 thresholdShiftTime_
        ) = fluidRangeAuthDex.getThresholdConfig(DEX_WEETHS_ETH);

        uint256 newUpperThresholdPercent_ = ((upperThresholdPercent_ / 1e3) * 1e3) + 999;
        uint256 newLowerThresholdPercent_ = ((lowerThresholdPercent_ / 1e3) * 1e3) + 999;

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__NoChange));
        fluidRangeAuthDex.setThresholdConfig(
            DEX_WEETHS_ETH,
            newUpperThresholdPercent_,
            newLowerThresholdPercent_,
            thresholdShiftTime_,
            2 days
        );

        vm.stopPrank();
    }

    function test_setRanges() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET2);
        vm.deal(TEAM_MULTISIG_MAINNET2, 1 ether);

        (uint256 upperRangePercent_, uint256 lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        // increase ranges by 1%
        uint256 newUpperRangePercent_ = ((upperRangePercent_ * 101)) / 100;
        uint256 newLowerRangePercent_ = ((lowerRangePercent_ * 101)) / 100;

        // set user withdraw limit
        fluidRangeAuthDex.setRanges(DEX_WEETHS_ETH, newUpperRangePercent_, newLowerRangePercent_, 2 days);

        vm.stopPrank();

        // get user supply data from dex
        (upperRangePercent_, lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        assertEq(upperRangePercent_, newUpperRangePercent_);
        assertEq(lowerRangePercent_, newLowerRangePercent_);
    }

    function test_setRangesByPercentageUp() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (uint256 upperRangePercent_, uint256 lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        // increase ranges by 1%
        int256 newUpperRangePercentage_ = 1e4; // 1% = 1e4
        int256 newLowerRangePercentage_ = 1e4; // 1% = 1e4

        // set user withdraw limit
        fluidRangeAuthDex.setRangesByPercentage(
            DEX_WEETHS_ETH,
            newUpperRangePercentage_,
            newLowerRangePercentage_,
            2 days
        );

        // increase ranges by 1%
        uint256 newUpperRangePercent_ = ((upperRangePercent_ * 101)) / 100;
        uint256 newLowerRangePercent_ = ((lowerRangePercent_ * 101)) / 100;

        vm.stopPrank();

        // get user supply data from dex
        (upperRangePercent_, lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        assertEq(upperRangePercent_, newUpperRangePercent_);
        assertEq(lowerRangePercent_, newLowerRangePercent_);
    }

    function test_setRangesByPercentageDown() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (uint256 upperRangePercent_, uint256 lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        // increase ranges by 1%
        int256 newUpperRangePercentage_ = 1e4; // 1% = 1e4

        // decrease ranges by 1%
        int256 newLowerRangePercentage_ = -1e4; // 1% = 1e4

        // set user withdraw limit
        fluidRangeAuthDex.setRangesByPercentage(
            DEX_WEETHS_ETH,
            newUpperRangePercentage_,
            newLowerRangePercentage_,
            2 days
        );

        // increase ranges by 1%
        uint256 newUpperRangePercent_ = ((upperRangePercent_ * 101)) / 100;
        uint256 newLowerRangePercent_ = ((lowerRangePercent_ * 99)) / 100;

        vm.stopPrank();

        // get user supply data from dex
        (upperRangePercent_, lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        assertEq(upperRangePercent_, newUpperRangePercent_);
        assertEq(lowerRangePercent_, newLowerRangePercent_);
    }

    function test_SetThresholdConfig() public {
        _setThresholdBaseline(DEX_WEETHS_ETH, 10e4, 10e4);

        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (
            uint256 upperThresholdPercent_,
            uint256 lowerThresholdPercent_,
            uint256 thresholdShiftTime_
        ) = fluidRangeAuthDex.getThresholdConfig(DEX_WEETHS_ETH);

        uint256 newUpperThresholdPercent_ = upperThresholdPercent_ + 1e4; // 1% = 1e4
        uint256 newLowerThresholdPercent_ = lowerThresholdPercent_ + 1e4; // 1% = 1e4
        uint256 newThresholdShiftTime_ = thresholdShiftTime_;

        // set user withdraw limit
        fluidRangeAuthDex.setThresholdConfig(
            DEX_WEETHS_ETH,
            newUpperThresholdPercent_,
            newLowerThresholdPercent_,
            newThresholdShiftTime_,
            2 days
        );

        vm.stopPrank();

        (upperThresholdPercent_, lowerThresholdPercent_, thresholdShiftTime_) = fluidRangeAuthDex.getThresholdConfig(
            DEX_WEETHS_ETH
        );

        upperThresholdPercent_ = upperThresholdPercent_;
        lowerThresholdPercent_ = lowerThresholdPercent_;

        assertEq(upperThresholdPercent_, newUpperThresholdPercent_);
        assertEq(lowerThresholdPercent_, newLowerThresholdPercent_);
        assertEq(thresholdShiftTime_, newThresholdShiftTime_);
    }

    function test_RevertIfSetThresholdConfigAboveMaxAllowed() public {
        _setThresholdBaseline(DEX_WEETHS_ETH, 10e4, 10e4);

        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (
            uint256 upperThresholdPercent_,
            uint256 lowerThresholdPercent_,
            uint256 thresholdShiftTime_
        ) = fluidRangeAuthDex.getThresholdConfig(DEX_WEETHS_ETH);

        console.log("upperThresholdPercent_", upperThresholdPercent_);
        console.log("lowerThresholdPercent_", lowerThresholdPercent_);

        uint256 newUpperThresholdPercent_ = upperThresholdPercent_ + 1e4; // 1% = 1e4
        uint256 newLowerThresholdPercent_ = lowerThresholdPercent_ + 1e4; // 1% = 1e4
        uint256 newThresholdShiftTime_ = thresholdShiftTime_;

        fluidRangeAuthDex.setThresholdConfig(
            DEX_WEETHS_ETH,
            newUpperThresholdPercent_,
            newLowerThresholdPercent_,
            newThresholdShiftTime_,
            2 days
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        vm.warp(block.timestamp + 5 days);

        newUpperThresholdPercent_ = upperThresholdPercent_ + 20e4; // 1% = 1e4
        newLowerThresholdPercent_ = lowerThresholdPercent_ + 20e4; // 1% = 1e4

        fluidRangeAuthDex.setThresholdConfig(
            DEX_WEETHS_ETH,
            newUpperThresholdPercent_,
            newLowerThresholdPercent_,
            newThresholdShiftTime_,
            2 days
        );

        vm.stopPrank();
    }

    function test_setThresholdConfig_RevertIfThresholdOffZero() public {
        (uint256 upper, uint256 lower, uint256 t) = fluidRangeAuthDex.getThresholdConfig(DEX_WEETHS_ETH);
        assertEq(upper, 0);
        assertEq(lower, 0);

        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );
        fluidRangeAuthDex.setThresholdConfig(DEX_WEETHS_ETH, 1e4, 1e4, t, 2 days);

        (uint256 upperWsteth, uint256 lowerWsteth, uint256 tWsteth) = fluidRangeAuthDex.getThresholdConfig(
            DEX_WSTETH_ETH
        );
        assertEq(upperWsteth, 0);
        assertEq(lowerWsteth, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );
        fluidRangeAuthDex.setThresholdConfig(DEX_WSTETH_ETH, 1e4, 1e4, tWsteth, 0);

        vm.stopPrank();
    }

    function test_setThresholdConfig_zeroThresholdsAllowShiftTimeChange() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (uint256 upper, uint256 lower, uint256 t) = fluidRangeAuthDex.getThresholdConfig(DEX_WEETHS_ETH);

        uint256 newT = (t * 9) / 10;
        fluidRangeAuthDex.setThresholdConfig(DEX_WEETHS_ETH, 0, 0, newT, 2 days);

        (upper, lower, t) = fluidRangeAuthDex.getThresholdConfig(DEX_WEETHS_ETH);
        assertEq(upper, 0);
        assertEq(lower, 0);
        assertEq(t, newT);

        vm.stopPrank();
    }

    function test_setThresholdConfig_truncationToZeroIsOneWay() public {
        uint256 t = _setThresholdBaseline(DEX_WEETHS_ETH, 1e3, 1e3);
        (uint256 upper, uint256 lower, ) = fluidRangeAuthDex.getThresholdConfig(DEX_WEETHS_ETH);
        assertEq(upper, 1e3);
        assertEq(lower, 1e3);

        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        fluidRangeAuthDex.setThresholdConfig(DEX_WEETHS_ETH, 700, 700, t, 2 days);

        (upper, lower, ) = fluidRangeAuthDex.getThresholdConfig(DEX_WEETHS_ETH);
        assertEq(upper, 0);
        assertEq(lower, 0);

        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );
        fluidRangeAuthDex.setThresholdConfig(DEX_WEETHS_ETH, 1e3, 1e3, t, 2 days);

        vm.stopPrank();
    }

    function test_RevertIfSetThresholdConfigInvalidShiftTime() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setThresholdConfig(DEX_WEETHS_ETH, 1, 1, 1, 2 days - 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setThresholdConfig(DEX_WEETHS_ETH, 1, 1, 1, 12 days + 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setThresholdConfig(DEX_WEETH_ETH, 1, 1, 1, 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setThresholdConfig(DEX_WSTETH_ETH, 1, 1, 1, 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        fluidRangeAuthDex.setThresholdConfig(DEX_WEETHS_ETH, 1, 1, 1, 12 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        fluidRangeAuthDex.setThresholdConfig(DEX_WEETH_ETH, 1, 1, 1, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        fluidRangeAuthDex.setThresholdConfig(DEX_WSTETH_ETH, 1, 1, 1, 0);
    }

    function test_RevertIfSetRangesByPercentageInvalidShiftTime() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setRangesByPercentage(DEX_WEETHS_ETH, 1, 1, 2 days - 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setRangesByPercentage(DEX_WEETHS_ETH, 1, 1, 12 days + 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setRangesByPercentage(DEX_WEETH_ETH, 1, 1, 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setRangesByPercentage(DEX_WSTETH_ETH, 1, 1, 2 days);

        fluidRangeAuthDex.setRangesByPercentage(DEX_WEETHS_ETH, 10_000, 10_000, 12 days);
        fluidRangeAuthDex.setRangesByPercentage(DEX_WEETH_ETH, 10_000, 10_000, 0);
        fluidRangeAuthDex.setRangesByPercentage(DEX_WSTETH_ETH, 10_000, 10_000, 0);
    }

    function test_RevertIfSetRangesInvalidShiftTime() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setRanges(DEX_WEETHS_ETH, 1, 1, 2 days - 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setRanges(DEX_WEETHS_ETH, 1, 1, 12 days + 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setRanges(DEX_WEETH_ETH, 1, 1, 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__InvalidShiftTime)
        );
        fluidRangeAuthDex.setRanges(DEX_WSTETH_ETH, 1, 1, 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        fluidRangeAuthDex.setRanges(DEX_WEETHS_ETH, 1, 1, 12 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        fluidRangeAuthDex.setRanges(DEX_WEETH_ETH, 1, 1, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        fluidRangeAuthDex.setRanges(DEX_WSTETH_ETH, 1, 1, 0);
    }

    function test_RevertIfNotMultisig() public {
        vm.startPrank(address(0xbeef));

        (uint256 upperRangePercent_, uint256 lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        // increase ranges by 1%
        int256 newUpperRangePercentage_ = 1e4; // 1% = 1e4

        // decrease ranges by 1%
        int256 newLowerRangePercentage_ = -1e4; // 1% = 1e4

        vm.expectRevert(Access__Unauthorized.selector);

        // set user withdraw limit
        fluidRangeAuthDex.setRangesByPercentage(
            DEX_WEETHS_ETH,
            newUpperRangePercentage_,
            newLowerRangePercentage_,
            2 days
        );

        // increase ranges by 1%
        uint256 newUpperRangePercent_ = ((upperRangePercent_ * 101)) / 100;
        uint256 newLowerRangePercent_ = ((lowerRangePercent_ * 99)) / 100;

        vm.stopPrank();
    }

    function test_RevertIfCooldownLeft() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (uint256 upperRangePercent_, uint256 lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        // increase ranges by 1%
        int256 newUpperRangePercentage_ = 1e4; // 1% = 1e4

        // decrease ranges by 1%
        int256 newLowerRangePercentage_ = -1e4; // 1% = 1e4

        // set user withdraw limit
        fluidRangeAuthDex.setRangesByPercentage(
            DEX_WEETHS_ETH,
            newUpperRangePercentage_,
            newLowerRangePercentage_,
            2 days
        );

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.RangeAuthDex__CooldownLeft));

        // try updating again
        fluidRangeAuthDex.setRangesByPercentage(
            DEX_WEETHS_ETH,
            newUpperRangePercentage_,
            newLowerRangePercentage_,
            2 days
        );

        vm.stopPrank();
    }

    function test_RevertIfInvalidParamsPercentage() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (uint256 upperRangePercent_, uint256 lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        // increase ranges by 1%
        int256 newUpperRangePercentage_ = 31e4; // 1% = 1e4

        // decrease ranges by 1%
        int256 newLowerRangePercentage_ = -31e4; // 1% = 1e4

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        // set user withdraw limit
        fluidRangeAuthDex.setRangesByPercentage(
            DEX_WEETHS_ETH,
            newUpperRangePercentage_,
            newLowerRangePercentage_,
            2 days
        );

        vm.stopPrank();
    }

    function test_RevertIfInvalidParams() public {
        vm.startPrank(TEAM_MULTISIG_MAINNET);
        vm.deal(TEAM_MULTISIG_MAINNET, 1 ether);

        (uint256 upperRangePercent_, uint256 lowerRangePercent_) = fluidRangeAuthDex.getRanges(DEX_WEETHS_ETH);

        // increase ranges by 31% (> 30% max)
        uint256 newUpperRangePercent_ = ((upperRangePercent_ * 131)) / 100;
        uint256 newLowerRangePercent_ = ((lowerRangePercent_ * 131)) / 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange
            )
        );

        // set user withdraw limit
        fluidRangeAuthDex.setRanges(DEX_WEETHS_ETH, newUpperRangePercent_, newLowerRangePercent_, 2 days);

        vm.stopPrank();
    }

    function test_deployment_constants() public {
        assertEq(fluidRangeAuthDex.COOLDOWN(), 1 days);
        assertEq(fluidRangeAuthDex.MAX_PERCENT_RANGE_CHANGE_ALLOWED(), 30 * 1e4);
    }
}
