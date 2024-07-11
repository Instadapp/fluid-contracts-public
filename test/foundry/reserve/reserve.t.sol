//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { FluidLiquidityUserModule } from "../../../contracts/liquidity/userModule/main.sol";
import { FluidLiquidityAdminModule, AuthModule, GovernanceModule } from "../../../contracts/liquidity/adminModule/main.sol";
import { FluidLiquidityProxy } from "../../../contracts/liquidity/proxy.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { IFToken } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { FluidReserveContract } from "../../../contracts/reserve/main.sol";
import { FluidReserveContractProxy } from "../../../contracts/reserve/proxy.sol";
import { LiquidityCalcs } from "../../../contracts/libraries/liquidityCalcs.sol";
import { Events } from "../../../contracts/reserve/events.sol";
import { Error } from "../../../contracts/reserve/error.sol";
import { ErrorTypes } from "../../../contracts/reserve/errorTypes.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { FluidVaultT1 } from "../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultResolver } from "../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidVaultT1Admin } from "../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { MockOracle } from "../../../contracts/mocks/mockOracle.sol";

import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { VaultFactoryTest } from "../vaultT1/factory/vaultFactory.t.sol";
import "../testERC20.sol";
import "../bytesLib.sol";

abstract contract ReserveContractBaseTest is LiquidityBaseTest {
    FluidReserveContract reserveContractImpl;
    FluidReserveContract reserveContract; //proxy
    FluidLendingFactory factory;

    IFluidLiquidity liquidityProxy;

    address owner = address(0x123F);
    address rebalancer = address(0x678A);
    address authUser = address(0x987B);

    address[] auths;
    address[] rebalancers;

    function setUp() public virtual override {
        // native underlying tests must run in fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(18827888);

        super.setUp();

        auths = new address[](1);
        auths[0] = authUser;
        rebalancers = new address[](1);
        rebalancers[0] = owner;

        liquidityProxy = IFluidLiquidity(address(liquidity));
        reserveContractImpl = new FluidReserveContract(liquidityProxy);
        reserveContract = FluidReserveContract(
            payable(new FluidReserveContractProxy(address(reserveContractImpl), new bytes(0)))
        );
        reserveContract.initialize(auths, rebalancers, owner);
        // reserve contract proxy admin is 'admin'
        // reserve contract owner is 'owner'
        vm.prank(authUser);
        reserveContract.updateRebalancer(rebalancer, true);

        // fund Liquidity with ETH for lending out
        // Add supply config for MockProtocol
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: NATIVE_TOKEN_ADDRESS,
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT
        });
        vm.prank(admin);
        liquidityProxy.updateUserSupplyConfigs(userSupplyConfigs_);
    }
}

contract ReserveContractTestConstructor is ReserveContractBaseTest, Events {
    function test_constructor_RevertIfLiquidityAddressZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__AddressZero)
        );
        reserveContractImpl = new FluidReserveContract(IFluidLiquidity(address(0)));
    }

    function test_constructor() public {
        reserveContractImpl = new FluidReserveContract(liquidityProxy);
        reserveContract = FluidReserveContract(
            payable(new FluidReserveContractProxy(address(reserveContractImpl), new bytes(0)))
        );
        reserveContract.initialize(auths, rebalancers, owner);
        assertEq(address(reserveContractImpl.LIQUIDITY()), address(liquidityProxy));
        assertEq(address(reserveContract.LIQUIDITY()), address(liquidityProxy));
    }
}

contract ReserveContractTestInitializer is ReserveContractBaseTest, Events {
    function setUp() public virtual override {
        super.setUp();
        // reserve contract reset
        reserveContractImpl = new FluidReserveContract(liquidityProxy);
        reserveContract = FluidReserveContract(
            payable(new FluidReserveContractProxy(address(reserveContractImpl), new bytes(0)))
        );
    }

    function test_initialize_RevertIfInitializedSecondTime() public {
        reserveContract.initialize(auths, rebalancers, owner);
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        reserveContract.initialize(auths, rebalancers, owner);
    }

    function test_initialize_RevertIfOwnerAddressZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__AddressZero)
        );
        vm.prank(authUser);
        reserveContract.initialize(auths, rebalancers, address(0));
    }

    function test_initialize() public {
        vm.expectEmit(true, true, true, false);
        emit LogUpdateAuth(authUser, true);
        vm.expectEmit(true, true, true, false);
        emit LogUpdateRebalancer(owner, true);
        reserveContract.initialize(auths, rebalancers, owner);
        assertEq(address(reserveContract.LIQUIDITY()), address(liquidityProxy));
        assertEq(address(reserveContract.owner()), address(owner));
    }
}

