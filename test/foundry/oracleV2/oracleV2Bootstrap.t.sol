// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsdOracle } from "../../../contracts/oracleV2/usdOracle/main.sol";
import { FluidUsdOracleBootstrap } from "../../../contracts/oracleV2/usdOracle/bootstrap/main.sol";
import { FluidUsdOracleProxy } from "../../../contracts/oracleV2/usdOracle/proxy.sol";
import { Error } from "../../../contracts/oracleV2/usdOracle/error.sol";
import { ErrorTypes as UsdOracleErrorTypes } from "../../../contracts/oracleV2/usdOracle/errorTypes.sol";
import { MemoryStructs } from "../../../contracts/oracleV2/usdOracle/structs.sol";
import { ViewStructs } from "../../../contracts/oracleV2/usdOracle/structs.sol";

contract MockLiquidityGovernanceStorage {
    mapping(bytes32 => uint256) public storageValues;

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        return storageValues[slot_];
    }

    function setStorage(bytes32 slot_, uint256 value_) external {
        storageValues[slot_] = value_;
    }
}

/// @dev USD oracle bootstrap: admin acts as governance; Team MS / gov / bootstrap can upgrade to final; final strips privilege.
contract FluidOracleV2BootstrapTest is Test {
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address internal constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    MockLiquidityGovernanceStorage internal liquidityMock;
    address internal governance;
    address internal bootstrapAdmin;
    address internal randomCaller;

    function setUp() public {
        liquidityMock = new MockLiquidityGovernanceStorage();
        governance = makeAddr("governance");
        bootstrapAdmin = makeAddr("bootstrapAdmin");
        randomCaller = makeAddr("random");
        liquidityMock.setStorage(LIQUIDITY_GOVERNANCE_SLOT, uint256(uint160(governance)));
    }

    function test_usdOracleBootstrap_adminCanSetTokenType_randomCannot() public {
        FluidUsdOracleBootstrap bootImpl_ = new FluidUsdOracleBootstrap(address(liquidityMock), bootstrapAdmin);
        FluidUsdOracle proxied_ = FluidUsdOracle(address(new FluidUsdOracleProxy(address(bootImpl_), "")));

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        vm.prank(randomCaller);
        proxied_.setTokenType(NATIVE, 3);

        vm.prank(bootstrapAdmin);
        proxied_.setTokenType(NATIVE, 3);

        (, , uint8 tokenType_, ) = proxied_.getTokenConfig(NATIVE);
        assertEq(tokenType_, 3);
    }

    function test_usdOracleBootstrap_teamMultisigAndAdminCanUpgradeToFinal_thenAdminLosesPrivilege() public {
        FluidUsdOracleBootstrap bootImpl_ = new FluidUsdOracleBootstrap(address(liquidityMock), bootstrapAdmin);
        FluidUsdOracleProxy proxy_ = new FluidUsdOracleProxy(address(bootImpl_), "");
        FluidUsdOracle proxied_ = FluidUsdOracle(address(proxy_));

        vm.prank(bootstrapAdmin);
        proxied_.setTokenType(NATIVE, 3);

        FluidUsdOracle finalImpl_ = new FluidUsdOracle(address(liquidityMock));

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        vm.prank(randomCaller);
        // use upgradeTo (not upgradeToAndCall): OZ forceCall+empty data needs receive(); prod finals have none
        proxied_.upgradeTo(address(finalImpl_));

        // Team MS can finalize
        vm.prank(TEAM_MULTISIG);
        proxied_.upgradeTo(address(finalImpl_));

        // Config survives
        (, , uint8 tokenType_, ) = proxied_.getTokenConfig(NATIVE);
        assertEq(tokenType_, 3);

        // Bootstrap admin no longer has governance powers on final impl
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        vm.prank(bootstrapAdmin);
        proxied_.setTokenType(NATIVE, 2); // STABLE

        // Real governance still can
        vm.prank(governance);
        proxied_.setTokenType(NATIVE, 2);
    }

    function test_usdOracleBootstrap_adminCanUpgradeToFinal() public {
        FluidUsdOracleBootstrap bootImpl_ = new FluidUsdOracleBootstrap(address(liquidityMock), bootstrapAdmin);
        FluidUsdOracle proxied_ = FluidUsdOracle(address(new FluidUsdOracleProxy(address(bootImpl_), "")));
        FluidUsdOracle finalImpl_ = new FluidUsdOracle(address(liquidityMock));

        vm.prank(bootstrapAdmin);
        proxied_.upgradeTo(address(finalImpl_));
    }

    /// @dev STABLE + PEG priceMode = flat $1; no source config needed. Multicall must keep msg.sender = admin
    ///      across registerTransientOracleKey + setPriceMode (transient storage).
    function test_usdOracleBootstrap_adminMulticall_wiresTokenAndKeyInOneTx() public {
        FluidUsdOracleBootstrap bootImpl_ = new FluidUsdOracleBootstrap(address(liquidityMock), bootstrapAdmin);
        FluidUsdOracleBootstrap proxied_ = FluidUsdOracleBootstrap(
            address(new FluidUsdOracleProxy(address(bootImpl_), ""))
        );

        bytes[] memory data_ = new bytes[](3);
        data_[0] = abi.encodeWithSignature("setTokenType(address,uint8)", NATIVE, uint8(2)); // STABLE
        data_[1] = abi.encodeWithSignature(
            "registerTransientOracleKey((address,uint256,uint8,uint8))",
            MemoryStructs.OracleKey({ token: NATIVE, eMode: 0, isOperate: 1, isCollateral: 1 })
        );
        data_[2] = abi.encodeWithSignature("setPriceMode(uint8)", uint8(2)); // PEG / flat $1

        vm.prank(bootstrapAdmin);
        proxied_.multicall(data_);

        (, , uint8 tokenType_, ) = FluidUsdOracle(address(proxied_)).getTokenConfig(NATIVE);
        assertEq(tokenType_, 2);

        ViewStructs.ConfiguredTokenOracle[] memory infos_ = FluidUsdOracle(address(proxied_)).getConfiguredTokenOracles(
            NATIVE
        );
        assertEq(infos_.length, 1);
        assertEq(infos_[0].priceMode, 2);
        assertTrue(infos_[0].isOperate);
        assertTrue(infos_[0].isCollateral);
    }

    function test_usdOracleBootstrap_multicall_randomCannot() public {
        FluidUsdOracleBootstrap bootImpl_ = new FluidUsdOracleBootstrap(address(liquidityMock), bootstrapAdmin);
        FluidUsdOracleBootstrap proxied_ = FluidUsdOracleBootstrap(
            address(new FluidUsdOracleProxy(address(bootImpl_), ""))
        );

        bytes[] memory data_ = new bytes[](1);
        data_[0] = abi.encodeWithSignature("setTokenType(address,uint8)", NATIVE, uint8(3));

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        vm.prank(randomCaller);
        proxied_.multicall(data_);
    }

    function test_usdOracleBootstrap_multicallGoneAfterUpgradeToFinal() public {
        FluidUsdOracleBootstrap bootImpl_ = new FluidUsdOracleBootstrap(address(liquidityMock), bootstrapAdmin);
        FluidUsdOracleProxy proxy_ = new FluidUsdOracleProxy(address(bootImpl_), "");
        FluidUsdOracleBootstrap bootProxied_ = FluidUsdOracleBootstrap(address(proxy_));

        FluidUsdOracle finalImpl_ = new FluidUsdOracle(address(liquidityMock));
        vm.prank(bootstrapAdmin);
        FluidUsdOracle(address(proxy_)).upgradeTo(address(finalImpl_));

        bytes[] memory data_ = new bytes[](1);
        data_[0] = abi.encodeWithSignature("setTokenType(address,uint8)", NATIVE, uint8(3));

        // Final impl has no multicall — call hits fallback / empty code path and reverts
        vm.expectRevert();
        vm.prank(bootstrapAdmin);
        bootProxied_.multicall(data_);
    }

    function test_usdOracle_onlyGovernance_allowsWhenTeamMultisigIsGovernance() public {
        liquidityMock.setStorage(LIQUIDITY_GOVERNANCE_SLOT, uint256(uint160(TEAM_MULTISIG)));
        FluidUsdOracle proxied_ = FluidUsdOracle(
            address(new FluidUsdOracleProxy(address(new FluidUsdOracle(address(liquidityMock))), ""))
        );

        address guardian_ = makeAddr("guardian");
        vm.prank(TEAM_MULTISIG);
        proxied_.setGuardian(guardian_, true);

        vm.prank(TEAM_MULTISIG);
        proxied_.setTokenType(NATIVE, 3);
        vm.prank(TEAM_MULTISIG);
        proxied_.setTokenType(NATIVE, 2);
        (, , uint8 tokenType_, ) = proxied_.getTokenConfig(NATIVE);
        assertEq(tokenType_, 2);
    }

    function test_usdOracleBootstrap_onlyGovernance_allowsWhenBootstrapAdminIsTeamMultisig() public {
        FluidUsdOracle proxied_ = FluidUsdOracle(
            address(
                new FluidUsdOracleProxy(address(new FluidUsdOracleBootstrap(address(liquidityMock), TEAM_MULTISIG)), "")
            )
        );

        address guardian_ = makeAddr("guardian");
        vm.prank(TEAM_MULTISIG);
        proxied_.setGuardian(guardian_, true);
    }
}
