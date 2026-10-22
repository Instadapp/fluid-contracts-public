// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BasicValidations } from "contracts/libraries/utils/basicValidations.sol";
import { LibsErrorTypes } from "contracts/libraries/errorTypes.sol";
import { FluidPauseAuth } from "contracts/config/pauseAuth/main.sol";
import { FluidPauseAuthOracleV2 } from "contracts/config/pauseAuth/pauseAuthOracleV2.sol";
import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";

error Access__Unauthorized();

interface IOracleV2T {
    function setGuardian(address guardian_, bool allowed_) external;

    function setPausedState(address token_, bool pauseOperate_, bool pauseLiquidate_) external;

    function getTokenConfig(address token_) external view returns (bool, bool, uint8, uint8);
}

contract MockLiquidity {
    mapping(bytes32 => uint256) internal _storage;

    function setStorage(bytes32 slot_, uint256 value_) external {
        _storage[slot_] = value_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        return _storage[slot_];
    }
}

contract PauseAuthOracleV2Test is Test {
    event LogPauseOracleV2(address indexed token);
    event LogUnpauseOracleV2(address indexed token);
    event LogSkipTokenNotPausable(address indexed token);
    event LogSetPauseAuthContract(address indexed pauseAuthContract);

    bytes32 internal constant PAUSE_TOPIC = keccak256("LogPauseOracleV2(address)");
    bytes32 internal constant UNPAUSE_TOPIC = keccak256("LogUnpauseOracleV2(address)");
    bytes32 internal constant SKIP_TOPIC = keccak256("LogSkipTokenNotPausable(address)");

    address internal constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address internal constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    bytes4 internal constant ORACLE_V2_ERROR = bytes4(keccak256("FluidUsdOracleError(uint256)"));
    uint256 internal constant ORACLE_V2_UNAUTHORIZED = 310002;

    MockLiquidity internal mockLiquidity;
    address internal authGate;
    IOracleV2T internal oracleV2;
    FluidPauseAuthOracleV2 internal oracleExec;
    FluidPauseAuth internal pauseAuth;

    address internal governance;
    address internal bot;
    address internal manual;
    address internal unpauser;
    address internal tokenA;
    address internal tokenB;

    function setUp() public {
        governance = makeAddr("governance");
        bot = makeAddr("bot");
        manual = makeAddr("manual");
        unpauser = makeAddr("unpauser");
        tokenA = makeAddr("tokenA");
        tokenB = makeAddr("tokenB");

        mockLiquidity = new MockLiquidity();
        mockLiquidity.setStorage(LIQUIDITY_GOVERNANCE_SLOT, uint256(uint160(governance)));

        authGate = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(address(mockLiquidity), TEAM_MULTISIG, TEAM_MULTISIG2, makeAddr("teamTimelock"))
        );

        // FluidUsdOracle and its proxy are pragma 0.8.36, so they are deployed by artifact path.
        address oracleV2Impl_ = deployCode(
            "contracts/oracleV2/usdOracle/main.sol:FluidUsdOracle",
            abi.encode(address(mockLiquidity))
        );
        oracleV2 = IOracleV2T(
            deployCode(
                "contracts/oracleV2/usdOracle/proxy.sol:FluidUsdOracleProxy",
                abi.encode(oracleV2Impl_, bytes(""))
            )
        );

        oracleExec = new FluidPauseAuthOracleV2(address(mockLiquidity), address(oracleV2), authGate);
        pauseAuth = new FluidPauseAuth(
            address(mockLiquidity),
            makeAddr("vaultFactory"),
            makeAddr("dexFactory"),
            makeAddr("pauseAuthLiquidity"),
            makeAddr("pauseAuthDex"),
            address(oracleExec),
            authGate
        );

        vm.prank(TEAM_MULTISIG);
        oracleExec.setPauseAuthContract(address(pauseAuth));

        vm.prank(governance);
        oracleV2.setGuardian(address(oracleExec), true);

        vm.startPrank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(bot, 1);
        pauseAuth.setPauseAuth(manual, 2);
        pauseAuth.setPauseAuth(unpauser, 3);
        vm.stopPrank();
    }

    function test_constructor_RevertIfLiquidityZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuthOracleV2(address(0), address(oracleV2), authGate);
    }

    function test_constructor_RevertIfOracleV2Zero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuthOracleV2(address(mockLiquidity), address(0), authGate);
    }

    function test_constructor_RevertIfAuthGateZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidPauseAuthOracleV2(address(mockLiquidity), address(oracleV2), address(0));
    }

    function test_constructor_RevertIfAuthGateForOtherLiquidity() public {
        address otherAuthGate_ = deployCode(
            "contracts/config/authGate/main.sol:FluidAuthGate",
            abi.encode(makeAddr("otherLiquidity"), TEAM_MULTISIG, TEAM_MULTISIG2, makeAddr("teamTimelock"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthOracleV2__InvalidParams)
        );
        new FluidPauseAuthOracleV2(address(mockLiquidity), address(oracleV2), otherAuthGate_);
    }

    function test_constructor_SetsImmutables() public view {
        assertEq(address(oracleExec.ORACLE_V2()), address(oracleV2));
        assertEq(address(oracleExec.AUTH_GATE()), authGate);
        assertEq(address(pauseAuth.PAUSE_AUTH_ORACLE_V2()), address(oracleExec));
        assertEq(oracleExec.pauseAuthContract(), address(pauseAuth));
    }

    function test_setPauseAuthContract_RevertIfAlreadySet() public {
        address newPauseAuth_ = makeAddr("newPauseAuth");

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthOracleV2__InvalidParams)
        );
        vm.prank(TEAM_MULTISIG);
        oracleExec.setPauseAuthContract(newPauseAuth_);
    }

    function test_setPauseAuthContract_RevertIfNotMidTier() public {
        FluidPauseAuthOracleV2 fresh_ = _freshExecutor();
        address random_ = makeAddr("random");

        vm.expectRevert(Access__Unauthorized.selector);
        vm.prank(random_);
        fresh_.setPauseAuthContract(address(pauseAuth));
    }

    function test_setPauseAuthContract_RevertIfZero() public {
        FluidPauseAuthOracleV2 fresh_ = _freshExecutor();

        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        vm.prank(TEAM_MULTISIG2);
        fresh_.setPauseAuthContract(address(0));
    }

    function test_setPauseAuthContract_TeamMultisig2Sets() public {
        FluidPauseAuthOracleV2 fresh_ = _freshExecutor();

        vm.expectEmit(true, true, true, true, address(fresh_));
        emit LogSetPauseAuthContract(address(pauseAuth));
        vm.prank(TEAM_MULTISIG2);
        fresh_.setPauseAuthContract(address(pauseAuth));

        assertEq(fresh_.pauseAuthContract(), address(pauseAuth));
    }

    function test_pauseOperate_RevertIfNotPauseAuthContract() public {
        address random_ = makeAddr("random");

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthOracleV2__Unauthorized)
        );
        vm.prank(TEAM_MULTISIG);
        oracleExec.pauseOperate(_one(tokenA));

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthOracleV2__Unauthorized)
        );
        vm.prank(random_);
        oracleExec.pauseOperate(_one(tokenA));
    }

    function test_unpauseOperate_RevertIfNotPauseAuthContract() public {
        address random_ = makeAddr("random");

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthOracleV2__Unauthorized)
        );
        vm.prank(TEAM_MULTISIG);
        oracleExec.unpauseOperate(_one(tokenA));

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuthOracleV2__Unauthorized)
        );
        vm.prank(random_);
        oracleExec.unpauseOperate(_one(tokenA));
    }

    function test_pauseOperate_ReturnsActedFlags() public {
        address[] memory pause_ = new address[](3);
        pause_[0] = tokenA;
        pause_[1] = tokenA;
        pause_[2] = tokenB;

        vm.prank(address(pauseAuth));
        bool[] memory acted_ = oracleExec.pauseOperate(pause_);
        assertEq(acted_.length, 3);
        assertTrue(acted_[0]);
        assertFalse(acted_[1]);
        assertTrue(acted_[2]);

        address[] memory unpause_ = new address[](3);
        unpause_[0] = tokenA;
        unpause_[1] = tokenB;
        unpause_[2] = tokenA;

        vm.prank(address(pauseAuth));
        acted_ = oracleExec.unpauseOperate(unpause_);
        assertEq(acted_.length, 3);
        assertTrue(acted_[0]);
        assertTrue(acted_[1]);
        assertFalse(acted_[2]);
    }

    function test_pauseOperate_KeepsLiquidatePause() public {
        vm.prank(governance);
        oracleV2.setPausedState(tokenA, false, true);

        vm.prank(manual);
        pauseAuth.pauseOracleV2(_one(tokenA));
        assertTrue(_operatePaused(tokenA));
        assertTrue(_liquidatePaused(tokenA));

        vm.prank(unpauser);
        pauseAuth.unpauseOracleV2(_one(tokenA));
        assertFalse(_operatePaused(tokenA));
        assertTrue(_liquidatePaused(tokenA));
    }

    function test_pauseOracleV2_RevertIfExecutorNotGuardian() public {
        vm.prank(governance);
        oracleV2.setGuardian(address(oracleExec), false);

        vm.expectRevert(abi.encodeWithSelector(ORACLE_V2_ERROR, ORACLE_V2_UNAUTHORIZED));
        vm.prank(manual);
        pauseAuth.pauseOracleV2(_one(tokenA));
    }

    function test_pauseOracleV2_Level2Pauses() public {
        vm.expectEmit(true, true, true, true, address(pauseAuth));
        emit LogPauseOracleV2(tokenA);
        vm.expectEmit(true, true, true, true, address(pauseAuth));
        emit LogPauseOracleV2(tokenB);

        vm.prank(manual);
        pauseAuth.pauseOracleV2(_pair());

        assertTrue(_operatePaused(tokenA));
        assertTrue(_operatePaused(tokenB));
    }

    function test_pauseOracleV2_TeamMultisig2Pauses() public {
        vm.prank(TEAM_MULTISIG2);
        pauseAuth.pauseOracleV2(_one(tokenA));

        assertTrue(_operatePaused(tokenA));
    }

    function test_pauseOracleV2_RevertIfLevel1() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        vm.prank(bot);
        pauseAuth.pauseOracleV2(_one(tokenA));
    }

    function test_pauseOracleV2_RevertIfNoLevel() public {
        address random_ = makeAddr("random");

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        vm.prank(random_);
        pauseAuth.pauseOracleV2(_one(tokenA));
    }

    function test_unpauseOracleV2_Level3Unpauses() public {
        vm.prank(manual);
        pauseAuth.pauseOracleV2(_one(tokenA));

        vm.expectEmit(true, true, true, true, address(pauseAuth));
        emit LogUnpauseOracleV2(tokenA);
        vm.prank(unpauser);
        pauseAuth.unpauseOracleV2(_one(tokenA));

        assertFalse(_operatePaused(tokenA));
    }

    function test_unpauseOracleV2_RevertIfLevel2() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        vm.prank(manual);
        pauseAuth.unpauseOracleV2(_one(tokenA));
    }

    function test_unpauseOracleV2_RevertIfTeamMultisig2() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        vm.prank(TEAM_MULTISIG2);
        pauseAuth.unpauseOracleV2(_one(tokenA));
    }

    function test_unpauseOracleV2_TeamMultisigAndGovernance() public {
        vm.prank(manual);
        pauseAuth.pauseOracleV2(_one(tokenA));
        vm.prank(TEAM_MULTISIG);
        pauseAuth.unpauseOracleV2(_one(tokenA));
        assertFalse(_operatePaused(tokenA));

        vm.prank(manual);
        pauseAuth.pauseOracleV2(_one(tokenA));
        vm.prank(governance);
        pauseAuth.unpauseOracleV2(_one(tokenA));
        assertFalse(_operatePaused(tokenA));
    }

    function test_pauseOracleV2_SkipsNotPausableToken() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(tokenA, true);

        vm.expectEmit(true, true, true, true, address(pauseAuth));
        emit LogSkipTokenNotPausable(tokenA);
        vm.expectEmit(true, true, true, true, address(pauseAuth));
        emit LogPauseOracleV2(tokenB);

        vm.prank(manual);
        pauseAuth.pauseOracleV2(_pair());

        assertFalse(_operatePaused(tokenA));
        assertTrue(_operatePaused(tokenB));
    }

    function test_unpauseOracleV2_SkipsNotPausableToken() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(tokenA, true);
        vm.prank(governance);
        oracleV2.setPausedState(tokenA, true, false);

        vm.expectEmit(true, true, true, true, address(pauseAuth));
        emit LogSkipTokenNotPausable(tokenA);
        vm.prank(unpauser);
        pauseAuth.unpauseOracleV2(_one(tokenA));

        assertTrue(_operatePaused(tokenA));
    }

    function test_pauseOracleV2_TeamMultisigBypassesNotPausable() public {
        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(tokenA, true);

        vm.recordLogs();
        vm.prank(TEAM_MULTISIG);
        pauseAuth.pauseOracleV2(_one(tokenA));

        assertEq(_countLogs(SKIP_TOPIC, address(pauseAuth)), 0);
        assertTrue(_operatePaused(tokenA));
    }

    function test_pauseOracleV2_SkipsAlreadyPaused() public {
        vm.recordLogs();
        vm.prank(manual);
        pauseAuth.pauseOracleV2(_twice(tokenA));
        assertEq(_countLogs(PAUSE_TOPIC, address(pauseAuth)), 1);
        assertTrue(_operatePaused(tokenA));

        vm.recordLogs();
        vm.prank(manual);
        pauseAuth.pauseOracleV2(_one(tokenA));
        assertEq(_countLogs(PAUSE_TOPIC, address(pauseAuth)), 0);
        assertTrue(_operatePaused(tokenA));
    }

    function test_unpauseOracleV2_SkipsNotPaused() public {
        vm.recordLogs();
        vm.prank(unpauser);
        pauseAuth.unpauseOracleV2(_pair());

        assertEq(_countLogs(UNPAUSE_TOPIC, address(pauseAuth)), 0);
        assertFalse(_operatePaused(tokenA));
        assertFalse(_operatePaused(tokenB));
    }

    function test_pauseOracleV2_EmptyListIsNoop() public {
        vm.recordLogs();
        vm.prank(manual);
        pauseAuth.pauseOracleV2(new address[](0));
        assertEq(_countLogs(PAUSE_TOPIC, address(pauseAuth)), 0);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(tokenA, true);

        vm.recordLogs();
        vm.prank(manual);
        pauseAuth.pauseOracleV2(_one(tokenA));
        assertEq(_countLogs(SKIP_TOPIC, address(pauseAuth)), 1);
        assertFalse(_operatePaused(tokenA));
    }

    function test_unpauseOracleV2_EmptyListIsNoop() public {
        vm.recordLogs();
        vm.prank(unpauser);
        pauseAuth.unpauseOracleV2(new address[](0));
        assertEq(_countLogs(UNPAUSE_TOPIC, address(pauseAuth)), 0);

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setNotPausableToken(tokenA, true);
        vm.prank(governance);
        oracleV2.setPausedState(tokenA, true, false);

        vm.recordLogs();
        vm.prank(unpauser);
        pauseAuth.unpauseOracleV2(_one(tokenA));
        assertEq(_countLogs(SKIP_TOPIC, address(pauseAuth)), 1);
        assertEq(_countLogs(UNPAUSE_TOPIC, address(pauseAuth)), 0);
        assertTrue(_operatePaused(tokenA));
    }

    function test_pauseOracleV2_FollowsPauseAuthGrants() public {
        address newAuth_ = makeAddr("newAuth");

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        vm.prank(newAuth_);
        pauseAuth.pauseOracleV2(_one(tokenA));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(newAuth_, 2);
        vm.prank(newAuth_);
        pauseAuth.pauseOracleV2(_one(tokenA));
        assertTrue(_operatePaused(tokenA));

        vm.prank(TEAM_MULTISIG);
        pauseAuth.setPauseAuth(newAuth_, 0);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.PauseAuth__Unauthorized));
        vm.prank(newAuth_);
        pauseAuth.pauseOracleV2(_one(tokenB));
    }

    function _freshExecutor() internal returns (FluidPauseAuthOracleV2) {
        return new FluidPauseAuthOracleV2(address(mockLiquidity), address(oracleV2), authGate);
    }

    function _pair() internal view returns (address[] memory tokens_) {
        tokens_ = new address[](2);
        tokens_[0] = tokenA;
        tokens_[1] = tokenB;
    }

    function _one(address token_) internal pure returns (address[] memory tokens_) {
        tokens_ = new address[](1);
        tokens_[0] = token_;
    }

    function _twice(address token_) internal pure returns (address[] memory tokens_) {
        tokens_ = new address[](2);
        tokens_[0] = token_;
        tokens_[1] = token_;
    }

    function _operatePaused(address token_) internal view returns (bool operatePaused_) {
        (operatePaused_, , , ) = oracleV2.getTokenConfig(token_);
    }

    function _liquidatePaused(address token_) internal view returns (bool liquidatePaused_) {
        (, liquidatePaused_, , ) = oracleV2.getTokenConfig(token_);
    }

    function _countLogs(bytes32 topic_, address emitter_) internal returns (uint256 count_) {
        Vm.Log[] memory logs_ = vm.getRecordedLogs();
        for (uint256 i; i < logs_.length; ++i) {
            if (logs_[i].emitter == emitter_ && logs_[i].topics[0] == topic_) {
                ++count_;
            }
        }
    }
}
