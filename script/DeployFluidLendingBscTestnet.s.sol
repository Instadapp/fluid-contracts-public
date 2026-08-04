// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { FluidLiquidityProxy } from "../contracts/liquidity/proxy.sol";
import { FluidLiquidityUserModule } from "../contracts/liquidity/userModule/main.sol";
import { FluidLiquidityUserModuleOthers } from "../contracts/liquidity/userModule/mainOthers.sol";
import {
    FluidLiquidityAdminModule,
    AuthModule,
    GuardianModule,
    GovernanceModule
} from "../contracts/liquidity/adminModule/main.sol";
import { FluidLiquidityAdminModuleOthers } from "../contracts/liquidity/adminModule/mainOthers.sol";
import { Structs as AdminModuleStructs } from "../contracts/liquidity/adminModule/structs.sol";
import { IFluidLiquidity } from "../contracts/liquidity/interfaces/iLiquidity.sol";

import { FluidLiquidityResolver } from "../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidityResolver } from "../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";

import { FluidLendingFactory } from "../contracts/protocols/lending/lendingFactory/main.sol";
import { IFluidLendingFactory } from "../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { fToken } from "../contracts/protocols/lending/fToken/main.sol";
import { FluidLendingResolver } from "../contracts/periphery/resolvers/lending/main.sol";

/// @dev Local mirror of the test's `IVariables`, only needed for the `revenueCollector()` selector
///      registered on the admin module (matches liquidityBaseTest.t.sol exactly).
interface IVariables {
    function revenueCollector() external view returns (address);
}

