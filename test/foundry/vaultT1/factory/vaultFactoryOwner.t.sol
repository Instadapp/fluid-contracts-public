//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFluidVault } from "../../../../contracts/protocols/vault/interfaces/iVault.sol";
import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { IFluidOracle } from "../../../../contracts/oracleV2/interfaces/iFluidOracle.sol";
import { VaultFactoryBaseTest } from "./vaultFactory.t.sol";

import { TickMath } from "../../../../contracts/libraries/tickMath.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";

import { VaultFactoryOwner, VaultFactoryOwnerCore, VaultFactoryOwnerTransfer, IFluidVaultFactory_OwnerWrapper, ILiquidity_OwnerWrapper, Events } from "../../../../contracts/protocols/vault/factory/ownerWrapper.sol";
import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

/// @dev Base test that deploys the full stack: liquidity, factory, vault, and VaultFactoryOwner as factory owner.
abstract contract VaultFactoryOwnerBaseTest is VaultFactoryBaseTest {
    event LogSetVaultIdAllowlisted(uint256 indexed vaultId, bool indexed allowed);
    event LogSetTransferDustPosAuth(address indexed auth, bool indexed allowed);
    event LogTransferPosition(uint256 indexed tokenId, address indexed from, uint256 indexed vaultId);
    event LogTransferDustPosition(uint256 indexed tokenId, address indexed from, uint256 indexed vaultId);
    event LogTransferFactoryOwnership(address indexed newOwner);

    VaultFactoryOwner ownerWrapper;

    // vault with USDC supply / DAI borrow (used for transferPosition tests, debt always above threshold)
    FluidVaultT1 vault;
    MockOracle oracle;
    uint256 vaultId;

    // vault with DAI supply / USDC borrow (6-dec borrow, used for transferDustPosition tests)
    FluidVaultT1 dustVault;
    MockOracle dustOracle;
    uint256 dustVaultId;

    address governance; // = admin (liquidity proxy admin)
    address team;
    address dustAuth = makeAddr("dustAuth");
    address unauthorized = makeAddr("unauthorized");

    function setUp() public virtual override {
        super.setUp();

        governance = admin;
        team = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

        // deploy VaultFactoryOwner
        uint256[] memory vaultIds_ = new uint256[](0);
        address[] memory dustPosAuths_ = new address[](1);
        dustPosAuths_[0] = dustAuth;
        ownerWrapper = new VaultFactoryOwner(
            IFluidVaultFactory_OwnerWrapper(address(vaultFactory)),
            ILiquidity_OwnerWrapper(address(liquidity)),
            vaultIds_,
            dustPosAuths_
        );

        // transfer factory ownership to the wrapper
        vm.prank(admin);
        vaultFactory.transferOwnership(address(ownerWrapper));
        assertEq(vaultFactory.owner(), address(ownerWrapper));

        vm.prank(governance);
        ownerWrapper.setDeployer(alice, true);
        vm.prank(governance);
        ownerWrapper.setVaultDeploymentLogic(address(vaultT1Deployer), true);
        vm.prank(governance);
        ownerWrapper.setGlobalAuth(alice, true);

        // --- Vault 1: USDC supply / DAI borrow (for transferPosition tests) ---
        {
            vm.prank(alice);
            bytes memory code = abi.encodeCall(vaultT1Deployer.vaultT1, (address(USDC), address(DAI)));
            address vaultAddr = vaultFactory.deployVault(address(vaultT1Deployer), code);
            vault = FluidVaultT1(vaultAddr);
            vaultId = vault.VAULT_ID();

            oracle = new MockOracle();
            vm.prank(alice);
            FluidVaultT1Admin(vaultAddr).updateCoreSettings(10000, 10000, 8000, 8100, 9000, 500, 0, 0);
            vm.prank(alice);
            FluidVaultT1Admin(vaultAddr).updateOracle(address(oracle));
            vm.prank(alice);
            FluidVaultT1Admin(vaultAddr).updateRebalancer(alice);
            // 1 USDC col = 1 DAI debt => price = 1e18 * 1e27 / 1e6 = 1e39
            oracle.setPrice(1e39);

            _setUserAllowancesDefault(address(liquidity), admin, address(USDC), vaultAddr);
            _setUserAllowancesDefault(address(liquidity), admin, address(DAI), vaultAddr);
        }

        // --- Vault 2: DAI supply / USDC borrow (6-dec borrow, for dust tests) ---
        {
            vm.prank(alice);
            bytes memory code = abi.encodeCall(vaultT1Deployer.vaultT1, (address(DAI), address(USDC)));
            address dustVaultAddr = vaultFactory.deployVault(address(vaultT1Deployer), code);
            dustVault = FluidVaultT1(dustVaultAddr);
            dustVaultId = dustVault.VAULT_ID();

            dustOracle = new MockOracle();
            vm.prank(alice);
            FluidVaultT1Admin(dustVaultAddr).updateCoreSettings(10000, 10000, 8000, 8100, 9000, 500, 0, 0);
            vm.prank(alice);
            FluidVaultT1Admin(dustVaultAddr).updateOracle(address(dustOracle));
            vm.prank(alice);
            FluidVaultT1Admin(dustVaultAddr).updateRebalancer(alice);
            // 1 DAI col = 1 USDC debt => price = 1e6 * 1e27 / 1e18 = 1e15
            dustOracle.setPrice(1e15);

            _setUserAllowancesDefault(address(liquidity), admin, address(DAI), dustVaultAddr);
            _setUserAllowancesDefault(address(liquidity), admin, address(USDC), dustVaultAddr);
        }

        // supply liquidity
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(mockProtocol));
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 1e6 * 1e6);
        _supply(address(liquidity), mockProtocol, address(DAI), alice, 1e6 * 1e18);

        // approvals for users
        _setApproval(IERC20(address(USDC)), address(vault), alice);
        _setApproval(IERC20(address(DAI)), address(vault), alice);
        _setApproval(IERC20(address(DAI)), address(dustVault), alice);
        _setApproval(IERC20(address(USDC)), address(dustVault), alice);
        _setApproval(IERC20(address(USDC)), address(vault), bob);
        _setApproval(IERC20(address(DAI)), address(vault), bob);
        _setApproval(IERC20(address(DAI)), address(dustVault), bob);
        _setApproval(IERC20(address(USDC)), address(dustVault), bob);

        vm.stopPrank();

        vm.label(address(ownerWrapper), "VaultFactoryOwner");
        vm.label(address(vault), "Vault");
        vm.label(address(dustVault), "DustVault");
        vm.label(team, "TeamMultisig");
        vm.label(dustAuth, "DustAuth");
        vm.label(unauthorized, "Unauthorized");
    }

    function _createPosition(address user_, int256 col_, int256 debt_) internal returns (uint256 nftId_) {
        vm.prank(user_);
        (nftId_, , ) = vault.operate(0, col_, debt_, user_);
    }

    /// @dev Creates a position on the dustVault (DAI supply / USDC borrow).
    function _createDustPosition(address user_, int256 col_, int256 debt_) internal returns (uint256 nftId_) {
        vm.prank(user_);
        (nftId_, , ) = dustVault.operate(0, col_, debt_, user_);
    }
}

// ============ Constructor & Constants ============

