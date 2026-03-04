//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { FluidDexLite } from "../../../contracts/protocols/dexLite/core/main.sol";
import { FluidDexLiteAdminModule } from "../../../contracts/protocols/dexLite/adminModule/main.sol";
import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { DexKey, TransferParams } from "../../../contracts/protocols/dexLite/other/structs.sol";
import { InitializeParams } from "../../../contracts/protocols/dexLite/adminModule/structs.sol";

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Strings } from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DexLiteUsdcUsdtTest is LiquidityBaseTest {
    using SafeERC20 for IERC20;

    FluidDexLite public dexLite;
    FluidDexLiteAdminModule public dexLiteAdminModule;

    function _toString(uint256 x) internal pure returns (string memory) {
        return Strings.toString(x);
    }

    function _toString(int256 x) internal pure returns (string memory) {
        if (x == 0) {
            return "0";
        }
        bool neg = x < 0;
        uint256 ux = neg ? uint256(-x) : uint256(x);
        string memory s = Strings.toString(ux);
        return neg ? string.concat("-", s) : s;
    }

    function setUp() public virtual override {
        super.setUp();

        // Deploy DexLite contracts
        dexLite = new FluidDexLite(address(this), address(liquidity), address(this));
        dexLiteAdminModule = new FluidDexLiteAdminModule(address(liquidity), address(this));

        // Fund this contract with tokens for testing
        deal(address(USDC), address(this), 10000 * 1e6); // 10,000 USDC
        deal(address(USDT), address(this), 10000 * 1e6); // 10,000 USDT

        // Also fund the dexLite contract for liquidity (this mimics production setup)
        deal(address(USDC), address(dexLite), 1000 * 1e6); // 1,000 USDC
        deal(address(USDT), address(dexLite), 1000 * 1e6); // 1,000 USDT
    }

    function testSetUp() public {
        assertNotEq(address(dexLite), address(0));
        assertNotEq(address(dexLiteAdminModule), address(0));
        
        // Verify token balances
        assertEq(USDC.balanceOf(address(this)), 10000 * 1e6);
        assertEq(USDT.balanceOf(address(this)), 10000 * 1e6);
    }

    function testInitializeUsdcUsdtPool() public {
        console2.log("USDC address:", address(USDC));
        console2.log("USDT address:", address(USDT));
        
        // Determine correct token ordering (token0 = smaller address, token1 = larger address)
        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        console2.log("token0 (smaller address):", token0);
        console2.log("token1 (larger address):", token1);
        
        // Create DexKey with correct token ordering
        DexKey memory dexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(0) // Zero salt for simplicity
        });

        // Initialize with 100 USDC + 100 USDT (same as production)
        uint256 token0Amount = 100 * 1e6; // 100 of token0
        uint256 token1Amount = 100 * 1e6; // 100 of token1

        // Initialize parameters matching production script
        InitializeParams memory initParams = InitializeParams({
            dexKey: dexKey,
            revenueCut: 0,
            fee: 5, // 0.05% fee (5 = 0.05% in 4 decimals)
            rebalancingStatus: false,
            centerPrice: 1e27, // 1:1 center price (1 USDC = 1 USDT)
            centerPriceContract: 0, // No external price contract
            upperPercent: 1500, // 0.15% upper range (1500 = 0.15% in 4 decimals)
            lowerPercent: 1500, // 0.15% lower range (1500 = 0.15% in 4 decimals)
            upperShiftThreshold: 0, // No shift threshold
            lowerShiftThreshold: 0, // No shift threshold
            shiftTime: 3600, // 1 hour shift time
            minCenterPrice: 1,
            maxCenterPrice: type(uint256).max,
            token0Amount: token0Amount,
            token1Amount: token1Amount
        });

        // Check initial balances
        uint256 initialUsdcBalance = USDC.balanceOf(address(this));
        uint256 initialUsdtBalance = USDT.balanceOf(address(this));
        uint256 initialPoolUsdcBalance = USDC.balanceOf(address(dexLite));
        uint256 initialPoolUsdtBalance = USDT.balanceOf(address(dexLite));

        console2.log("=== INITIALIZATION ===");
        console2.log("Initial this USDC balance:", _toString(initialUsdcBalance / 1e6), "USDC");
        console2.log("Initial this USDT balance:", _toString(initialUsdtBalance / 1e6), "USDT");
        console2.log("Initial pool USDC balance:", _toString(initialPoolUsdcBalance / 1e6), "USDC");
        console2.log("Initial pool USDT balance:", _toString(initialPoolUsdtBalance / 1e6), "USDT");

        // Approve tokens for DexLite contract (based on actual token ordering)
        if (token0 == address(USDC)) {
            USDC.approve(address(dexLite), token0Amount);
            USDT.approve(address(dexLite), token1Amount);
        } else {
            USDT.approve(address(dexLite), token0Amount);
            USDC.approve(address(dexLite), token1Amount);
        }

        // Encode the initialize function call
        bytes memory initializeData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.initialize.selector,
            initParams
        );

        // Encode the fallback data (target address + spell data)
        bytes memory fallbackData = abi.encode(address(dexLiteAdminModule), initializeData);

        // Call the fallback function to delegate call initialize
        (bool success, ) = address(dexLite).call(fallbackData);
        require(success, "Initialize failed");

        // Verify the initialization worked
        assertTrue(success, "USDC/USDT Dex initialization should succeed");

        // Check final balances after initialization
        uint256 finalUsdcBalance = USDC.balanceOf(address(this));
        uint256 finalUsdtBalance = USDT.balanceOf(address(this));
        uint256 finalPoolUsdcBalance = USDC.balanceOf(address(dexLite));
        uint256 finalPoolUsdtBalance = USDT.balanceOf(address(dexLite));

        console2.log("Final this USDC balance:", _toString(finalUsdcBalance / 1e6), "USDC");
        console2.log("Final this USDT balance:", _toString(finalUsdtBalance / 1e6), "USDT");
        console2.log("Final pool USDC balance:", _toString(finalPoolUsdcBalance / 1e6), "USDC");
        console2.log("Final pool USDT balance:", _toString(finalPoolUsdtBalance / 1e6), "USDT");

        // Verify tokens were transferred correctly
        assertEq(finalUsdcBalance, initialUsdcBalance - token0Amount, "USDC should be deducted from this contract");
        assertEq(finalUsdtBalance, initialUsdtBalance - token1Amount, "USDT should be deducted from this contract");
        assertEq(finalPoolUsdcBalance, initialPoolUsdcBalance + token0Amount, "USDC should be added to pool");
        assertEq(finalPoolUsdtBalance, initialPoolUsdtBalance + token1Amount, "USDT should be added to pool");
    }

    struct TestSwapUsdcUsdt {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialUsdtBalance;
        uint256 initialPoolUsdcBalance;
        uint256 initialPoolUsdtBalance;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut;
        uint256 finalUsdcBalance;
        uint256 finalUsdtBalance;
        uint256 finalPoolUsdcBalance;
        uint256 finalPoolUsdtBalance;
        uint256 usdcSpent;
        uint256 usdtReceived;
        uint256 exchangeRate;
        uint256 gasUsed;
    }

    function testSwapUsdcToUsdt() public {
        // First initialize the pool
        testInitializeUsdcUsdtPool();

        console2.log("\n=== SWAP TEST ===");

        TestSwapUsdcUsdt memory v_;

        // Determine correct token ordering (same as initialization)
        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        // Create DexKey with correct token ordering
        DexKey memory dexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(0) // Zero salt for simplicity
        });

        // Swap amount: 1 USDC (same as production script)
        v_.swapAmount = 1 * 1e6; // 1 USDC

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialUsdtBalance = USDT.balanceOf(address(this));
        v_.initialPoolUsdcBalance = USDC.balanceOf(address(dexLite));
        v_.initialPoolUsdtBalance = USDT.balanceOf(address(dexLite));

        console2.log("Before swap this USDC balance:", _toString(v_.initialUsdcBalance / 1e6), "USDC");
        console2.log("Before swap this USDT balance:", _toString(v_.initialUsdtBalance / 1e6), "USDT");
        console2.log("Before swap pool USDC balance:", _toString(v_.initialPoolUsdcBalance / 1e6), "USDC");
        console2.log("Before swap pool USDT balance:", _toString(v_.initialPoolUsdtBalance / 1e6), "USDT");

        // Verify sufficient USDC balance
        assertGe(v_.initialUsdcBalance, v_.swapAmount, "Should have enough USDC for swap");

        // Set up swap parameters - determine swap direction for USDC -> USDT
        v_.swap0To1 = (token0 == address(USDC)); // If USDC is token0, then USDC->USDT is swap0To1=true
        v_.amountSpecified = int256(v_.swapAmount); // Positive for exact input
        v_.amountLimit = 0; // Minimum USDT to receive (0 for testing)
        v_.to = address(this); // Receive USDT to this address
        v_.isCallback = false; // No callback needed for ERC20 tokens
        v_.callbackData = ""; // Empty callback data
        v_.extraData = ""; // Empty extra data

        // Approve USDC for DexLite contract
        USDC.approve(address(dexLite), v_.swapAmount);

        console2.log("Swapping 1 USDC for USDT...");
        console2.log("Swap direction (swap0To1):", v_.swap0To1);

        // Measure gas consumption for the swap
        uint256 gasBefore = gasleft();
        
        // Perform the swap
        v_.amountOut = dexLite.swapSingle(
            dexKey,
            v_.swap0To1,
            v_.amountSpecified,
            v_.amountLimit,
            v_.to,
            v_.isCallback,
            v_.callbackData,
            v_.extraData
        );
        
        uint256 gasAfter = gasleft();
        v_.gasUsed = gasBefore - gasAfter;
        
        console2.log("Gas used for swap:", _toString(v_.gasUsed));

        // Get final balances
        v_.finalUsdcBalance = USDC.balanceOf(address(this));
        v_.finalUsdtBalance = USDT.balanceOf(address(this));
        v_.finalPoolUsdcBalance = USDC.balanceOf(address(dexLite));
        v_.finalPoolUsdtBalance = USDT.balanceOf(address(dexLite));

        console2.log("After swap this USDC balance:", _toString(v_.finalUsdcBalance / 1e6), "USDC");
        console2.log("After swap this USDT balance:", _toString(v_.finalUsdtBalance / 1e6), "USDT");
        console2.log("After swap pool USDC balance:", _toString(v_.finalPoolUsdcBalance / 1e6), "USDC");
        console2.log("After swap pool USDT balance:", _toString(v_.finalPoolUsdtBalance / 1e6), "USDT");

        // Calculate actual amounts
        v_.usdcSpent = v_.initialUsdcBalance - v_.finalUsdcBalance;
        v_.usdtReceived = v_.finalUsdtBalance - v_.initialUsdtBalance;

        console2.log("USDC spent:", _toString(v_.usdcSpent), "wei");
        console2.log("USDT received:", _toString(v_.usdtReceived), "wei"); 
        console2.log("Contract returned amountOut:", _toString(v_.amountOut), "wei");

        // Verify the swap results
        assertEq(v_.usdcSpent, v_.swapAmount, "Should spend exactly the swap amount of USDC");
        assertGt(v_.usdtReceived, 0, "Should receive some USDT");
        assertEq(v_.usdtReceived, v_.amountOut, "USDT received should match contract return value");

        // Verify pool balances changed correctly
        assertEq(v_.finalPoolUsdcBalance, v_.initialPoolUsdcBalance + v_.swapAmount, "Pool should gain USDC");
        assertEq(v_.finalPoolUsdtBalance, v_.initialPoolUsdtBalance - v_.amountOut, "Pool should lose USDT");

        // Calculate exchange rate (should be close to 1:1 for stablecoins)
        if (v_.usdcSpent > 0) {
            v_.exchangeRate = (v_.usdtReceived * 1e6) / v_.usdcSpent; // Rate with 6 decimal precision
            console2.log("Exchange rate (scaled by 1e6):", _toString(v_.exchangeRate));
            
            // For stablecoins with 0.05% fee, we expect rate close to 0.9995 (99.95%)
            assertGe(v_.exchangeRate, 990000, "Exchange rate should be at least 0.99 (accounting for fees)");
            assertLe(v_.exchangeRate, 1010000, "Exchange rate should be at most 1.01");
        }

        console2.log("=== SWAP COMPLETED SUCCESSFULLY ===");
    }
} 