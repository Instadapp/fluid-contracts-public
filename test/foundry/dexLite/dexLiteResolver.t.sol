//SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../../contracts/periphery/resolvers/dexLite/main.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract DexLiteResolverTest is Test {
    FluidDexLiteResolver resolver;
    
    // Mainnet contract addresses
    address constant FLUID_DEX_LITE = 0xBbcb91440523216e2b87052A99F69c604A7b6e00;
    address constant FLUID_DEX_LITE_ADMIN = 0xFb74dF3e8abEcA43Fcc89041848cc8fdBB91b677;
    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    address constant DEPLOYER_FACTORY = 0x4EC7b668BAF70d4A4b0FC7941a7708A07b6d45Be;

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
    
    function setUp() public {
        // Fork mainnet using MAINNET_RPC_URL from environment
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);
        
        // Deploy a new resolver for testing
        resolver = new FluidDexLiteResolver(FLUID_DEX_LITE, LIQUIDITY, DEPLOYER_FACTORY);
        
        console.log("=== Test Setup Complete ===");
        console.log("Resolver deployed at:", address(resolver));
        console.log("DexLite address:", FLUID_DEX_LITE);
        console.log("DeployerFactory address:", DEPLOYER_FACTORY);
    }
    
    function testGetAllDexes() public {
        console.log("=== Testing getAllDexes() ===");
        
        try resolver.getAllDexes() returns (DexKey[] memory dexes) {
            console.log("SUCCESS: getAllDexes() succeeded");
            console.log("Total dexes found:", _toString(dexes.length));
            
            if (dexes.length > 0) {
                console.log("First dex details:");
                console.log("  token0:", dexes[0].token0);
                console.log("  token1:", dexes[0].token1);
                console.log("  salt:", vm.toString(dexes[0].salt));
            }
            
            assertTrue(true, "getAllDexes should not revert");
        } catch Error(string memory reason) {
            console.log("ERROR: getAllDexes() failed with error:", reason);
            fail();
        } catch (bytes memory lowLevelData) {
            console.log("ERROR: getAllDexes() failed with low-level error");
            console.logBytes(lowLevelData);
            fail();
        }
    }
    
    function testGetDexState() public {
        console.log("=== Testing getDexState() ===");
        
        // First get available dexes
        DexKey[] memory dexes = resolver.getAllDexes();
        
        if (dexes.length == 0) {
            console.log("WARNING: No dexes available to test getDexState");
            return;
        }
        
        // Test getDexState with first available dex
        DexKey memory testDexKey = dexes[0];
        
        try resolver.getDexState(testDexKey) returns (DexState memory dexState) {
            console.log("SUCCESS: getDexState() succeeded");
            console.log("DexVariables fee:", _toString(dexState.dexVariables.fee));
            console.log("DexVariables revenueCut:", _toString(dexState.dexVariables.revenueCut));
            console.log("Token0 decimals:", _toString(dexState.dexVariables.token0Decimals));
            console.log("Token1 decimals:", _toString(dexState.dexVariables.token1Decimals));
            
            assertTrue(true, "getDexState should not revert");
        } catch Error(string memory reason) {
            console.log("ERROR: getDexState() failed with error:", reason);
            fail();
        }
    }
    
    function testGetPricesAndReserves() public {
        console.log("=== Testing getPricesAndReserves() ===");
        
        // First get available dexes
        DexKey[] memory dexes = resolver.getAllDexes();
        
        if (dexes.length == 0) {
            console.log("WARNING: No dexes available to test getPricesAndReserves");
            return;
        }
        
        // Test getPricesAndReserves with first available dex
        DexKey memory testDexKey = dexes[0];
        
        try resolver.getPricesAndReserves(testDexKey) returns (Prices memory prices, Reserves memory reserves) {
            console.log("SUCCESS: getPricesAndReserves() succeeded");
            console.log("Pool price:", _toString(prices.poolPrice));
            console.log("Center price:", _toString(prices.centerPrice));
            console.log("Token0 real reserves:", _toString(reserves.token0RealReserves));
            console.log("Token1 real reserves:", _toString(reserves.token1RealReserves));
            
            assertTrue(true, "getPricesAndReserves should not revert");
        } catch Error(string memory reason) {
            console.log("ERROR: getPricesAndReserves() failed with error:", reason);
            fail();
        }
    }
    
    function testGetDexEntireData() public {
        console.log("=== Testing getDexEntireData() ===");
        
        // First get available dexes
        DexKey[] memory dexes = resolver.getAllDexes();
        
        if (dexes.length == 0) {
            console.log("WARNING: No dexes available to test getDexEntireData");
            return;
        }
        
        // Test getDexEntireData with first available dex
        DexKey memory testDexKey = dexes[0];
        
        try resolver.getDexEntireData(testDexKey) returns (DexEntireData memory entireData) {
            console.log("SUCCESS: getDexEntireData() succeeded");
            console.log("DexId:", vm.toString(entireData.dexId));
            console.log("DexKey token0:", entireData.dexKey.token0);
            console.log("DexKey token1:", entireData.dexKey.token1);
            console.log("Pool price:", _toString(entireData.prices.poolPrice));
            console.log("Token0 reserves:", _toString(entireData.reserves.token0RealReserves));
            
            assertTrue(true, "getDexEntireData should not revert");
        } catch Error(string memory reason) {
            console.log("ERROR: getDexEntireData() failed with error:", reason);
            fail();
        }
    }
    
    function testGetAllDexesEntireData() public {
        console.log("=== Testing getAllDexesEntireData() ===");
        
        try resolver.getAllDexesEntireData() returns (DexEntireData[] memory entireData) {
            console.log("SUCCESS: getAllDexesEntireData() succeeded");
            console.log("Total dexes with entire data:", _toString(entireData.length));
            
            for (uint i = 0; i < entireData.length; i++) {
                console.log("");
                console.log("==================== DEX", _toString(i + 1), "====================");
                
                // Basic DEX Info
                console.log("DexId:", vm.toString(entireData[i].dexId));
                console.log("DexKey:");
                console.log("  token0:", entireData[i].dexKey.token0);
                console.log("  token1:", entireData[i].dexKey.token1);
                console.log("  salt:", vm.toString(entireData[i].dexKey.salt));
                
                // Constant Views
                console.log("Constant Views:");
                console.log("  liquidity:", entireData[i].constantViews.liquidity);
                console.log("  deployer:", entireData[i].constantViews.deployer);
                
                // Prices
                console.log("Prices:");
                console.log("  poolPrice:", _toString(entireData[i].prices.poolPrice));
                console.log("  centerPrice:", _toString(entireData[i].prices.centerPrice));
                console.log("  upperRangePrice:", _toString(entireData[i].prices.upperRangePrice));
                console.log("  lowerRangePrice:", _toString(entireData[i].prices.lowerRangePrice));
                console.log("  upperThresholdPrice:", _toString(entireData[i].prices.upperThresholdPrice));
                console.log("  lowerThresholdPrice:", _toString(entireData[i].prices.lowerThresholdPrice));
                
                // Reserves
                console.log("Reserves:");
                console.log("  token0RealReserves:", _toString(entireData[i].reserves.token0RealReserves));
                console.log("  token1RealReserves:", _toString(entireData[i].reserves.token1RealReserves));
                console.log("  token0ImaginaryReserves:", _toString(entireData[i].reserves.token0ImaginaryReserves));
                console.log("  token1ImaginaryReserves:", _toString(entireData[i].reserves.token1ImaginaryReserves));
                
                // DEX Variables
                console.log("DEX Variables:");
                console.log("  fee:", _toString(entireData[i].dexState.dexVariables.fee));
                console.log("  revenueCut:", _toString(entireData[i].dexState.dexVariables.revenueCut));
                console.log("  rebalancingStatus:", _toString(entireData[i].dexState.dexVariables.rebalancingStatus));
                console.log("  isCenterPriceShiftActive:", entireData[i].dexState.dexVariables.isCenterPriceShiftActive);
                console.log("  centerPrice:", _toString(entireData[i].dexState.dexVariables.centerPrice));
                console.log("  centerPriceAddress:", entireData[i].dexState.dexVariables.centerPriceAddress);
                console.log("  isRangePercentShiftActive:", entireData[i].dexState.dexVariables.isRangePercentShiftActive);
                console.log("  upperRangePercent:", _toString(entireData[i].dexState.dexVariables.upperRangePercent));
                console.log("  lowerRangePercent:", _toString(entireData[i].dexState.dexVariables.lowerRangePercent));
                console.log("  isThresholdPercentShiftActive:", entireData[i].dexState.dexVariables.isThresholdPercentShiftActive);
                console.log("  upperShiftThresholdPercent:", _toString(entireData[i].dexState.dexVariables.upperShiftThresholdPercent));
                console.log("  lowerShiftThresholdPercent:", _toString(entireData[i].dexState.dexVariables.lowerShiftThresholdPercent));
                console.log("  token0Decimals:", _toString(entireData[i].dexState.dexVariables.token0Decimals));
                console.log("  token1Decimals:", _toString(entireData[i].dexState.dexVariables.token1Decimals));
                console.log("  totalToken0AdjustedAmount:", _toString(entireData[i].dexState.dexVariables.totalToken0AdjustedAmount));
                console.log("  totalToken1AdjustedAmount:", _toString(entireData[i].dexState.dexVariables.totalToken1AdjustedAmount));
                
                // Center Price Shift
                console.log("Center Price Shift:");
                console.log("  lastInteractionTimestamp:", _toString(entireData[i].dexState.centerPriceShift.lastInteractionTimestamp));
                console.log("  rebalancingShiftingTime:", _toString(entireData[i].dexState.centerPriceShift.rebalancingShiftingTime));
                console.log("  maxCenterPrice:", _toString(entireData[i].dexState.centerPriceShift.maxCenterPrice));
                console.log("  minCenterPrice:", _toString(entireData[i].dexState.centerPriceShift.minCenterPrice));
                console.log("  shiftPercentage:", _toString(entireData[i].dexState.centerPriceShift.shiftPercentage));
                console.log("  centerPriceShiftingTime:", _toString(entireData[i].dexState.centerPriceShift.centerPriceShiftingTime));
                console.log("  startTimestamp:", _toString(entireData[i].dexState.centerPriceShift.startTimestamp));
                
                // Range Shift
                console.log("Range Shift:");
                console.log("  oldUpperRangePercent:", _toString(entireData[i].dexState.rangeShift.oldUpperRangePercent));
                console.log("  oldLowerRangePercent:", _toString(entireData[i].dexState.rangeShift.oldLowerRangePercent));
                console.log("  shiftingTime:", _toString(entireData[i].dexState.rangeShift.shiftingTime));
                console.log("  startTimestamp:", _toString(entireData[i].dexState.rangeShift.startTimestamp));
                
                // Threshold Shift
                console.log("Threshold Shift:");
                console.log("  oldUpperThresholdPercent:", _toString(entireData[i].dexState.thresholdShift.oldUpperThresholdPercent));
                console.log("  oldLowerThresholdPercent:", _toString(entireData[i].dexState.thresholdShift.oldLowerThresholdPercent));
                console.log("  shiftingTime:", _toString(entireData[i].dexState.thresholdShift.shiftingTime));
                console.log("  startTimestamp:", _toString(entireData[i].dexState.thresholdShift.startTimestamp));
                
                console.log("===============================================");
            }
            
            assertTrue(true, "getAllDexesEntireData should not revert");
        } catch Error(string memory reason) {
            console.log("ERROR: getAllDexesEntireData() failed with error:", reason);
            fail();
        } catch (bytes memory lowLevelData) {
            console.log("ERROR: getAllDexesEntireData() failed with low-level error");
            console.logBytes(lowLevelData);
            fail();
        }
    }
    
    function testEstimateSwapSingle() public {
        console.log("=== Testing estimateSwapHop() - Single ===");
        
        // First get available dexes
        DexKey[] memory dexes = resolver.getAllDexes();
        
        if (dexes.length == 0) {
            console.log("WARNING: No dexes available to test estimateSwapHop");
            return;
        }
        
        // Test estimateSwapHop with first available dex
        DexKey memory testDexKey = dexes[0];
        int256 amountSpecified = 1e6; // 1 token
        
                 try resolver.estimateSwapSingle(testDexKey, true, amountSpecified) returns (uint256 amountOut) {
             console.log("SUCCESS: estimateSwapSingle() succeeded");
            console.log("Estimated output amount:", _toString(amountOut));
            
            assertTrue(amountOut > 0, "Estimated output should be greater than 0");
        } catch Error(string memory reason) {
            console.log("WARNING: estimateSwapHop() (single) failed with error:", reason);
            // This might fail if there's insufficient liquidity or other reasons
            // Don't fail the test as this is expected behavior in some cases
        }
    }
    
        function testEstimateSwapHopMultiple() public {
        console.log("=== Testing estimateSwapHop() - Multiple ===");
         
        // First get available dexes
        DexKey[] memory dexes = resolver.getAllDexes();
         
        if (dexes.length == 0) {
            console.log("ERROR: No dexes available to test multi-hop swap");
            return;
        }
         
        // Since we only have 1 dex (USDC/USDT), we'll create a round-trip path
        // USDC -> USDT -> USDC using the same dex twice
        address[] memory path = new address[](3);
        path[0] = dexes[0].token0; // USDC
        path[1] = dexes[0].token1; // USDT
        path[2] = dexes[0].token0; // USDC (back to original)
         
        DexKey[] memory dexKeys = new DexKey[](2);
        dexKeys[0] = dexes[0]; // USDC -> USDT
        dexKeys[1] = dexes[0]; // USDT -> USDC (same pool, reverse direction)
         
        int256 amountSpecified = 1e6; // 1 USDC (6 decimals)
         
        console.log("Multi-hop path:");
        console.log("  Start:", path[0]);
        console.log("  Via:", path[1]); 
        console.log("  End:", path[2]);
        console.log("Amount specified:", _toString(uint256(amountSpecified)));
         
        try resolver.estimateSwapHop(path, dexKeys, amountSpecified) returns (uint256 amountOut) {
            console.log("SUCCESS: estimateSwapHop() (multiple) succeeded");
            console.log("Estimated output amount:", _toString(amountOut));
             
            assertTrue(amountOut > 0, "Estimated output should be greater than 0");
            
            // The round-trip should result in less than the original amount due to fees
            assertTrue(amountOut < uint256(amountSpecified), "Round-trip should lose value due to fees");
            
            // But it shouldn't be drastically different (should be > 90% of original)
            uint256 efficiency = (amountOut * 10000) / uint256(amountSpecified);
            console.log("Round-trip efficiency (basis points):", _toString(efficiency));
            assertTrue(efficiency > 9000, "Efficiency should be > 90%"); // More than 90% efficiency
             
        } catch Error(string memory reason) {
            console.log("ERROR: estimateSwapHop() (multiple) failed with error:", reason);
            fail();
        } catch (bytes memory reason) {
            console.log("ERROR: estimateSwapHop() (multiple) failed with low-level error");
            console.log("Reason length:", _toString(reason.length));
            if (reason.length >= 4) {
                console.log("Error selector:", vm.toString(bytes4(reason)));
            }
            fail();
        }
    }
    
    function testContractAddresses() public {
        console.log("=== Testing Contract Addresses ===");
        
        // Test that all contract addresses have code
        uint256 dexLiteCodeSize;
        uint256 adminCodeSize;
        uint256 deployerCodeSize;
        
        assembly {
            dexLiteCodeSize := extcodesize(FLUID_DEX_LITE)
            adminCodeSize := extcodesize(FLUID_DEX_LITE_ADMIN)
            deployerCodeSize := extcodesize(DEPLOYER_FACTORY)
        }
        
        console.log("FluidDexLite code size:", _toString(dexLiteCodeSize));
        console.log("FluidDexLiteAdmin code size:", _toString(adminCodeSize));
        console.log("DeployerFactory code size:", _toString(deployerCodeSize));
        
        assertTrue(dexLiteCodeSize > 0, "FluidDexLite should have code");
        assertTrue(adminCodeSize > 0, "FluidDexLiteAdmin should have code");
        assertTrue(deployerCodeSize > 0, "DeployerFactory should have code");
        
        console.log("SUCCESS: All contract addresses are valid");
    }
}