/// @dev The bsctestnet USDT is a Centre-style faucet token (6 decimals): mint via `allocateTo`, no
///      access control. Only the members needed by the smoke test are declared.
interface IFaucetUSDT {
    function allocateTo(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/**
 * @title DeployFluidLendingBscTestnet
 * @notice Stands up a REAL, standalone Fluid lending market (single fUSDT market) on bsctestnet for
 *         QA of the venus-liquidity-hub Flux family, faucets USDT to the deployer, runs a live
 *         deposit smoke test, and writes every deployed address to a JSON file.
 * @dev The deploy sequence mirrors Fluid's own foundry setUp — `test/foundry/liquidity/liquidityBaseTest.t.sol`
 *      (Liquidity layer) + `test/foundry/lending/fToken.t.sol` (fToken) — with the BSC module variants
 *      (`*Others`) and constructor args taken verbatim from `deployments/bnb/`. The deployer EOA becomes
 *      Liquidity governance, LendingFactory owner, and fToken auth.
 *
 *      Run:
 *        DEPLOYER_PRIVATE_KEY=0x... forge script script/DeployFluidLendingBscTestnet.s.sol:DeployFluidLendingBscTestnet \
 *          --rpc-url https://bsc-testnet-rpc.publicnode.com --broadcast
 *
 *      Env flags:
 *        DEPLOYER_PRIVATE_KEY  (required) deployer key; becomes admin/owner of the whole stack.
 *        UNDERLYING            (optional) underlying token; default = the hub's bsctestnet USDT.
 *        SMOKE_DEPOSIT_USDT    (optional) whole USDT to faucet + deposit as a smoke test; default 1000; 0 = skip.
 *        DEPLOY_OUT            (optional) output JSON path; default ./deployments/bsctestnet-fluid-lending.json.
 *
 *      Deployed addresses are persisted to DEPLOY_OUT (and, on --broadcast, also to
 *      broadcast/DeployFluidLendingBscTestnet.s.sol/97/run-latest.json by forge itself).
 */
contract DeployFluidLendingBscTestnet is Script {
    /// @dev bsctestnet USDT used by the hub's `Hub_USDT` (deploy/config/bsctestnet.json -> assets[0].asset).
    address internal constant DEFAULT_UNDERLYING = 0xA11c8D9DC9b66E209Ef60F0C8D969D3CD988782c;

    /// @dev Native-token max borrow cap for the admin module. 1.5e26, verbatim from bnb AdminModule args.
    uint256 internal constant NATIVE_MAX_BORROW_CAP = 150_000_000 ether;

    // Interest-rate curve (1e2 precision: 100% = 10_000). Fluid test defaults.
    uint256 internal constant KINK = 8_000; // 80%
    uint256 internal constant RATE_AT_ZERO = 400; // 4%
    uint256 internal constant RATE_AT_KINK = 1_000; // 10%
    uint256 internal constant RATE_AT_MAX = 15_000; // 150%

    // fToken -> Liquidity supply config. Fluid test defaults (test USDT is also 6-decimal); without
    // this, deposits revert at Liquidity, not at the fToken.
    uint8 internal constant SUPPLY_MODE = 1; // with interest
    uint256 internal constant EXPAND_PERCENT = 2_000; // 20%
    uint256 internal constant EXPAND_DURATION = 2 days;
    uint256 internal constant BASE_WITHDRAWAL_LIMIT = 100_000 ether;

    // Addresses captured for the JSON dump.
    struct Deployed {
        address liquidity;
        address userModule;
        address adminModule;
        address liquidityResolver;
        address lendingFactory;
        address fToken;
        address lendingResolver;
    }

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address underlying = vm.envOr("UNDERLYING", DEFAULT_UNDERLYING);
        uint256 smokeUsdt = vm.envOr("SMOKE_DEPOSIT_USDT", uint256(1000));
        string memory outPath = vm.envOr("DEPLOY_OUT", string("./deployments/bsctestnet-fluid-lending.json"));

        console2.log("Deployer / admin / owner:", deployer);
        console2.log("Underlying (USDT):       ", underlying);

        vm.startBroadcast(pk);
        Deployed memory d = _deploy(deployer, underlying);
        if (smokeUsdt > 0) _smoke(underlying, d.fToken, deployer, smokeUsdt);
        vm.stopBroadcast();

        // Sanity: the fToken must wrap exactly the configured underlying, or the hub adapter rejects it.
        require(fToken(d.fToken).asset() == underlying, "fToken asset() != underlying");

        _persist(outPath, deployer, underlying, d);
        _report(outPath, d, smokeUsdt > 0 ? fToken(d.fToken).balanceOf(deployer) : 0);
    }

    /// @dev Phases 1-4 in an isolated stack frame (keeps run() below the stack-too-deep threshold).
    function _deploy(address deployer, address underlying) internal returns (Deployed memory d) {
        // Phase 1: Liquidity core
        FluidLiquidityProxy liquidity = new FluidLiquidityProxy(deployer, address(0));
        d.liquidity = address(liquidity);
        d.userModule = address(new FluidLiquidityUserModuleOthers());
        d.adminModule = address(new FluidLiquidityAdminModuleOthers(NATIVE_MAX_BORROW_CAP));
        d.liquidityResolver = address(new FluidLiquidityResolver(IFluidLiquidity(d.liquidity)));

        liquidity.addImplementation(d.adminModule, _adminSigs());
        liquidity.addImplementation(d.userModule, _userSigs());

        // Phase 2: list the underlying on Liquidity (rate curve + token config)
        _setRateData(d.liquidity, underlying);
        _setTokenConfig(d.liquidity, underlying);

        // Phase 3: lending factory + fToken
        FluidLendingFactory factory = new FluidLendingFactory(IFluidLiquidity(d.liquidity), deployer);
        d.lendingFactory = address(factory);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        d.fToken = factory.createToken(underlying, "fToken", false);

        // Authorize the fToken as a supplier into Liquidity (else deposits revert at Liquidity).
        _setFTokenSupplyConfig(d.liquidity, underlying, d.fToken);

        // Phase 4: lending resolver (the contract AdapterFlux reads for spot APY)
        d.lendingResolver = address(
            new FluidLendingResolver(
                IFluidLendingFactory(d.lendingFactory),
                IFluidLiquidityResolver(d.liquidityResolver)
            )
        );
    }

    /// @dev Faucet USDT to the deployer and deposit into the fToken (exercises the real supply path
    ///      that AdapterFlux uses: approve -> deposit -> Liquidity pulls via liquidityCallback).
    function _smoke(address underlying, address fTokenAddr, address deployer, uint256 smokeUsdt) internal {
        uint256 amount = smokeUsdt * (10 ** IFaucetUSDT(underlying).decimals());
        IFaucetUSDT(underlying).allocateTo(deployer, amount);
        IFaucetUSDT(underlying).approve(fTokenAddr, amount);
        uint256 shares = fToken(fTokenAddr).deposit(amount, deployer);
        require(shares > 0, "smoke deposit minted no shares");
        // console2.log(string, uint256) silently no-ops under foundry-zksync; concat instead.
        console2.log(string.concat("Smoke deposit USDT (raw): ", vm.toString(amount)));
        console2.log(string.concat("fUSDT shares minted:      ", vm.toString(shares)));
    }

    // ─────────────────────────────── persistence ───────────────────────────────

    /// @dev Write every deployed address to a single JSON file (name -> address map).
    function _persist(string memory outPath, address deployer, address underlying, Deployed memory d) internal {
        string memory json = "fluid-bsctestnet";
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeAddress(json, "deployer", deployer);
        vm.serializeAddress(json, "underlying", underlying);
        vm.serializeAddress(json, "liquidity", d.liquidity);
        vm.serializeAddress(json, "userModule", d.userModule);
        vm.serializeAddress(json, "adminModule", d.adminModule);
        vm.serializeAddress(json, "liquidityResolver", d.liquidityResolver);
        vm.serializeAddress(json, "lendingFactory", d.lendingFactory);
        vm.serializeAddress(json, "fToken", d.fToken);
        string memory finalJson = vm.serializeAddress(json, "lendingResolver", d.lendingResolver);
        vm.writeJson(finalJson, outPath);
    }

    function _report(string memory outPath, Deployed memory d, uint256 deployerShares) internal view {
        console2.log("");
        console2.log("=== Fluid lending (bsctestnet) deployed ===");
        console2.log("Liquidity (proxy):  ", d.liquidity);
        console2.log("UserModule:         ", d.userModule);
        console2.log("AdminModule:        ", d.adminModule);
        console2.log("LiquidityResolver:  ", d.liquidityResolver);
        console2.log("LendingFactory:     ", d.lendingFactory);
        console2.log("fUSDT (fToken):     ", d.fToken);
        console2.log("LendingResolver:    ", d.lendingResolver);
        console2.log(string.concat("deployer fUSDT bal: ", vm.toString(deployerShares)));
        console2.log("saved ->", outPath);
        console2.log("");
        console2.log("--- next: hub wiring (venus-liquidity-hub) ---");
        console2.log("bsctestnet.json fluxLendingResolver =", d.lendingResolver);
        console2.log("register Flux resource =", d.fToken);
    }

    // ─────────────────────────────── helpers ───────────────────────────────────

    /// @dev Admin-module selectors registered on the InfiniteProxy. Verbatim from liquidityBaseTest.t.sol.
    function _adminSigs() internal pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](16);
        sigs[0] = AuthModule.updateRateDataV1s.selector;
        sigs[1] = AuthModule.updateRateDataV2s.selector;
        sigs[2] = GovernanceModule.updateAuths.selector;
        sigs[3] = GovernanceModule.updateRevenueCollector.selector;
        sigs[4] = GovernanceModule.updateGuardians.selector;
        sigs[5] = IVariables.revenueCollector.selector;
        sigs[6] = AuthModule.collectRevenue.selector;
        sigs[7] = AuthModule.updateTokenConfigs.selector;
        sigs[8] = AuthModule.updateUserWithdrawalLimit.selector;
        sigs[9] = AuthModule.updateUserSupplyConfigs.selector;
        sigs[10] = AuthModule.updateUserBorrowConfigs.selector;
        sigs[11] = AuthModule.updateUserClasses.selector;
        sigs[12] = AuthModule.changeStatus.selector;
        sigs[13] = GuardianModule.pauseUser.selector;
        sigs[14] = GuardianModule.unpauseUser.selector;
        sigs[15] = FluidLiquidityAdminModule.updateExchangePrices.selector;
    }

    /// @dev User-module selectors: just `operate` (all supply/withdraw flows go through it).
    function _userSigs() internal pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](1);
        sigs[0] = FluidLiquidityUserModule.operate.selector;
    }

    function _setRateData(address liquidity, address token) internal {
        AdminModuleStructs.RateDataV1Params[] memory rd = new AdminModuleStructs.RateDataV1Params[](1);
        rd[0] = AdminModuleStructs.RateDataV1Params(token, KINK, RATE_AT_ZERO, RATE_AT_KINK, RATE_AT_MAX);
        AuthModule(liquidity).updateRateDataV1s(rd);
    }

    function _setTokenConfig(address liquidity, address token) internal {
        AdminModuleStructs.TokenConfig[] memory tc = new AdminModuleStructs.TokenConfig[](1);
        tc[0] = AdminModuleStructs.TokenConfig({ token: token, fee: 0, threshold: 0, maxUtilization: 10_000 });
        FluidLiquidityAdminModule(liquidity).updateTokenConfigs(tc);
    }

    function _setFTokenSupplyConfig(address liquidity, address token, address fTokenAddr) internal {
        AdminModuleStructs.UserSupplyConfig[] memory sc = new AdminModuleStructs.UserSupplyConfig[](1);
        sc[0] = AdminModuleStructs.UserSupplyConfig({
            user: fTokenAddr,
            token: token,
            mode: SUPPLY_MODE,
            expandPercent: EXPAND_PERCENT,
            expandDuration: EXPAND_DURATION,
            baseWithdrawalLimit: BASE_WITHDRAWAL_LIMIT
        });
        FluidLiquidityAdminModule(liquidity).updateUserSupplyConfigs(sc);
    }
}