contract VaultFactoryOwnerConstructorTest is VaultFactoryOwnerBaseTest {
    function test_constructor_setsImmutables() public view {
        assertEq(address(ownerWrapper.FACTORY()), address(vaultFactory));
        assertEq(address(ownerWrapper.LIQUIDITY()), address(liquidity));
    }

    function test_constructor_setsDustPosAuths() public view {
        assertTrue(ownerWrapper.transferDustPosAuths(dustAuth));
        assertFalse(ownerWrapper.transferDustPosAuths(unauthorized));
    }

    function test_constructor_teamMultisigConstant() public view {
        assertEq(ownerWrapper.TEAM_MULTISIG(), 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e);
    }

    function test_governanceResolution() public {
        // governance = liquidity proxy admin = admin
        // the proxy was deployed with admin as the admin, so admin can exercise governance-only paths
        assertEq(vaultFactory.owner(), address(ownerWrapper));

        address newDeployer = makeAddr("newDeployer");
        vm.prank(governance);
        ownerWrapper.setDeployer(newDeployer, true);
        assertTrue(vaultFactory.isDeployer(newDeployer));
    }

    function test_constructor_revertsForZeroFactory() public {
        uint256[] memory vaultIds_ = new uint256[](0);
        address[] memory dustPosAuths_ = new address[](0);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__ZeroAddress)
        );
        new VaultFactoryOwner(
            IFluidVaultFactory_OwnerWrapper(address(0)),
            ILiquidity_OwnerWrapper(address(liquidity)),
            vaultIds_,
            dustPosAuths_
        );
    }

    function test_constructor_revertsForZeroLiquidity() public {
        uint256[] memory vaultIds_ = new uint256[](0);
        address[] memory dustPosAuths_ = new address[](0);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__ZeroAddress)
        );
        new VaultFactoryOwner(
            IFluidVaultFactory_OwnerWrapper(address(vaultFactory)),
            ILiquidity_OwnerWrapper(address(0)),
            vaultIds_,
            dustPosAuths_
        );
    }

    function test_constructor_revertsForZeroDustPosAuth() public {
        uint256[] memory vaultIds_ = new uint256[](0);
        address[] memory dustPosAuths_ = new address[](1);
        dustPosAuths_[0] = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__ZeroAddress)
        );
        new VaultFactoryOwner(
            IFluidVaultFactory_OwnerWrapper(address(vaultFactory)),
            ILiquidity_OwnerWrapper(address(liquidity)),
            vaultIds_,
            dustPosAuths_
        );
    }

    function test_constructor_revertsForInvalidInitialVaultId() public {
        uint256[] memory vaultIds_ = new uint256[](1);
        vaultIds_[0] = type(uint256).max;
        address[] memory dustPosAuths_ = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__InvalidVault)
        );
        new VaultFactoryOwner(
            IFluidVaultFactory_OwnerWrapper(address(vaultFactory)),
            ILiquidity_OwnerWrapper(address(liquidity)),
            vaultIds_,
            dustPosAuths_
        );
    }
}

// ============ Access Control ============

contract VaultFactoryOwnerAccessControlTest is VaultFactoryOwnerBaseTest {
    // --- onlyGovernance ---

    function test_setDeployer_revertsForNonGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.setDeployer(bob, true);
    }

    function test_setDeployer_revertsForTeam() public {
        vm.prank(team);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.setDeployer(bob, true);
    }

    function test_setGlobalAuth_revertsForNonGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.setGlobalAuth(bob, true);
    }

    function test_setVaultAuth_revertsForNonGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.setVaultAuth(address(vault), bob, true);
    }

    function test_setVaultDeploymentLogic_revertsForNonGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.setVaultDeploymentLogic(bob, true);
    }

    function test_spell_revertsForNonGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.spell(address(0), "");
    }

    function test_transferFactoryOwnership_revertsForNonGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.transferFactoryOwnership(bob);
    }

    function test_setVaultIdAllowlisted_revertsForNonGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);
    }

    function test_setTransferDustPosAuth_revertsForNonTeamOrGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.setTransferDustPosAuth(bob, true);
    }

    // --- onlyTeamOrGovernance ---

    function test_transferPosition_revertsForNonTeamOrGovernance() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.transferPosition(nftId);
    }

    function test_transferPosition_revertsForDustAuth() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);
        vm.prank(dustAuth);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.transferPosition(nftId);
    }

    // --- onlyDustPosAuthOrTeamOrGovernance ---

    function test_transferDustPosition_revertsForNonAuthorized() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.transferDustPosition(nftId);
    }
}

// ============ Factory Passthroughs ============

contract VaultFactoryOwnerPassthroughTest is VaultFactoryOwnerBaseTest {
    function test_setDeployer() public {
        assertFalse(vaultFactory.isDeployer(bob));
        vm.prank(governance);
        ownerWrapper.setDeployer(bob, true);
        assertTrue(vaultFactory.isDeployer(bob));

        vm.prank(governance);
        ownerWrapper.setDeployer(bob, false);
        assertFalse(vaultFactory.isDeployer(bob));
    }

    function test_setGlobalAuth() public {
        vm.prank(governance);
        ownerWrapper.setGlobalAuth(bob, true);
        assertTrue(vaultFactory.isGlobalAuth(bob));

        vm.prank(governance);
        ownerWrapper.setGlobalAuth(bob, false);
        assertFalse(vaultFactory.isGlobalAuth(bob));
    }

    function test_setVaultAuth() public {
        vm.prank(governance);
        ownerWrapper.setVaultAuth(address(vault), bob, true);
        assertTrue(vaultFactory.isVaultAuth(address(vault), bob));

        vm.prank(governance);
        ownerWrapper.setVaultAuth(address(vault), bob, false);
        assertFalse(vaultFactory.isVaultAuth(address(vault), bob));
    }

    function test_setVaultDeploymentLogic() public {
        address newLogic = makeAddr("newLogic");
        vm.prank(governance);
        ownerWrapper.setVaultDeploymentLogic(newLogic, true);
        assertTrue(vaultFactory.isVaultDeploymentLogic(newLogic));
    }

    function test_transferFactoryOwnership() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(governance);
        ownerWrapper.transferFactoryOwnership(newOwner);
        assertEq(vaultFactory.owner(), newOwner);
    }

    function test_transferFactoryOwnership_revertsForZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__ZeroAddress)
        );
        ownerWrapper.transferFactoryOwnership(address(0));
    }

    function test_transferFactoryOwnership_emitsEvent() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(governance);
        vm.expectEmit(true, false, false, false);
        emit LogTransferFactoryOwnership(newOwner);
        ownerWrapper.transferFactoryOwnership(newOwner);
    }
}

// ============ spellApprove ============

contract VaultFactoryOwnerSpellApproveTest is VaultFactoryOwnerBaseTest {
    function test_spellApprove_revertsOnDirectCall() public {
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__NotFactoryContext)
        );
        ownerWrapper.spellApprove(1, alice);
    }

    function test_spellApprove_revertsFromRandomAddress() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__NotFactoryContext)
        );
        ownerWrapper.spellApprove(1, alice);
    }

    function test_spellApprove_worksViaDelegatecallFromFactory() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        // Verify no approval exists
        assertEq(vaultFactory.getApproved(nftId), address(0));

        // spell delegatecalls spellApprove on factory context
        vm.prank(governance);
        ownerWrapper.spell(
            address(ownerWrapper),
            abi.encodeWithSelector(ownerWrapper.spellApprove.selector, nftId, address(ownerWrapper))
        );

        // Approval should now be set
        assertEq(vaultFactory.getApproved(nftId), address(ownerWrapper));
    }
}

// ============ Governance Config ============

contract VaultFactoryOwnerConfigTest is VaultFactoryOwnerBaseTest {
    function test_setVaultIdAllowlisted() public {
        assertFalse(ownerWrapper.vaultIdAllowlisted(vaultId));

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);
        assertTrue(ownerWrapper.vaultIdAllowlisted(vaultId));

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, false);
        assertFalse(ownerWrapper.vaultIdAllowlisted(vaultId));
    }

    function test_setVaultIdAllowlisted_revertsForInvalidVaultId() public {
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__InvalidVault)
        );
        ownerWrapper.setVaultIdAllowlisted(type(uint256).max, true);
    }

    function test_setTransferDustPosAuth() public {
        address newAuth = makeAddr("newAuth");
        assertFalse(ownerWrapper.transferDustPosAuths(newAuth));

        vm.prank(governance);
        ownerWrapper.setTransferDustPosAuth(newAuth, true);
        assertTrue(ownerWrapper.transferDustPosAuths(newAuth));

        vm.prank(governance);
        ownerWrapper.setTransferDustPosAuth(newAuth, false);
        assertFalse(ownerWrapper.transferDustPosAuths(newAuth));
    }

    function test_setTransferDustPosAuth_byTeam() public {
        address newAuth = makeAddr("newAuth");
        assertFalse(ownerWrapper.transferDustPosAuths(newAuth));

        vm.prank(team);
        ownerWrapper.setTransferDustPosAuth(newAuth, true);
        assertTrue(ownerWrapper.transferDustPosAuths(newAuth));

        vm.prank(team);
        ownerWrapper.setTransferDustPosAuth(newAuth, false);
        assertFalse(ownerWrapper.transferDustPosAuths(newAuth));
    }

    function test_setTransferDustPosAuth_revertsForZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__ZeroAddress)
        );
        ownerWrapper.setTransferDustPosAuth(address(0), true);
    }

    function test_setVaultIdAllowlisted_emitsEvent() public {
        vm.prank(governance);
        vm.expectEmit(true, true, false, false);
        emit LogSetVaultIdAllowlisted(vaultId, true);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);
    }

    function test_setTransferDustPosAuth_emitsEvent() public {
        address newAuth = makeAddr("newAuth");
        vm.prank(governance);
        vm.expectEmit(true, true, false, false);
        emit LogSetTransferDustPosAuth(newAuth, true);
        ownerWrapper.setTransferDustPosAuth(newAuth, true);
    }
}

