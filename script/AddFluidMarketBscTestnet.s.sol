// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { FluidLiquidityAdminModule, AuthModule } from "../contracts/liquidity/adminModule/main.sol";
import { Structs as AdminModuleStructs } from "../contracts/liquidity/adminModule/structs.sol";
import { FluidLendingFactory } from "../contracts/protocols/lending/lendingFactory/main.sol";
import { fToken } from "../contracts/protocols/lending/fToken/main.sol";
import { IFToken } from "../contracts/protocols/lending/interfaces/iFToken.sol";
import { FluidLendingResolver } from "../contracts/periphery/resolvers/lending/main.sol";

/// @dev Only what the optional smoke deposit needs from a faucet-style test ERC20 (e.g. USDC/USDT
///      expose `allocateTo`). Leave SMOKE_DEPOSIT=0 for tokens without a public faucet (e.g. WBNB).
interface IFaucetERC20 {
    function allocateTo(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

/**
 * @title AddFluidMarketBscTestnet
 * @notice Adds ONE new Fluid fToken market for any ERC20 asset to the ALREADY-DEPLOYED Fluid core on
 *         bsctestnet, reusing the shared Liquidity layer + LendingFactory + LendingResolver. This is
 *         the per-asset script QA runs to spin up each Flux "pool" (fUSDC, fWBNB, fU, ...). Every
 *         fToken lands under the single resolver the hub's AdapterFlux reads, so one hub adapter
 *         serves them all.
 * @dev MUST be run with the deployer key that OWNS the core (Liquidity governance + factory owner),
 *      because listing the asset and the supply config are governance-gated. Core addresses are read
 *      from the JSON that DeployFluidLendingBscTestnet wrote.
 *
 *      Run:
 *        DEPLOYER_PRIVATE_KEY=0x... UNDERLYING=0x<token> MARKET_LABEL=USDC \
 *          forge script script/AddFluidMarketBscTestnet.s.sol:AddFluidMarketBscTestnet \
 *          --rpc-url https://bsc-testnet-rpc.publicnode.com --broadcast --slow
 *
 *      Env flags:
 *        DEPLOYER_PRIVATE_KEY  (required) MUST equal the core owner/governance.
 *        UNDERLYING            (required) ERC20 asset to create an fToken for.
 *        FLUID_CORE            (optional) core JSON path; default ./deployments/bsctestnet-fluid-lending.json.
 *        MARKET_LABEL          (optional) label used in the output filename; default = the token address.
 *        SMOKE_DEPOSIT         (optional) whole tokens to allocateTo + deposit as a check; default 0 (skip).
 *                              Only works for allocateTo faucet tokens; leave 0 for WBNB and non-faucet tokens.
 */
contract AddFluidMarketBscTestnet is Script {
    // Same Fluid test defaults as the core deploy — asset-agnostic (percentages, not amounts).
    uint256 internal constant KINK = 8_000; // 80%
    uint256 internal constant RATE_AT_ZERO = 400; // 4%
    uint256 internal constant RATE_AT_KINK = 1_000; // 10%
    uint256 internal constant RATE_AT_MAX = 15_000; // 150%
    uint8 internal constant SUPPLY_MODE = 1; // with interest
    uint256 internal constant EXPAND_PERCENT = 2_000; // 20%
    uint256 internal constant EXPAND_DURATION = 2 days;
    uint256 internal constant BASE_WITHDRAWAL_LIMIT = 100_000 ether;

    struct Core {
        address liquidity;
        address lendingFactory;
        address lendingResolver;
    }

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address underlying = vm.envAddress("UNDERLYING");
        uint256 smoke = vm.envOr("SMOKE_DEPOSIT", uint256(0));

        Core memory c = _readCore();
        console2.log("Core liquidity: ", c.liquidity);
        console2.log("Core factory:   ", c.lendingFactory);
        console2.log("New underlying: ", underlying);

        vm.startBroadcast(pk);
        address fTokenAddr = _addMarket(c, underlying);
        if (smoke > 0) _smoke(underlying, fTokenAddr, deployer, smoke);
        vm.stopBroadcast();

        // Sanity: the fToken wraps exactly this underlying, and the SHARED resolver can read it
        // (this getFTokenDetails call is exactly what the hub's AdapterFlux performs).
        require(fToken(fTokenAddr).asset() == underlying, "fToken asset() != underlying");
        FluidLendingResolver(c.lendingResolver).getFTokenDetails(IFToken(fTokenAddr));

        _persist(underlying, fTokenAddr, c);
    }

    function _readCore() internal view returns (Core memory c) {
        string memory path = vm.envOr("FLUID_CORE", string("./deployments/bsctestnet-fluid-lending.json"));
        string memory j = vm.readFile(path);
        c.liquidity = vm.parseJsonAddress(j, ".liquidity");
        c.lendingFactory = vm.parseJsonAddress(j, ".lendingFactory");
        c.lendingResolver = vm.parseJsonAddress(j, ".lendingResolver");
    }

    function _addMarket(Core memory c, address underlying) internal returns (address fTokenAddr) {
        // List the asset on Liquidity: interest-rate curve + token config.
        AdminModuleStructs.RateDataV1Params[] memory rd = new AdminModuleStructs.RateDataV1Params[](1);
        rd[0] = AdminModuleStructs.RateDataV1Params(underlying, KINK, RATE_AT_ZERO, RATE_AT_KINK, RATE_AT_MAX);
        AuthModule(c.liquidity).updateRateDataV1s(rd);

        AdminModuleStructs.TokenConfig[] memory tc = new AdminModuleStructs.TokenConfig[](1);
        tc[0] = AdminModuleStructs.TokenConfig({ token: underlying, fee: 0, threshold: 0, maxUtilization: 10_000 });
        FluidLiquidityAdminModule(c.liquidity).updateTokenConfigs(tc);

        // Ensure the fToken creation code is set on the factory (idempotent) and create the fToken.
        FluidLendingFactory(c.lendingFactory).setFTokenCreationCode("fToken", type(fToken).creationCode);
        fTokenAddr = FluidLendingFactory(c.lendingFactory).createToken(underlying, "fToken", false);

        // Authorize the fToken to supply the underlying into Liquidity (else deposits revert).
        AdminModuleStructs.UserSupplyConfig[] memory sc = new AdminModuleStructs.UserSupplyConfig[](1);
        sc[0] = AdminModuleStructs.UserSupplyConfig({
            user: fTokenAddr,
            token: underlying,
            mode: SUPPLY_MODE,
            expandPercent: EXPAND_PERCENT,
            expandDuration: EXPAND_DURATION,
            baseWithdrawalLimit: BASE_WITHDRAWAL_LIMIT
        });
        FluidLiquidityAdminModule(c.liquidity).updateUserSupplyConfigs(sc);
    }

    function _smoke(address underlying, address fTokenAddr, address deployer, uint256 smoke) internal {
        uint256 amount = smoke * (10 ** IFaucetERC20(underlying).decimals());
        IFaucetERC20(underlying).allocateTo(deployer, amount);
        IFaucetERC20(underlying).approve(fTokenAddr, amount);
        uint256 shares = fToken(fTokenAddr).deposit(amount, deployer);
        require(shares > 0, "smoke deposit minted no shares");
        console2.log(string.concat("smoke deposit (raw): ", vm.toString(amount)));
        console2.log(string.concat("fToken shares:       ", vm.toString(shares)));
    }

    function _persist(address underlying, address fTokenAddr, Core memory c) internal {
        string memory label = vm.envOr("MARKET_LABEL", vm.toString(underlying));
        string memory outPath = string.concat("./deployments/bsctestnet-fluid-market-", label, ".json");
        string memory json = "market";
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeAddress(json, "underlying", underlying);
        vm.serializeAddress(json, "liquidity", c.liquidity);
        vm.serializeAddress(json, "lendingFactory", c.lendingFactory);
        vm.serializeAddress(json, "lendingResolver", c.lendingResolver);
        string memory finalJson = vm.serializeAddress(json, "fToken", fTokenAddr);
        vm.writeJson(finalJson, outPath);

        console2.log("");
        console2.log("=== new Fluid market ===");
        console2.log("fToken (Flux resource):   ", fTokenAddr);
        console2.log("LendingResolver (shared): ", c.lendingResolver);
        console2.log("saved ->", outPath);
    }
}