contract ReserveContractTestOwnership is ReserveContractBaseTest {
    function test_renounceOwnership_RevertIfNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        reserveContract.renounceOwnership();
    }

    function test_renounceOwnership_RevertUnsupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidReserveContractError.selector,
                ErrorTypes.ReserveContract__RenounceOwnershipUnsupported
            )
        );
        vm.prank(owner);
        reserveContract.renounceOwnership();
    }
}

contract ReserveContractTestAdmin is ReserveContractBaseTest, Events {
    function test_updateAuth_RevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        reserveContract.updateAuth(address(alice), true);
    }

    function test_updateAuth_RevertIfAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__AddressZero)
        );
        reserveContract.updateAuth(address(0), true);
    }

    function test_updateAuth() public {
        bool isAuth = reserveContract.isAuth(address(bob));
        assertEq(isAuth, false);
        vm.expectEmit(true, true, true, false);
        emit LogUpdateAuth(address(bob), true);
        vm.prank(owner);
        reserveContract.updateAuth(address(bob), true);
        isAuth = reserveContract.isAuth(address(bob));
        assertEq(isAuth, true);
    }

    function test_updateRebalancer_RevertIfNotAuth() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__Unauthorized)
        );
        reserveContract.updateRebalancer(address(alice), true);
    }

    function test_updateRebalancer_RevertIfAddressZero() public {
        vm.prank(authUser);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__AddressZero)
        );
        reserveContract.updateRebalancer(address(0), true);
    }

    function test_updateRebalancer() public {
        bool isRebalancer = reserveContract.isRebalancer(address(bob));
        assertEq(isRebalancer, false);
        vm.expectEmit(true, true, true, false);
        emit LogUpdateRebalancer(address(bob), true);
        vm.prank(authUser);
        reserveContract.updateRebalancer(address(bob), true);
        isRebalancer = reserveContract.isRebalancer(address(bob));
        assertEq(isRebalancer, true);
    }

    function test_approve_RevertIfNotAuth() public {
        address[] memory protocols_ = new address[](2);
        address[] memory tokens_ = new address[](2);
        uint256[] memory amounts_ = new uint256[](2);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__Unauthorized)
        );
        reserveContract.approve(protocols_, tokens_, amounts_);
    }

    function test_approve_RevertIfProtocolsAndTokensAreNotTheSameLengths() public {
        address[] memory protocols_ = new address[](2);
        address[] memory tokens_ = new address[](3);
        uint256[] memory amounts_ = new uint256[](2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidReserveContractError.selector,
                ErrorTypes.ReserveContract__InvalidInputLenghts
            )
        );
        vm.prank(authUser);
        reserveContract.approve(protocols_, tokens_, amounts_);
    }

    function test_approve_RevertIfTokensAndAmountsAreNotTheSameLengths() public {
        address[] memory protocols_ = new address[](2);
        address[] memory tokens_ = new address[](2);
        uint256[] memory amounts_ = new uint256[](3);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidReserveContractError.selector,
                ErrorTypes.ReserveContract__InvalidInputLenghts
            )
        );
        vm.prank(authUser);
        reserveContract.approve(protocols_, tokens_, amounts_);
    }

    function test_approve() public {
        address[] memory protocols_ = new address[](3);
        protocols_[0] = address(1);
        protocols_[1] = address(1);
        protocols_[2] = address(2);
        address[] memory tokens_ = new address[](3);
        tokens_[0] = address(USDC);
        tokens_[1] = address(DAI);
        tokens_[2] = address(DAI);
        uint256[] memory amounts_ = new uint256[](3);
        amounts_[0] = 1000;
        amounts_[1] = 2000;
        amounts_[2] = 3000;

        vm.expectEmit(true, true, true, true);
        emit LogAllow(protocols_[0], tokens_[0], amounts_[0], 0);
        vm.expectEmit(true, true, true, true);
        emit LogAllow(protocols_[1], tokens_[1], amounts_[1], 0);
        vm.expectEmit(true, true, true, true);
        emit LogAllow(protocols_[2], tokens_[2], amounts_[2], 0);

        vm.prank(authUser);
        reserveContract.approve(protocols_, tokens_, amounts_);

        for (uint256 i = 0; i < protocols_.length; i++) {
            address protocol_ = protocols_[i];
            address token_ = tokens_[i];
            uint256 amount_ = amounts_[i];
            assertEq(IERC20(address(token_)).allowance(address(reserveContract), protocol_), amount_);
        }
        address[] memory protocolTokens = reserveContract.getProtocolTokens(address(1)); // should have two tokens USDC and DAI
        assertEq(protocolTokens.length, 2);
        assertEq(protocolTokens[0], address(USDC));
        assertEq(protocolTokens[1], address(DAI));

        protocolTokens = reserveContract.getProtocolTokens(address(2)); // should have two tokens USDC and DAI
        assertEq(protocolTokens.length, 1);
        assertEq(protocolTokens[0], address(DAI));
    }

    function test_revoke_RevertIfNotAuth() public {
        address[] memory protocols_ = new address[](2);
        address[] memory tokens_ = new address[](2);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__Unauthorized)
        );
        reserveContract.revoke(protocols_, tokens_);
    }

    function test_revoke_RevertIfProtocolsAndTokensAreNotTheSameLengths() public {
        address[] memory protocols_ = new address[](2);
        address[] memory tokens_ = new address[](3);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidReserveContractError.selector,
                ErrorTypes.ReserveContract__InvalidInputLenghts
            )
        );
        vm.prank(authUser);
        reserveContract.revoke(protocols_, tokens_);
    }

    function test_revoke() public {
        test_approve(); //approve protocols with USDC and DAI

        // revoke
        address[] memory protocols_ = new address[](1);
        protocols_[0] = address(1);
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(DAI);

        vm.expectEmit(true, true, false, false);
        emit LogRevoke(protocols_[0], tokens_[0]);

        vm.prank(authUser);
        reserveContract.revoke(protocols_, tokens_);

        address[] memory protocolTokens = reserveContract.getProtocolTokens(address(1));
        assertEq(protocolTokens.length, 1);
        assertEq(protocolTokens[0], address(USDC));

        assertEq(IERC20(address(USDC)).allowance(address(reserveContract), address(1)), 1000);
        assertEq(IERC20(address(DAI)).allowance(address(reserveContract), address(1)), 0);

        protocolTokens = reserveContract.getProtocolTokens(address(2));
        assertEq(protocolTokens.length, 1);
        assertEq(protocolTokens[0], address(DAI));

        assertEq(IERC20(address(USDC)).allowance(address(reserveContract), address(2)), 0);
        assertEq(IERC20(address(DAI)).allowance(address(reserveContract), address(2)), 3000);
    }
}