// ============ transferPosition ============

contract VaultFactoryOwnerTransferPositionTest is VaultFactoryOwnerBaseTest {
    function test_transferPosition_revertsIfNotAllowlisted() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        vm.prank(team);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__VaultNotAllowlisted)
        );
        ownerWrapper.transferPosition(nftId);
    }

    function test_transferPosition_byTeam() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);

        assertEq(vaultFactory.ownerOf(nftId), alice);

        vm.prank(team);
        ownerWrapper.transferPosition(nftId);

        assertEq(vaultFactory.ownerOf(nftId), team);
    }

    function test_transferPosition_byGovernance() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);

        vm.prank(governance);
        ownerWrapper.transferPosition(nftId);

        assertEq(vaultFactory.ownerOf(nftId), team);
    }

    function test_transferPosition_emitsEvent() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);

        vm.prank(team);
        vm.expectEmit(true, true, true, false);
        emit LogTransferPosition(nftId, alice, vaultId);
        ownerWrapper.transferPosition(nftId);
    }

    function test_transferPosition_clearApprovalAfterTransfer() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);

        vm.prank(team);
        ownerWrapper.transferPosition(nftId);

        // approval should be cleared atomically by transferFrom
        assertEq(vaultFactory.getApproved(nftId), address(0));
    }

    function test_transferPosition_revertsForInvalidPosition() public {
        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);

        vm.prank(team);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__InvalidPosition)
        );
        ownerWrapper.transferPosition(type(uint256).max);
    }
}

// ============ transferDustPosition ============

contract VaultFactoryOwnerTransferDustPositionTest is VaultFactoryOwnerBaseTest {
    // dustVault: DAI (18 dec) supply / USDC (6 dec) borrow
    // DEBT_THRESHOLD = 1e5 = 0.1 USDC
    // oracle price: 1e15 (1 DAI col = 1 USDC debt in 1e27 precision)

    function test_transferDustPosition_revertsIfDebtAboveThreshold() public {
        // 1 DAI col, 0.79 USDC debt = 79e4 > 1e5
        uint256 nftId = _createDustPosition(alice, 1 * 1e18, 79e4);

        vm.prank(dustAuth);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__DebtAboveThreshold)
        );
        ownerWrapper.transferDustPosition(nftId);
    }

    function test_transferDustPosition_revertsIfSupplyOnly() public {
        vm.prank(alice);
        (uint256 nftId, , ) = dustVault.operate(0, 1 * 1e18, 0, alice);

        vm.prank(dustAuth);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__PositionTooSafe)
        );
        ownerWrapper.transferDustPosition(nftId);
    }

    function test_transferDustPosition_revertsIfPositionTooSafe() public {
        // 1 DAI col, 0.01 USDC debt = 1e4 < threshold, ratio = 1% -> too safe
        uint256 nftId = _createDustPosition(alice, 1 * 1e18, 1e4);

        vm.prank(dustAuth);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__PositionTooSafe)
        );
        ownerWrapper.transferDustPosition(nftId);
    }

    function test_transferDustPosition_successWhenDustAndRisky() public {
        // 0.1 DAI col, 0.079 USDC debt = 79000 < 1e5 threshold
        // ratio = 0.079 / 0.1 = 79% -> risky (above 50%)
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        assertEq(vaultFactory.ownerOf(nftId), alice);

        vm.prank(dustAuth);
        ownerWrapper.transferDustPosition(nftId);

        assertEq(vaultFactory.ownerOf(nftId), team);
    }

    function test_transferDustPosition_byTeam() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        vm.prank(team);
        ownerWrapper.transferDustPosition(nftId);

        assertEq(vaultFactory.ownerOf(nftId), team);
    }

    function test_transferDustPosition_byGovernance() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        vm.prank(governance);
        ownerWrapper.transferDustPosition(nftId);

        assertEq(vaultFactory.ownerOf(nftId), team);
    }

    function test_transferDustPosition_byTeam_skipsRatioCheck() public {
        uint256 nftId = _createDustPosition(alice, 1 * 1e18, 1e4);

        vm.prank(team);
        ownerWrapper.transferDustPosition(nftId);

        assertEq(vaultFactory.ownerOf(nftId), team);
    }

    function test_transferDustPosition_byGovernance_skipsRatioCheck() public {
        uint256 nftId = _createDustPosition(alice, 1 * 1e18, 1e4);

        vm.prank(governance);
        ownerWrapper.transferDustPosition(nftId);

        assertEq(vaultFactory.ownerOf(nftId), team);
    }

    function test_transferDustPosition_emitsEvent() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        vm.prank(dustAuth);
        vm.expectEmit(true, true, true, false);
        emit LogTransferDustPosition(nftId, alice, dustVaultId);
        ownerWrapper.transferDustPosition(nftId);
    }

    function test_transferDustPosition_clearApprovalAfterTransfer() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        vm.prank(dustAuth);
        ownerWrapper.transferDustPosition(nftId);

        assertEq(vaultFactory.getApproved(nftId), address(0));
    }

    function test_transferDustPosition_revertsWhenRatioDropsBelowThreshold() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        // increase oracle price: col worth 10x more → ratio drops to ~7.9% → too safe
        dustOracle.setPrice(1e15 * 10);

        vm.prank(dustAuth);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__PositionTooSafe)
        );
        ownerWrapper.transferDustPosition(nftId);
    }

    function test_transferDustPosition_revertsForInvalidPosition() public {
        vm.prank(dustAuth);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__InvalidPosition)
        );
        ownerWrapper.transferDustPosition(type(uint256).max);
    }
}

// ============ Multiple positions and edge cases ============

contract VaultFactoryOwnerEdgeCaseTest is VaultFactoryOwnerBaseTest {
    function test_transferPosition_multiplePositions() public {
        uint256 nftId1 = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);
        uint256 nftId2 = _createPosition(alice, 20000 * 1e6, 14000 * 1e18);

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);

        vm.prank(team);
        ownerWrapper.transferPosition(nftId1);
        assertEq(vaultFactory.ownerOf(nftId1), team);
        assertEq(vaultFactory.ownerOf(nftId2), alice);

        vm.prank(team);
        ownerWrapper.transferPosition(nftId2);
        assertEq(vaultFactory.ownerOf(nftId2), team);
    }

    function test_transferPosition_afterDeallowlisting() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);

        // remove allowlist
        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, false);

        vm.prank(team);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__VaultNotAllowlisted)
        );
        ownerWrapper.transferPosition(nftId);
    }

    function test_dustAuthCannotCallTransferPosition() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        vm.prank(governance);
        ownerWrapper.setVaultIdAllowlisted(vaultId, true);

        vm.prank(dustAuth);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.transferPosition(nftId);
    }

    function test_removedDustAuthCannotTransfer() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        vm.prank(governance);
        ownerWrapper.setTransferDustPosAuth(dustAuth, false);

        vm.prank(dustAuth);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        ownerWrapper.transferDustPosition(nftId);
    }

    function test_newDustAuthCanTransfer() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        address newAuth = makeAddr("newAuth");
        vm.prank(governance);
        ownerWrapper.setTransferDustPosAuth(newAuth, true);

        vm.prank(newAuth);
        ownerWrapper.transferDustPosition(nftId);

        assertEq(vaultFactory.ownerOf(nftId), team);
    }
}

// ============ Internal method unit & integration tests ============