contract ReserveContractTestFTokenRebalance is ReserveContractTestAdmin {
    function test_rebalanceFToken_RevertIfNotRebalancer() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__Unauthorized)
        );
        reserveContract.rebalanceFToken(address(1), 0);
    }

    function test_rebalanceFToken() public {
        // create fToken
        factory = new FluidLendingFactory(liquidityProxy, admin);
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        vm.prank(admin);
        fToken lendingFToken = fToken(address(factory.createToken(address(USDC), "fToken", false)));

        // update rebalancer for fToken
        vm.prank(admin);
        factory.setAuth(address(alice), true);
        vm.prank(alice);
        lendingFToken.updateRebalancer(address(reserveContract));

        address[] memory protocols_ = new address[](1);
        protocols_[0] = address(lendingFToken);
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);
        uint256[] memory amounts_ = new uint256[](1);
        amounts_[0] = 1000;

        vm.prank(authUser);
        reserveContract.approve(protocols_, tokens_, amounts_);

        vm.prank(authUser);
        reserveContract.updateRebalancer(rebalancer, true);

        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(lendingFToken));

        vm.prank(alice);
        IERC20(address(USDC)).approve(address(lendingFToken), 1000);
        vm.prank(alice);
        lendingFToken.deposit(1000, alice);

        uint256 startTime_ = block.timestamp + 3153600;
        uint256 endTime_ = startTime_ + 365 days;

        FluidLendingRewardsRateModel rateModel = new FluidLendingRewardsRateModel(
            365 days,
            1,
            1 ether,
            alice,
            IFluidLendingRewardsRateModel(address(0))
        );
        vm.prank(alice);
        rateModel.start();

        vm.prank(admin);
        IFToken(address(lendingFToken)).updateRewards(FluidLendingRewardsRateModel(address(rateModel)));

        vm.prank(alice);
        USDC.mint(address(reserveContract), 500);
        vm.warp(block.timestamp + (PASS_1YEAR_TIME * 1) / 2);

        vm.expectEmit(true, true, true, false);
        emit LogRebalanceFToken(address(lendingFToken), 0);
        vm.prank(rebalancer);
        reserveContract.rebalanceFToken(address(lendingFToken), 0);
    }
}

struct VaultRebalance {
    uint liqSupplyExPrice;
    uint liqBorrowExPrice;
    uint vaultSupplyExPrice;
    uint vaultBorrowExPrice;
    uint supplyVault;
    uint supplyVaultAfter;
    uint supplyVaultAfterLiquidity;
    uint borrowVault;
    uint borrowVaultAfter;
    uint borrowVaultAfterLiquidity;
    uint expectedSupplyRebalanceAmt;
    uint expectedBorrowRebalanceAmt;
}

// TODO
// contract ReserveContractTestVaultRebalance is ReserveContractTestAdmin, VaultFactoryTest {
//     FluidVaultT1 vaultOne;
//     FluidVaultT1 vaultTwo;
//     MockERC20 supplyToken;
//     MockERC20 borrowToken;

//     MockOracle oracleOne;
//     MockOracle oracleTwo;

//     function setUp() public virtual override(ReserveContractBaseTest, VaultFactoryTest) {
//         ReserveContractBaseTest.setUp();
//         VaultFactoryTest.setUp();

//         supplyToken = MockERC20(address(USDC));
//         borrowToken = MockERC20(address(DAI));

//         supplyToken.mint(alice, 10e32);
//         borrowToken.mint(alice, 10e32);

//         vaultOne = FluidVaultT1(_deployVaultTokens(address(supplyToken), address(borrowToken)));
//         vaultTwo = FluidVaultT1(_deployVaultTokens(address(borrowToken), address(supplyToken)));

//         oracleOne = MockOracle(_setDefaultVaultSettings(address(vaultOne)));
//         oracleTwo = MockOracle(_setDefaultVaultSettings(address(vaultTwo)));

//         // set default allowances for vault
//         _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultOne));
//         _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultOne));
//         _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultTwo));
//         _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultTwo));

//         // set default allowances for mockProtocol
//         _setUserAllowancesDefault(address(liquidity), admin, address(supplyToken), address(mockProtocol));
//         _setUserAllowancesDefault(address(liquidity), admin, address(borrowToken), address(mockProtocol));

//         _supply(mockProtocol, address(supplyToken), alice, 10e6 * 1e6);
//         _supply(mockProtocol, address(borrowToken), alice, 10e6 * 1e18);
//         // _supplyNative(mockProtocol, alice, 1e3 * 1e18);

//         _setApproval(USDC, address(vaultOne), alice);
//         _setApproval(USDC, address(vaultTwo), alice);
//     }

//     function test_rebalanceVault_RevertIfNotRebalancer() public {
//         vm.prank(alice);
//         vm.expectRevert(
//             abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__Unauthorized)
//         );
//         reserveContract.rebalanceVault(address(vaultOne));
//     }

//     function test_rebalanceVault() public {
//         FluidVaultResolver.UserPosition memory userPosition_;
//         VaultRebalance memory rebalance_;

//         // creating position in both vaults to make sure supply & borrow rates are not 0

//         uint oracleOnePrice_ = 1e38; // * 1e18
//         _setOracleOnePrice(oracleOnePrice_);