contract VaultFactoryOwnerInternalMethodsTest is VaultFactoryOwnerBaseTest {
    VaultFactoryOwnerHarness harness;

    uint256 constant X19 = 0x7ffff;
    uint256 constant VAULT_T1_TYPE_ = 10000;

    function setUp() public override {
        super.setUp();
        uint256[] memory vaultIds_ = new uint256[](0);
        address[] memory dustPosAuths_ = new address[](0);
        harness = new VaultFactoryOwnerHarness(
            IFluidVaultFactory_OwnerWrapper(address(vaultFactory)),
            ILiquidity_OwnerWrapper(address(liquidity)),
            vaultIds_,
            dustPosAuths_
        );
    }

    // =============================================
    // _getPositionTickAndDebtRaw — step-by-step
    // =============================================

    /// @dev Replicates _getPositionTickAndDebtRaw step-by-step for manual verification.
    ///      Returns (tick, expectedDebtRaw) computed from raw vault storage. Dust is NOT subtracted.
    function _manualGetPositionTickAndDebtRaw(
        IFluidVault vault_,
        uint256 nftId_
    ) internal view returns (int256 tick_, uint256 expectedDebtRaw_) {
        uint256 positionData_ = vault_.readFromStorage(keccak256(abi.encode(nftId_, uint256(3))));

        if ((positionData_ & 1) == 1) return (0, 0);

        uint256 supply_ = (positionData_ >> 45) & X64;
        supply_ = (supply_ >> 8) << (supply_ & X8);

        tick_ = (positionData_ & 2) == 2 ? int256((positionData_ >> 2) & X19) : -int256((positionData_ >> 2) & X19);

        expectedDebtRaw_ = (TickMath.getRatioAtTick(int24(tick_)) * supply_) >> 96;

        {
            uint256 tickData_ = vault_.readFromStorage(keccak256(abi.encode(tick_, uint256(5))));
            uint256 tickId_ = (positionData_ >> 21) & X24;
            if (((tickData_ & 1) == 1) || (((tickData_ >> 1) & X24) > tickId_)) {
                (tick_, expectedDebtRaw_, supply_, , ) = vault_.fetchLatestPosition(
                    tick_,
                    tickId_,
                    expectedDebtRaw_,
                    tickData_
                );
            }
        }
    }

    function test_getPositionTickAndDebtRaw_matchesManualComputation() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        (int256 expectedTick, uint256 expectedDebtRaw) = _manualGetPositionTickAndDebtRaw(
            IFluidVault(address(vault)),
            nftId
        );

        (int256 actualTick, uint256 actualDebtRaw) = harness.exposedGetPositionTickAndDebtRawDirect(
            IFluidVault(address(vault)),
            nftId
        );

        assertEq(actualTick, expectedTick);
        assertEq(actualDebtRaw, expectedDebtRaw);
        assertTrue(actualDebtRaw > 0);
    }

    function test_getPositionTickAndDebtRaw_supplyOnlyPosition() public {
        vm.prank(alice);
        (uint256 nftId, , ) = vault.operate(0, 10000 * 1e6, 0, alice);

        (int256 tick, uint256 debtRaw) = harness.exposedGetPositionTickAndDebtRawDirect(
            IFluidVault(address(vault)),
            nftId
        );
        assertEq(tick, 0);
        assertEq(debtRaw, 0);
    }

    function test_getPositionTickAndDebtRaw_dustVaultMatchesManual() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        (int256 expectedTick, uint256 expectedDebtRaw) = _manualGetPositionTickAndDebtRaw(
            IFluidVault(address(dustVault)),
            nftId
        );

        (int256 actualTick, uint256 actualDebtRaw) = harness.exposedGetPositionTickAndDebtRawDirect(
            IFluidVault(address(dustVault)),
            nftId
        );
        assertEq(actualTick, expectedTick);
        assertEq(actualDebtRaw, expectedDebtRaw);
    }

    function test_getPositionTickAndDebtRaw_debtRawIsPositive() public {
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        (, uint256 debtRaw) = harness.exposedGetPositionTickAndDebtRawDirect(IFluidVault(address(vault)), nftId);
        assertTrue(debtRaw > 0);
    }

    function test_getPositionTickAndDebtRaw_multiplePositionsDiffer() public {
        uint256 nftId1 = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);
        uint256 nftId2 = _createPosition(bob, 10000 * 1e6, 3000 * 1e18);

        (int256 tick1, uint256 debtRaw1) = harness.exposedGetPositionTickAndDebtRawDirect(
            IFluidVault(address(vault)),
            nftId1
        );
        (int256 tick2, uint256 debtRaw2) = harness.exposedGetPositionTickAndDebtRawDirect(
            IFluidVault(address(vault)),
            nftId2
        );

        // 70% LTV has higher tick (riskier) than 30% LTV
        assertTrue(tick1 > tick2);
        assertTrue(debtRaw1 > debtRaw2);
    }

    // =============================================
    // _isPositionAboveRatioThreshold — step-by-step
    // =============================================

    function test_isPositionAboveRatioThreshold_matchesManualComputation() public {
        // Step 1: read vaultVariables2 from slot 1
        uint256 vaultVariables2 = IFluidVault(address(vault)).readFromStorage(bytes32(uint256(1)));

        // Step 2: T1 oracle address stored at bits 96+ of vaultVariables2
        address oracleAddr = address(uint160(vaultVariables2 >> 96));
        assertTrue(oracleAddr != address(0));

        // Step 3: oracle price (debt per col in 1e27)
        uint256 oraclePrice = IFluidOracle(oracleAddr).getExchangeRateOperate();

        // Step 4: raw oracle price adjusted for exchange prices
        (, , uint256 supplyExPrice, uint256 borrowExPrice) = IFluidVault(address(vault)).updateExchangePrices(
            vaultVariables2
        );
        uint256 rawOraclePrice = (oraclePrice * supplyExPrice) / borrowExPrice;

        // Step 5: apply RATIO_THRESHOLD = 500 (50% in 3-decimal precision)
        uint256 ratioAtThreshold = (rawOraclePrice * 500) / 1000;

        // Step 6: convert from 1e27 to tick-ratio space (scaled by 1 << 96)
        ratioAtThreshold = (ratioAtThreshold * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;

        // Step 7: tick at threshold
        (int tickAtThreshold, ) = TickMath.getTickAtRatio(ratioAtThreshold);

        // Verify: at threshold tick → true (>= check)
        assertTrue(
            harness.exposedIsPositionAboveRatioThresholdDirect(
                IFluidVault(address(vault)),
                VAULT_T1_TYPE_,
                tickAtThreshold
            )
        );

        // Verify: one below threshold → false
        assertFalse(
            harness.exposedIsPositionAboveRatioThresholdDirect(
                IFluidVault(address(vault)),
                VAULT_T1_TYPE_,
                tickAtThreshold - 1
            )
        );
    }

    function test_isPositionAboveRatioThreshold_oraclePriceShift() public {
        uint256 vaultVariables2 = IFluidVault(address(vault)).readFromStorage(bytes32(uint256(1)));
        (, , uint256 supplyExPrice, uint256 borrowExPrice) = IFluidVault(address(vault)).updateExchangePrices(
            vaultVariables2
        );

        // threshold tick at original oracle price (1e39)
        uint256 rawPrice1 = (1e39 * supplyExPrice) / borrowExPrice;
        uint256 ratio1 = (rawPrice1 * 500) / 1000;
        ratio1 = (ratio1 * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;
        (int tick1, ) = TickMath.getTickAtRatio(ratio1);

        // change oracle price to 10e39 (collateral worth 10x more)
        oracle.setPrice(10e39);

        uint256 rawPrice2 = (10e39 * supplyExPrice) / borrowExPrice;
        uint256 ratio2 = (rawPrice2 * 500) / 1000;
        ratio2 = (ratio2 * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;
        (int tick2, ) = TickMath.getTickAtRatio(ratio2);

        // higher collateral value → higher threshold tick (harder to qualify as "risky")
        assertTrue(tick2 > tick1);

        assertTrue(
            harness.exposedIsPositionAboveRatioThresholdDirect(IFluidVault(address(vault)), VAULT_T1_TYPE_, tick2)
        );
        assertFalse(
            harness.exposedIsPositionAboveRatioThresholdDirect(IFluidVault(address(vault)), VAULT_T1_TYPE_, tick2 - 1)
        );
    }

    function test_isPositionAboveRatioThreshold_classifiesRiskyPosition() public {
        // 70% LTV → should be above 50% threshold
        uint256 nftId = _createPosition(alice, 10000 * 1e6, 7000 * 1e18);

        (int256 posTick, ) = harness.exposedGetPositionTickAndDebtRawDirect(IFluidVault(address(vault)), nftId);

        assertTrue(
            harness.exposedIsPositionAboveRatioThresholdDirect(IFluidVault(address(vault)), VAULT_T1_TYPE_, posTick)
        );
    }

    function test_isPositionAboveRatioThreshold_classifiesSafePosition() public {
        // ~7% LTV → should be below 50% threshold
        uint256 nftId = _createPosition(alice, 100000 * 1e6, 7000 * 1e18);

        (int256 posTick, ) = harness.exposedGetPositionTickAndDebtRawDirect(IFluidVault(address(vault)), nftId);

        assertFalse(
            harness.exposedIsPositionAboveRatioThresholdDirect(IFluidVault(address(vault)), VAULT_T1_TYPE_, posTick)
        );
    }

    function test_isPositionAboveRatioThreshold_dustVault() public {
        // 79% LTV on dustVault → should be above 50% threshold
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        (int256 posTick, ) = harness.exposedGetPositionTickAndDebtRawDirect(IFluidVault(address(dustVault)), nftId);

        assertTrue(
            harness.exposedIsPositionAboveRatioThresholdDirect(IFluidVault(address(dustVault)), VAULT_T1_TYPE_, posTick)
        );
    }

    // =============================================
    // Cross-method: combined flow matching transferDustPosition
    // =============================================

    function test_combinedFlow_dustPositionRiskyAboveThreshold() public {
        uint256 nftId = _createDustPosition(alice, 1e17, 79000);

        (int256 tick, uint256 debtRaw) = harness.exposedGetPositionTickAndDebtRawDirect(
            IFluidVault(address(dustVault)),
            nftId
        );

        // debtRaw should be below DEBT_THRESHOLD (1e5)
        assertTrue(debtRaw < 1e5);
        assertTrue(debtRaw > 0);

        // position should be above ratio threshold (risky)
        assertTrue(
            harness.exposedIsPositionAboveRatioThresholdDirect(IFluidVault(address(dustVault)), VAULT_T1_TYPE_, tick)
        );
    }

    function test_combinedFlow_safePositionBelowThreshold() public {
        // Small debt, very safe ratio
        uint256 nftId = _createDustPosition(alice, 1 * 1e18, 1e4);

        (int256 tick, uint256 debtRaw) = harness.exposedGetPositionTickAndDebtRawDirect(
            IFluidVault(address(dustVault)),
            nftId
        );

        assertTrue(debtRaw < 1e5);
        assertTrue(debtRaw > 0);

        // 1% LTV → below 50% threshold
        assertFalse(
            harness.exposedIsPositionAboveRatioThresholdDirect(IFluidVault(address(dustVault)), VAULT_T1_TYPE_, tick)
        );
    }
}

contract MockOwnerWrapperFactory is IFluidVaultFactory_OwnerWrapper {
    mapping(bytes32 => uint256) internal _storageValues;
    mapping(uint256 => address) internal _vaults;

    function setStorage(bytes32 slot_, uint256 value_) external {
        _storageValues[slot_] = value_;
    }

    function setVaultAddress(uint256 vaultId_, address vault_) external {
        _vaults[vaultId_] = vault_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256 result_) {
        return _storageValues[slot_];
    }

    function getVaultAddress(uint256 vaultId_) external view returns (address vault_) {
        return _vaults[vaultId_];
    }

    function isVault(address vault_) external pure returns (bool) {
        return vault_ != address(0);
    }

    function transferFrom(address, address, uint256) external {}

    function setDeployer(address, bool) external {}

    function setGlobalAuth(address, bool) external {}

    function setVaultAuth(address, address, bool) external {}

    function setVaultDeploymentLogic(address, bool) external {}

    function spell(address target_, bytes memory data_) external returns (bytes memory response_) {
        (bool success_, bytes memory response__) = target_.delegatecall(data_);
        require(success_, "spell-failed");
        return response__;
    }

    function transferOwnership(address) external {}
}

contract MockOwnerWrapperLiquidity is ILiquidity_OwnerWrapper {
    mapping(bytes32 => uint256) internal _storageValues;

    function setStorage(bytes32 slot_, uint256 value_) external {
        _storageValues[slot_] = value_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256 result_) {
        return _storageValues[slot_];
    }
}

contract MockOwnerWrapperOracle is IFluidOracle {
    uint256 internal _exchangeRate;

    constructor(uint256 exchangeRate_) {
        _exchangeRate = exchangeRate_;
    }

    function setExchangeRate(uint256 exchangeRate_) external {
        _exchangeRate = exchangeRate_;
    }

    function getExchangeRate() external view returns (uint256 exchangeRate_) {
        return _exchangeRate;
    }

    function getExchangeRateOperate() external view returns (uint256 exchangeRate_) {
        return _exchangeRate;
    }

    function getExchangeRateLiquidate() external view returns (uint256 exchangeRate_) {
        return _exchangeRate;
    }

    function getExchangeRateOperateRaw() external view returns (uint256 exchangeRate_) {
        return _exchangeRate;
    }

    function getExchangeRateLiquidateRaw() external view returns (uint256 exchangeRate_) {
        return _exchangeRate;
    }

    function getExchangeRateRaw() external view returns (uint256 exchangeRate_) {
        return _exchangeRate;
    }

    function infoName() external pure returns (string memory) {
        return "mock";
    }

    function targetDecimals() external pure returns (uint8) {
        return 27;
    }
}

contract MockOwnerWrapperRevertingOracle is IFluidOracle {
    function getExchangeRate() external pure returns (uint256) {
        revert("oracle down");
    }

    function getExchangeRateOperate() external pure returns (uint256) {
        revert("oracle down");
    }

    function getExchangeRateLiquidate() external pure returns (uint256) {
        revert("oracle down");
    }

    function getExchangeRateOperateRaw() external pure returns (uint256) {
        revert("oracle down");
    }

    function getExchangeRateLiquidateRaw() external pure returns (uint256) {
        revert("oracle down");
    }

    function getExchangeRateRaw() external pure returns (uint256) {
        revert("oracle down");
    }

    function infoName() external pure returns (string memory) {
        return "reverting";
    }

    function targetDecimals() external pure returns (uint8) {
        return 27;
    }
}

contract MockOwnerWrapperOracleDeployer {
    function deploy(uint256 exchangeRate_) external returns (MockOwnerWrapperOracle oracle_) {
        oracle_ = new MockOwnerWrapperOracle(exchangeRate_);
    }
}

contract MockOwnerWrapperTypedVault is IFluidVault {
    mapping(bytes32 => uint256) internal _storageValues;
    ConstantViews internal _constantsView;
    uint256 internal _vaultType;
    int256 internal _latestTick;
    uint256 internal _latestBorrow;
    uint256 internal _latestSupply;
    uint256 internal _supplyExPrice = 1e12;
    uint256 internal _borrowExPrice = 1e12;

    constructor(uint256 vaultType_) {
        _vaultType = vaultType_;
    }

    function setStorage(bytes32 slot_, uint256 value_) external {
        _storageValues[slot_] = value_;
    }

    function setConstantsDeployer(address deployer_) external {
        _constantsView.deployer = deployer_;
    }

    function setLatestPosition(int256 tick_, uint256 borrow_, uint256 supply_) external {
        _latestTick = tick_;
        _latestBorrow = borrow_;
        _latestSupply = supply_;
    }

    function setExchangePrices(uint256 supplyExPrice_, uint256 borrowExPrice_) external {
        _supplyExPrice = supplyExPrice_;
        _borrowExPrice = borrowExPrice_;
    }

    function VAULT_ID() external pure returns (uint256) {
        return 0;
    }

    function TYPE() external view returns (uint256) {
        return _vaultType;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256 result_) {
        return _storageValues[slot_];
    }

    function constantsView() external view returns (ConstantViews memory constantsView_) {
        return _constantsView;
    }

    function fetchLatestPosition(
        int256,
        uint256,
        uint256,
        uint256
    ) external view returns (int256, uint256, uint256, uint256, uint256) {
        return (_latestTick, _latestBorrow, _latestSupply, 0, 0);
    }

    function updateExchangePrices(
        uint256
    )
        external
        view
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        return (0, 0, _supplyExPrice, _borrowExPrice);
    }

    function updateExchangePricesOnStorage()
        external
        pure
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        return (0, 0, 0, 0);
    }

    function LIQUIDITY() external pure returns (address) {
        return address(0);
    }

    function rebalance(int, int, int, int) external payable returns (int supplyAmt_, int borrowAmt_) {
        revert("not-implemented");
    }

    function simulateLiquidate(uint256, bool) external pure {
        revert("not-implemented");
    }
}

contract MockOwnerWrapperLegacyVault {
    mapping(bytes32 => uint256) internal _storageValues;
    IFluidVault.ConstantViews internal _constantsView;
    uint256 internal _vaultId;
    int256 internal _latestTick;
    uint256 internal _latestBorrow;
    uint256 internal _latestSupply;
    uint256 internal _supplyExPrice = 1e12;
    uint256 internal _borrowExPrice = 1e12;

    constructor(uint256 vaultId_) {
        _vaultId = vaultId_;
    }

    function setStorage(bytes32 slot_, uint256 value_) external {
        _storageValues[slot_] = value_;
    }

    function setConstantsDeployer(address deployer_) external {
        _constantsView.deployer = deployer_;
    }

    function setLatestPosition(int256 tick_, uint256 borrow_, uint256 supply_) external {
        _latestTick = tick_;
        _latestBorrow = borrow_;
        _latestSupply = supply_;
    }

    function setExchangePrices(uint256 supplyExPrice_, uint256 borrowExPrice_) external {
        _supplyExPrice = supplyExPrice_;
        _borrowExPrice = borrowExPrice_;
    }

    function VAULT_ID() external view returns (uint256) {
        return _vaultId;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256 result_) {
        return _storageValues[slot_];
    }

    function constantsView() external view returns (IFluidVault.ConstantViews memory constantsView_) {
        return _constantsView;
    }

    function fetchLatestPosition(
        int256,
        uint256,
        uint256,
        uint256
    ) external view returns (int256, uint256, uint256, uint256, uint256) {
        return (_latestTick, _latestBorrow, _latestSupply, 0, 0);
    }

    function updateExchangePrices(
        uint256
    )
        external
        view
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        return (0, 0, _supplyExPrice, _borrowExPrice);
    }

    function updateExchangePricesOnStorage()
        external
        pure
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        return (0, 0, 0, 0);
    }

    function LIQUIDITY() external pure returns (address) {
        return address(0);
    }
}