//         vm.prank(alice);
//         vaultOne.operate(
//             0, // new position
//             10_000 * 1e6 * 2,
//             7_990 * 1e18 * 2,
//             alice
//         );

//         uint oracleTwoPrice_ = 1e15; // * 1e18
//         _setOracleTwoPrice(oracleTwoPrice_);

//         vm.prank(alice);
//         vaultTwo.operate(
//             0, // new position
//             10_000 * 1e6,
//             7_990 * 1e18,
//             alice
//         );

//         uint vaultOneNewMagnifier_ = 11000;
//         vm.prank(alice);
//         FluidVaultT1Admin(address(vaultOne)).updateSupplyRateMagnifier(vaultOneNewMagnifier_);
//         vm.prank(alice);
//         FluidVaultT1Admin(address(vaultOne)).updateBorrowRateMagnifier(vaultOneNewMagnifier_);

//         vm.warp(100000);

//         // ################ Vault One ################

//         (
//             rebalance_.liqSupplyExPrice,
//             rebalance_.liqBorrowExPrice,
//             rebalance_.vaultSupplyExPrice,
//             rebalance_.vaultBorrowExPrice
//         ) = vaultOne.updateExchangePricesOnStorage();

//         // last liquidity exchange price is same as EXCHANGE_PRICES_PRECISION
//         uint expectedSupplyExDifference_ = rebalance_.liqSupplyExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
//         expectedSupplyExDifference_ = (expectedSupplyExDifference_ * vaultOneNewMagnifier_) / 10000;

//         assertEq(
//             (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedSupplyExDifference_),
//             rebalance_.vaultSupplyExPrice
//         );

//         // last liquidity exchange price is same as EXCHANGE_PRICES_PRECISION
//         uint expectedBorrowExDifference_ = rebalance_.liqBorrowExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
//         expectedBorrowExDifference_ = (expectedBorrowExDifference_ * vaultOneNewMagnifier_) / 10000;

//         assertEq(
//             (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedBorrowExDifference_),
//             rebalance_.vaultBorrowExPrice
//         );

//         rebalance_.supplyVault = 10_000 * 1e6 * 2;
//         rebalance_.supplyVaultAfter =
//             (rebalance_.supplyVault * rebalance_.vaultSupplyExPrice) /
//             LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
//         rebalance_.supplyVaultAfterLiquidity =
//             (rebalance_.supplyVault * rebalance_.liqSupplyExPrice) /
//             LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
//         rebalance_.borrowVault = 7_990 * 1e18 * 2;
//         rebalance_.borrowVaultAfter =
//             (rebalance_.borrowVault * rebalance_.vaultBorrowExPrice) /
//             LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
//         rebalance_.borrowVaultAfterLiquidity =
//             (rebalance_.borrowVault * rebalance_.liqBorrowExPrice) /
//             LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

//         // Vault one will have deposit
//         rebalance_.expectedSupplyRebalanceAmt = rebalance_.supplyVaultAfter - rebalance_.supplyVaultAfterLiquidity;
//         // Vault one will have borrow
//         rebalance_.expectedBorrowRebalanceAmt = rebalance_.borrowVaultAfter - rebalance_.borrowVaultAfterLiquidity;
//         // vm.expectEmit(true, false, false, false);
//         // emit Events.LogRebalanceFToken(address(lendingFToken), 0);
//         // vm.prank(rebalancer);
//         // reserveContract.rebalanceVault(address(lendingFToken));
//         vm.prank(alice);
//         (int supplyRebalanceAmt_, int borrowRebalanceAmt_) = vaultOne.rebalance();

//         // 1e18 = 100%
//         assertApproxEqRel(rebalance_.expectedSupplyRebalanceAmt, uint(supplyRebalanceAmt_), 1e4);
//         assertApproxEqRel(rebalance_.expectedBorrowRebalanceAmt, uint(borrowRebalanceAmt_), 1e4);
//     }

//     function _deployVaultTokens(address supplyToken_, address borrowToken_) internal returns (address vault_) {
//         vm.prank(alice);