contract VaultFactoryOwnerHarness is VaultFactoryOwner {
    constructor(
        IFluidVaultFactory_OwnerWrapper factory_,
        ILiquidity_OwnerWrapper liquidity_,
        uint256[] memory vaultIds_,
        address[] memory dustPosAuths_
    ) VaultFactoryOwner(factory_, liquidity_, vaultIds_, dustPosAuths_) {}

    function exposedGetPositionTickAndDebtRaw(
        uint256 tokenId_,
        uint256 vaultId_
    ) external view returns (int256 tick_, uint256 debtRaw_) {
        (IFluidVault vault_, ) = _resolveVault(vaultId_);
        return _getPositionTickAndDebtRaw(vault_, tokenId_);
    }

    function exposedIsPositionAboveRatioThreshold(
        int256 positionTick_,
        uint256 vaultId_
    ) external view returns (bool isAboveThreshold_) {
        (IFluidVault vault_, uint256 vaultType_) = _resolveVault(vaultId_);
        return _isPositionAboveRatioThreshold(vault_, vaultType_, positionTick_);
    }

    function exposedGetPositionTickAndDebtRawDirect(
        IFluidVault vault_,
        uint256 tokenId_
    ) external view returns (int256 tick_, uint256 debtRaw_) {
        return _getPositionTickAndDebtRaw(vault_, tokenId_);
    }

    function exposedIsPositionAboveRatioThresholdDirect(
        IFluidVault vault_,
        uint256 vaultType_,
        int256 positionTick_
    ) external view returns (bool isAboveThreshold_) {
        return _isPositionAboveRatioThreshold(vault_, vaultType_, positionTick_);
    }
}