//         bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (supplyToken_, borrowToken_));
//         vault_ = address(FluidVaultT1(vaultFactory.deployVault(address(vaultT1Deployer), vaultT1CreationCode)));
//     }

//     function _setDefaultVaultSettings(address vault_) internal returns (address oracle_) {
//         FluidVaultT1Admin vaultAdmin_ = FluidVaultT1Admin(vault_);
//         vm.prank(alice);
//         vaultAdmin_.updateCoreSettings(
//             10000, // supplyFactor_ => 100%
//             10000, // borrowFactor_ => 100%
//             8000, // collateralFactor_ => 80%
//             8100, // liquidationThreshold_ => 81%
//             9000, // liquidationMaxLimit_ => 90%
//             500, // withdrawGap_ => 5%
//             0, // liquidationPenalty_ => 0%
//             0 // borrowFee_ => 0.01%
//         );

//         oracle_ = address(new MockOracle());
//         vm.prank(alice);
//         vaultAdmin_.updateOracle(address(oracle_));

//         vm.prank(alice);
//         vaultAdmin_.updateRebalancer(address(alice));
//     }

//     function _setOracleOnePrice(uint price) internal {
//         oracleOne.setPrice(price);
//     }

//     function _setOracleTwoPrice(uint price) internal {
//         oracleTwo.setPrice(price);
//     }
// }

contract ReserveContractTestTransferFunds is ReserveContractBaseTest, Events {
    function test_transferFunds_RevertIfNoAuth() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidReserveContractError.selector, ErrorTypes.ReserveContract__Unauthorized)
        );
        address[] memory tokens_ = new address[](1);
        reserveContract.transferFunds(tokens_);
    }

    function test_transferFunds_AuthUser() public {
        MockERC20 mockTokenOne = new MockERC20("Mock Token", "TKN", 18);
        MockERC20 mockTokenTwo = new MockERC20("Another Mock Token", "ATKN", 18);
        mockTokenOne.mint(address(reserveContract), 1000);
        mockTokenTwo.mint(address(reserveContract), 2000);

        vm.expectEmit(true, true, false, false);
        emit LogTransferFunds(address(mockTokenOne));
        vm.expectEmit(true, true, false, false);
        emit LogTransferFunds(address(mockTokenTwo));
        address[] memory tokens_ = new address[](2);
        tokens_[0] = address(mockTokenOne);
        tokens_[1] = address(mockTokenTwo);

        vm.prank(authUser);
        reserveContract.transferFunds(tokens_);
        assertEq(mockTokenOne.balanceOf(address(liquidityProxy)), 1000);
        assertEq(mockTokenTwo.balanceOf(address(liquidityProxy)), 2000);
    }

    function test_transferFunds_Owner() public {
        MockERC20 mockTokenOne = new MockERC20("Mock Token", "TKN", 18);
        MockERC20 mockTokenTwo = new MockERC20("Another Mock Token", "ATKN", 18);
        mockTokenOne.mint(address(reserveContract), 1000);
        mockTokenTwo.mint(address(reserveContract), 2000);

        vm.expectEmit(true, true, false, false);
        emit LogTransferFunds(address(mockTokenOne));
        vm.expectEmit(true, true, false, false);
        emit LogTransferFunds(address(mockTokenTwo));

        address[] memory tokens_ = new address[](2);
        tokens_[0] = address(mockTokenOne);
        tokens_[1] = address(mockTokenTwo);

        vm.prank(owner);
        reserveContract.transferFunds(tokens_);
        assertEq(mockTokenOne.balanceOf(address(liquidityProxy)), 1000);
        assertEq(mockTokenTwo.balanceOf(address(liquidityProxy)), 2000);
    }
}

contract ReserveContractTestUpgradable is ReserveContractBaseTest {
    function test_upgradeTo_RevertIfNotOwner() public {
        FluidReserveContract reserveContractImplV2 = new FluidReserveContract(liquidityProxy);
        vm.prank(alice);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        reserveContract.upgradeTo(address(reserveContractImplV2));
    }

    function test_upgradeTo() public {
        FluidReserveContract reserveContractImplV2 = new FluidReserveContract(liquidityProxy);
        vm.prank(owner);
        reserveContract.upgradeTo(address(reserveContractImplV2));
    }
}