contract VaultFactoryOwnerCoverageGapTest is Test {
    event LogSetVaultIdAllowlisted(uint256 indexed vaultId, bool indexed allowed);
    event LogSetTransferDustPosAuth(address indexed auth, bool indexed allowed);

    bytes32 internal constant LIQUIDITY_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    uint256 internal constant TEST_VAULT_ID = 77;
    uint256 internal constant VAULT_T1_TYPE = 10000;
    uint256 internal constant NON_T1_TYPE = 10001;

    MockOwnerWrapperFactory internal factory;
    MockOwnerWrapperLiquidity internal liquidity;
    VaultFactoryOwnerHarness internal harness;

    function setUp() public {
        factory = new MockOwnerWrapperFactory();
        liquidity = new MockOwnerWrapperLiquidity();
        liquidity.setStorage(LIQUIDITY_ADMIN_SLOT, uint256(uint160(address(this))));

        uint256[] memory vaultIds_ = new uint256[](0);
        address[] memory dustPosAuths_ = new address[](0);
        harness = new VaultFactoryOwnerHarness(factory, liquidity, vaultIds_, dustPosAuths_);
    }

    function _encodeCompactAmount(uint256 rawAmount_) internal pure returns (uint256) {
        return rawAmount_ << 8;
    }

    function _encodePositionData(
        int256 tick_,
        uint256 tickId_,
        uint256 supplyRaw_,
        uint256 dustBorrowRaw_,
        bool isSupplyOnly_
    ) internal pure returns (uint256 positionData_) {
        uint256 absTick_ = uint256(tick_ >= 0 ? tick_ : -tick_);

        positionData_ = absTick_ << 2;

        if (tick_ >= 0) {
            positionData_ |= 2;
        }

        if (isSupplyOnly_) {
            positionData_ |= 1;
        }

        positionData_ |= tickId_ << 21;
        positionData_ |= _encodeCompactAmount(supplyRaw_) << 45;
        positionData_ |= _encodeCompactAmount(dustBorrowRaw_) << 109;
    }

    function test_constructor_allowlistsInitialVaultIdsAndDustAuths() public {
        uint256[] memory vaultIds_ = new uint256[](2);
        vaultIds_[0] = 11;
        vaultIds_[1] = 12;
        factory.setVaultAddress(11, address(new MockOwnerWrapperTypedVault(VAULT_T1_TYPE)));
        factory.setVaultAddress(12, address(new MockOwnerWrapperTypedVault(VAULT_T1_TYPE)));

        address[] memory dustPosAuths_ = new address[](2);
        dustPosAuths_[0] = makeAddr("initialDustAuth1");
        dustPosAuths_[1] = makeAddr("initialDustAuth2");

        vm.expectEmit(true, true, false, false);
        emit LogSetVaultIdAllowlisted(11, true);
        vm.expectEmit(true, true, false, false);
        emit LogSetVaultIdAllowlisted(12, true);
        vm.expectEmit(true, true, false, false);
        emit LogSetTransferDustPosAuth(dustPosAuths_[0], true);
        vm.expectEmit(true, true, false, false);
        emit LogSetTransferDustPosAuth(dustPosAuths_[1], true);

        VaultFactoryOwner wrapper_ = new VaultFactoryOwner(factory, liquidity, vaultIds_, dustPosAuths_);

        assertTrue(wrapper_.vaultIdAllowlisted(11));
        assertTrue(wrapper_.vaultIdAllowlisted(12));
        assertTrue(wrapper_.transferDustPosAuths(dustPosAuths_[0]));
        assertTrue(wrapper_.transferDustPosAuths(dustPosAuths_[1]));
    }

    function test_getPositionTickAndDebtRaw_usesLatestPositionWhenTickWasLiquidated() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));

        uint256 tokenId_ = 2;
        vault_.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            _encodePositionData(0, 7, 50_000, 10_000, false)
        );
        vault_.setStorage(keccak256(abi.encode(int256(0), uint256(5))), 1);
        vault_.setStorage(bytes32(uint256(1)), 0);
        vault_.setLatestPosition(123, 90_000, 50_000);
        vault_.setExchangePrices(1e12, 1e12);

        (int256 tick_, uint256 debtRaw_) = harness.exposedGetPositionTickAndDebtRaw(tokenId_, TEST_VAULT_ID);

        assertEq(tick_, 123);
        assertEq(debtRaw_, 90_000);
    }

    function test_isPositionAboveRatioThreshold_usesLegacyT1OraclePathWhenTypeIsMissing() public {
        MockOwnerWrapperLegacyVault vault_ = new MockOwnerWrapperLegacyVault(TEST_VAULT_ID);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(0, TEST_VAULT_ID));
    }

    function test_onlyGovernance_tracksLiquidityAdminSlot() public {
        address newGovernance_ = makeAddr("newGovernance");
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        liquidity.setStorage(LIQUIDITY_ADMIN_SLOT, uint256(uint160(newGovernance_)));

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__Unauthorized)
        );
        harness.setVaultIdAllowlisted(TEST_VAULT_ID, true);

        vm.prank(newGovernance_);
        harness.setVaultIdAllowlisted(TEST_VAULT_ID, true);
        assertTrue(harness.vaultIdAllowlisted(TEST_VAULT_ID));
    }

    function test_transferDustPosition_revertsAtDebtThresholdViaHarness() public {
        uint256 tokenId_ = 4;
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        factory.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            uint256(uint160(address(this))) | (TEST_VAULT_ID << 192)
        );
        vault_.setStorage(keccak256(abi.encode(tokenId_, uint256(3))), _encodePositionData(0, 7, 100_001, 0, false));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__DebtAboveThreshold)
        );
        harness.transferDustPosition(tokenId_);
    }

    function test_isPositionAboveRatioThreshold_usesComputedOraclePathForNonT1Vault() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(NON_T1_TYPE);
        MockOwnerWrapperOracleDeployer deployer_ = new MockOwnerWrapperOracleDeployer();
        deployer_.deploy(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setConstantsDeployer(address(deployer_));
        vault_.setStorage(bytes32(uint256(1)), uint256(1) << 92);
        vault_.setExchangePrices(1e12, 1e12);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(0, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: negative tick decoding ============

    function test_getPositionTickAndDebtRaw_negativeTick() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));

        int256 encodedTick_ = -500;
        uint256 tokenId_ = 10;
        vault_.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            _encodePositionData(encodedTick_, 1, 100_000, 0, false)
        );
        vault_.setStorage(bytes32(uint256(1)), 0);
        vault_.setExchangePrices(1e12, 1e12);

        (int256 tick_, uint256 debtRaw_) = harness.exposedGetPositionTickAndDebtRaw(tokenId_, TEST_VAULT_ID);

        assertEq(tick_, -500);
        assertTrue(debtRaw_ > 0);
    }

    // ============ Coverage Gap: positive non-zero tick decoding ============

    function test_getPositionTickAndDebtRaw_positiveTick() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));

        int256 encodedTick_ = int256(500);
        uint256 tokenId_ = 11;
        vault_.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            _encodePositionData(encodedTick_, 1, 100_000, 0, false)
        );
        vault_.setStorage(bytes32(uint256(1)), 0);
        vault_.setExchangePrices(1e12, 1e12);

        (int256 tick_, uint256 debtRaw_) = harness.exposedGetPositionTickAndDebtRaw(tokenId_, TEST_VAULT_ID);

        assertEq(tick_, 500);
        assertTrue(debtRaw_ > 0);
    }

    // ============ Coverage Gap: liquidation by tick ID mismatch ============

    function test_getPositionTickAndDebtRaw_liquidationByTickIdMismatch() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));

        uint256 tokenId_ = 12;
        uint256 posTickId_ = 3;
        vault_.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            _encodePositionData(0, posTickId_, 50_000, 10_000, false)
        );

        // tickData bit 0 = 0 (not liquidated), but (tickData >> 1) & X24 = 10 > posTickId_ = 3
        uint256 tickData_ = 10 << 1;
        vault_.setStorage(keccak256(abi.encode(int256(0), uint256(5))), tickData_);
        vault_.setStorage(bytes32(uint256(1)), 0);
        vault_.setLatestPosition(200, 80_000, 50_000);
        vault_.setExchangePrices(1e12, 1e12);

        (int256 tick_, uint256 debtRaw_) = harness.exposedGetPositionTickAndDebtRaw(tokenId_, TEST_VAULT_ID);

        assertEq(tick_, 200);
        assertEq(debtRaw_, 80_000);
    }

    // ============ Coverage Gap: normal path (no liquidation) via mock ============

    function test_getPositionTickAndDebtRaw_normalPathNoLiquidation() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));

        uint256 tokenId_ = 14;
        uint256 posTickId_ = 5;
        vault_.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            _encodePositionData(0, posTickId_, 100_000, 20_000, false)
        );

        // tickData: bit 0 = 0, (tickData >> 1) & X24 = posTickId_ (not greater, equal)
        uint256 tickData_ = posTickId_ << 1;
        vault_.setStorage(keccak256(abi.encode(int256(0), uint256(5))), tickData_);
        vault_.setStorage(bytes32(uint256(1)), 0);
        vault_.setExchangePrices(1e12, 1e12);

        (int256 tick_, uint256 debtRaw_) = harness.exposedGetPositionTickAndDebtRaw(tokenId_, TEST_VAULT_ID);

        assertEq(tick_, 0);
        // rawDebt = supply * ratio >> 96 at tick 0 = supply = 100_000. Dust is NOT subtracted.
        assertEq(debtRaw_, 100_000);
    }

    // ============ Coverage Gap: supply-only via mock ============

    function test_getPositionTickAndDebtRaw_supplyOnlyViaMock() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));

        uint256 tokenId_ = 15;
        vault_.setStorage(keccak256(abi.encode(tokenId_, uint256(3))), _encodePositionData(0, 0, 100_000, 0, true));

        (int256 tick_, uint256 debtRaw_) = harness.exposedGetPositionTickAndDebtRaw(tokenId_, TEST_VAULT_ID);

        assertEq(tick_, 0);
        assertEq(debtRaw_, 0);
    }

    // ============ Coverage Gap: _isPositionAboveRatioThreshold returns false ============

    function test_isPositionAboveRatioThreshold_returnsFalse() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        // very negative tick means position is very safe (low LTV)
        assertFalse(harness.exposedIsPositionAboveRatioThreshold(-20000, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: exact boundary tick ============

    function test_isPositionAboveRatioThreshold_exactBoundary() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        // replicate threshold computation: oraclePrice=1e27, supplyEx=borrowEx=1e12
        // rawOraclePrice = 1e27, ratioAtThreshold = 1e27 * 500 / 1000 = 5e26
        uint256 rawOraclePrice_ = uint256(1e27);
        uint256 ratioAtThreshold_ = (rawOraclePrice_ * 500) / 1000;
        ratioAtThreshold_ = (ratioAtThreshold_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;
        (int tickAtThreshold_, ) = TickMath.getTickAtRatio(ratioAtThreshold_);

        // at threshold tick: should return true (>=)
        assertTrue(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_, TEST_VAULT_ID));

        // one below: should return false
        assertFalse(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_ - 1, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: non-trivial exchange prices in ratio check ============

    function test_isPositionAboveRatioThreshold_nonTrivialExchangePrices() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        // supplyExPrice = 2e12, borrowExPrice = 1e12 → rawOraclePrice = 1e27 * 2 = 2e27
        vault_.setExchangePrices(2e12, 1e12);

        // rawOraclePrice = 2e27, ratioAtThreshold = 2e27 * 500 / 1000 = 1e27
        uint256 rawOraclePrice_ = uint256(2e27);
        uint256 ratioAtThreshold_ = (rawOraclePrice_ * 500) / 1000;
        ratioAtThreshold_ = (ratioAtThreshold_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;
        (int tickAtThreshold_, ) = TickMath.getTickAtRatio(ratioAtThreshold_);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_, TEST_VAULT_ID));
        assertFalse(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_ - 1, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: T1 vault with working TYPE() method ============

    function test_isPositionAboveRatioThreshold_t1VaultWithTypeMethod() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        // TYPE() returns 10000 (VAULT_T1_TYPE), should use T1 oracle path
        assertTrue(harness.exposedIsPositionAboveRatioThreshold(0, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: oracle reverts → assume risky ============

    function test_isPositionAboveRatioThreshold_returnsTrueWhenOracleReverts() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperRevertingOracle oracle_ = new MockOwnerWrapperRevertingOracle();

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(-20000, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: oracle returns 0 → assume risky ============

    function test_isPositionAboveRatioThreshold_returnsTrueWhenOracleReturnsZero() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(0);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(-20000, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: oracle price too low (< 1e9) → assume risky ============

    function test_isPositionAboveRatioThreshold_returnsTrueWhenOraclePriceTooLow() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e9 - 1);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(-20000, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: oracle price too high (> 1e54) → assume risky ============

    function test_isPositionAboveRatioThreshold_returnsTrueWhenOraclePriceTooHigh() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e54 + 1);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(-20000, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: oracle price at 1e9 boundary (valid) → normal path ============

    function test_isPositionAboveRatioThreshold_normalAtMinValidPrice() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        // 1e9 is the minimum valid price. With equal exchange prices, rawOraclePrice = 1e9.
        // ratioAtThreshold = 1e9 * 500 / 1000 = 5e8 → very low ratio → very negative threshold tick.
        // A tick of 0 (100% LTV) is certainly above this threshold.
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e9);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(0, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: raw oracle price cap at 1e45 ============

    function test_isPositionAboveRatioThreshold_capsRawOraclePriceAt1e45() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        // price 1e54 is max valid, with supplyExPrice=1e15 / borrowExPrice=1e12 → rawPrice = 1e57 > 1e45, gets capped
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e54);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e15, 1e12);

        // Manually compute expected threshold tick with capped price
        uint256 rawOraclePrice_ = 1e45; // capped
        uint256 ratioAtThreshold_ = (rawOraclePrice_ * 500) / 1000;
        ratioAtThreshold_ = (ratioAtThreshold_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;
        (int tickAtThreshold_, ) = TickMath.getTickAtRatio(ratioAtThreshold_);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_, TEST_VAULT_ID));
        assertFalse(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_ - 1, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: debtRaw_ == DEBT_THRESHOLD exactly → passes debt check ============

    function test_transferDustPosition_passesAtExactDebtThreshold() public {
        uint256 tokenId_ = 20;
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        factory.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            uint256(uint160(address(this))) | (TEST_VAULT_ID << 192)
        );
        // supply = 100_000 at tick 0 → debtRaw = 100_000 = DEBT_THRESHOLD exactly. Check is >, so should pass.
        vault_.setStorage(keccak256(abi.encode(tokenId_, uint256(3))), _encodePositionData(0, 7, 100_000, 0, false));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        // Should NOT revert on DebtAboveThreshold (100_000 is not > 100_000).
        // It should proceed to ratio check. Tick 0 is at 100% LTV, above 50% threshold.
        // Since caller is address(this) = governance (set via liquidity admin slot), ratio check is skipped.
        harness.transferDustPosition(tokenId_);
    }

    // ============ Coverage Gap: debtRaw_ == DEBT_THRESHOLD + 1 → reverts ============

    function test_transferDustPosition_revertsAtDebtThresholdPlusOne() public {
        uint256 tokenId_ = 21;
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e27);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        factory.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            uint256(uint160(address(this))) | (TEST_VAULT_ID << 192)
        );
        // supply = 100_001 at tick 0 → debtRaw = 100_001 > DEBT_THRESHOLD
        vault_.setStorage(keccak256(abi.encode(tokenId_, uint256(3))), _encodePositionData(0, 7, 100_001, 0, false));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__DebtAboveThreshold)
        );
        harness.transferDustPosition(tokenId_);
    }

    // ============ Coverage Gap: oracle price at exact 1e54 boundary (valid) ============

    function test_isPositionAboveRatioThreshold_normalAtMaxValidPrice() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        // 1e54 is the maximum valid price (check is > 1e54, so exactly 1e54 is valid).
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e54);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        // rawOraclePrice = 1e54 (equal exchange prices). > 1e45, so gets capped to 1e45.
        // Should proceed normally with capped price (same as capsRawOraclePriceAt1e45 test).
        uint256 rawOraclePrice_ = 1e45; // capped
        uint256 ratioAtThreshold_ = (rawOraclePrice_ * 500) / 1000;
        ratioAtThreshold_ = (ratioAtThreshold_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;
        (int tickAtThreshold_, ) = TickMath.getTickAtRatio(ratioAtThreshold_);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_, TEST_VAULT_ID));
        assertFalse(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_ - 1, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: rawOraclePrice at exactly 1e45 (should NOT be capped) ============

    function test_isPositionAboveRatioThreshold_rawOraclePriceAtExact1e45NotCapped() public {
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        // We need rawOraclePrice = oraclePrice * supplyExPrice / borrowExPrice = 1e45 exactly.
        // With supplyExPrice = 1e12, borrowExPrice = 1e12: oraclePrice must be 1e45.
        // But 1e45 < 1e54 so it passes the range check.
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(1e45);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        // rawOraclePrice = 1e45 exactly. Check is > 1e45, so NOT capped.
        uint256 rawOraclePrice_ = 1e45;
        uint256 ratioAtThreshold_ = (rawOraclePrice_ * 500) / 1000;
        ratioAtThreshold_ = (ratioAtThreshold_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;
        (int tickAtThreshold_, ) = TickMath.getTickAtRatio(ratioAtThreshold_);

        assertTrue(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_, TEST_VAULT_ID));
        assertFalse(harness.exposedIsPositionAboveRatioThreshold(tickAtThreshold_ - 1, TEST_VAULT_ID));
    }

    // ============ Coverage Gap: transferDustPosition succeeds via dustAuth when oracle reverts ============

    function test_transferDustPosition_succeedsWhenOracleRevertsViaDustAuth() public {
        uint256 tokenId_ = 30;
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperRevertingOracle oracle_ = new MockOwnerWrapperRevertingOracle();

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        factory.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            uint256(uint160(address(this))) | (TEST_VAULT_ID << 192)
        );
        // supply = 50_000, tick 0 → debtRaw = 50_000 < DEBT_THRESHOLD
        vault_.setStorage(keccak256(abi.encode(tokenId_, uint256(3))), _encodePositionData(0, 7, 50_000, 0, false));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        address testDustAuth_ = makeAddr("testDustAuth");
        harness.setTransferDustPosAuth(testDustAuth_, true);

        // Oracle reverts → _isPositionAboveRatioThreshold returns true → dustAuth should succeed
        vm.prank(testDustAuth_);
        harness.transferDustPosition(tokenId_);
    }

    // ============ Coverage Gap: transferDustPosition succeeds via dustAuth when oracle returns 0 ============

    function test_transferDustPosition_succeedsWhenOracleReturnsZeroViaDustAuth() public {
        uint256 tokenId_ = 31;
        MockOwnerWrapperTypedVault vault_ = new MockOwnerWrapperTypedVault(VAULT_T1_TYPE);
        MockOwnerWrapperOracle oracle_ = new MockOwnerWrapperOracle(0);

        factory.setVaultAddress(TEST_VAULT_ID, address(vault_));
        factory.setStorage(
            keccak256(abi.encode(tokenId_, uint256(3))),
            uint256(uint160(address(this))) | (TEST_VAULT_ID << 192)
        );
        vault_.setStorage(keccak256(abi.encode(tokenId_, uint256(3))), _encodePositionData(0, 7, 50_000, 0, false));
        vault_.setStorage(bytes32(uint256(1)), uint256(uint160(address(oracle_))) << 96);
        vault_.setExchangePrices(1e12, 1e12);

        address testDustAuth_ = makeAddr("testDustAuth");
        harness.setTransferDustPosAuth(testDustAuth_, true);

        // Oracle returns 0 → _isPositionAboveRatioThreshold returns true → dustAuth should succeed
        vm.prank(testDustAuth_);
        harness.transferDustPosition(tokenId_);
    }

    // ============ Coverage Gap: _resolveVault reverts when vault address is zero ============

    function test_resolveVault_revertsWhenVaultAddressIsZero() public {
        // vault ID 9999 has no address registered in the mock factory → getVaultAddress returns address(0)
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultFactoryOwner__InvalidVault)
        );
        harness.exposedGetPositionTickAndDebtRaw(1, 9999);
    }
}
