//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { FluidDexLite } from "../../../contracts/protocols/dexLite/core/main.sol";
import { FluidDexLiteAdminModule } from "../../../contracts/protocols/dexLite/adminModule/main.sol";
import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { DexKey, TransferParams } from "../../../contracts/protocols/dexLite/other/structs.sol";
import { InitializeParams } from "../../../contracts/protocols/dexLite/adminModule/structs.sol";
import { DexLiteSlotsLink as DSL } from "../../../contracts/libraries/dexLiteSlotsLink.sol";
import { EstimateSwap } from "../../../contracts/protocols/dexLite/core/errors.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract DexLiteTest is LiquidityBaseTest {
    using SafeERC20 for IERC20;

    FluidDexLite public dexLite;
    FluidDexLiteAdminModule public dexLiteAdminModule;

    uint256 internal constant X60 = 0xfffffffffffffff;

    // Use the canonical ETH address for native ETH
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function dexCallback(address token_, uint256 amount_, bytes calldata data_) external {
        if (data_.length > 0) { 
            (bool shouldTestReentrancy_) = abi.decode(data_, (bool));
            if (shouldTestReentrancy_) {
                console2.log("Reentrancy test");
                vm.expectRevert();
                DexKey memory dexKey = DexKey({
                    token0: address(USDC),
                    token1: ETH_ADDRESS,
                    salt: bytes32(0)
                });
                dexLite.swapSingle(
                    dexKey,
                    false,
                    int256(0.01 ether),
                    uint256(0),
                    address(this),
                    false,
                    "",
                    ""
                );
            }
        }

        if (token_ == ETH_ADDRESS) {
            // For ETH, we need to send ETH to increase the contract's balance
            (bool success, ) = address(dexLite).call{value: amount_}("");
            require(success, "ETH transfer failed in callback");
        } else {
            // For ERC20 tokens, transfer tokens to the contract
            IERC20(token_).safeTransfer(address(dexLite), amount_);
        }
    }

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

        // Fund address(this) with 10000 USDC and 10000 USDT
        deal(address(USDT), address(this), 100000 * 1e6);
        deal(address(USDC), address(this), 100000 * 1e6);

        dexLite = new FluidDexLite(address(this), address(liquidity), address(this));
        dexLiteAdminModule = new FluidDexLiteAdminModule(address(liquidity), address(this));
    }

    function testSetUp() public {
        assertNotEq(address(dexLite), address(0));
        assertNotEq(address(dexLiteAdminModule), address(0));
    }

    function _initialize(DexKey memory dexKey) internal {
        // Set initial liquidity: 2 ETH and 7000 USDC
        uint256 token0Amount = 7000 * 1e6;
        uint256 token1Amount = 2 ether;

        uint256 centerPrice_ = uint256(1e27) / 3500;
        InitializeParams memory initParams = InitializeParams({
            dexKey: dexKey,
            revenueCut: 0,
            fee: 3000, // 0.3% fee (3000 = 0.3% in 4 decimals)
            rebalancingStatus: false,
            centerPrice: centerPrice_, // 1 ETH = 3500 USDC
            centerPriceContract: 0, // No external price contract
            upperPercent: 50000, // 5% upper range (50000 = 5% in 4 decimals)
            lowerPercent: 50000, // 5% lower range (50000 = 5% in 4 decimals)
            upperShiftThreshold: 100000, // 10% threshold (100000 = 10% in 4 decimals)
            lowerShiftThreshold: 100000, // 10% threshold (100000 = 10% in 4 decimals)
            shiftTime: 3600, // 1 hour shift time
            minCenterPrice: 1,
            maxCenterPrice: type(uint256).max,
            token0Amount: token0Amount,
            token1Amount: token1Amount
        });

        // Encode the initialize function call using selector
        bytes memory initializeData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.initialize.selector,
            initParams,
            token0Amount,
            token1Amount
        );

        USDC.approve(address(dexLite), 7000 * 1e6);

        // Encode the fallback data (target address + spell data)
        bytes memory fallbackData = abi.encode(address(dexLiteAdminModule), initializeData);

        // Call the fallback function to delegate call initialize
        (bool success, ) = address(dexLite).call{value: 2 ether}(fallbackData);
        require(success, "Initialize failed");

        // Verify the initialization worked
        assertTrue(success, "ETH/USDC Dex initialization should succeed");
    }

    function _initializeUsdcUsdt(DexKey memory dexKey) internal {
        // Initialize with 100 USDC + 100 USDT
        uint256 token0Amount = 7000 * 1e6; // 100 of token0
        uint256 token1Amount = 7000 * 1e6; // 100 of token1

        // Determine which token is token0 and token1 based on address ordering
        address token0 = dexKey.token0;
        address token1 = dexKey.token1;

        // Initialize parameters for USDC/USDT pool
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

        // Approve tokens for DexLite contract based on actual token ordering
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
        require(success, "USDC/USDT Initialize failed");

        // Verify the initialization worked
        assertTrue(success, "USDC/USDT Dex initialization should succeed");
    }

    function _initializeEthUsdt(DexKey memory dexKey) internal {
        // Set initial liquidity: 2 ETH and 7000 USDT (similar to ETH/USDC)
        uint256 token0Amount;
        uint256 token1Amount;
        
        // Determine amounts based on token ordering
        uint256 centerPrice_;
        if (dexKey.token0 == address(USDT)) {
            token0Amount = 7000 * 1e6; // 7000 USDT
            token1Amount = 2 ether;    // 2 ETH
            centerPrice_ = uint256(1e27) / 3500; // 1 ETH = 3500 USDT
        } else {
            token0Amount = 2 ether;    // 2 ETH  
            token1Amount = 7000 * 1e6; // 7000 USDT
            centerPrice_ = 3500 * 1e27; // 1 ETH = 3500 USDT
        }

        InitializeParams memory initParams = InitializeParams({
            dexKey: dexKey,
            revenueCut: 0,
            fee: 3000, // 0.3% fee (3000 = 0.3% in 4 decimals)
            rebalancingStatus: false,
            centerPrice: centerPrice_, // 1 ETH = 3500 USDT
            centerPriceContract: 0, // No external price contract
            upperPercent: 50000, // 5% upper range (50000 = 5% in 4 decimals)
            lowerPercent: 50000, // 5% lower range (50000 = 5% in 4 decimals)
            upperShiftThreshold: 100000, // 10% threshold (100000 = 10% in 4 decimals)
            lowerShiftThreshold: 100000, // 10% threshold (100000 = 10% in 4 decimals)
            shiftTime: 3600, // 1 hour shift time
            minCenterPrice: 1,
            maxCenterPrice: type(uint256).max,
            token0Amount: token0Amount,
            token1Amount: token1Amount
        });

        // Encode the initialize function call using selector
        bytes memory initializeData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.initialize.selector,
            initParams,
            token0Amount,
            token1Amount
        );

        // Approve tokens based on ordering
        if (dexKey.token0 == address(USDT)) {
            USDT.approve(address(dexLite), token0Amount);
            // token1 is ETH, no approval needed
        } else {
            // token0 is ETH, no approval needed
            USDT.approve(address(dexLite), token1Amount);
        }

        // Encode the fallback data (target address + spell data)
        bytes memory fallbackData = abi.encode(address(dexLiteAdminModule), initializeData);

        // Call the fallback function to delegate call initialize
        // Send ETH amount based on token ordering
        uint256 ethAmount = (dexKey.token1 == ETH_ADDRESS) ? token1Amount : token0Amount;
        (bool success, ) = address(dexLite).call{value: ethAmount}(fallbackData);
        require(success, "ETH/USDT Initialize failed");

        // Verify the initialization worked
        assertTrue(success, "ETH/USDT Dex initialization should succeed");
    }

    function _initializeWithRebalancing(DexKey memory dexKey) internal {
        // Set initial liquidity: 2 ETH and 7000 USDC (same as regular init)
        uint256 token0Amount = 7000 * 1e6;
        uint256 token1Amount = 2 ether;

        uint256 centerPrice_ = uint256(1e27) / 3500;
        InitializeParams memory initParams = InitializeParams({
            dexKey: dexKey,
            revenueCut: 0,
            fee: 3000, // 0.3% fee (3000 = 0.3% in 4 decimals)
            rebalancingStatus: true, // Enable rebalancing
            centerPrice: centerPrice_, // 1 ETH = 3500 USDC
            centerPriceContract: 0, // No external price contract
            upperPercent: 50000, // 5% upper range (50000 = 5% in 4 decimals)
            lowerPercent: 50000, // 5% lower range (50000 = 5% in 4 decimals)
            upperShiftThreshold: 300000, // 30% threshold (300000 = 30% in 4 decimals) - aggressive threshold for testing
            lowerShiftThreshold: 300000, // 30% threshold (300000 = 30% in 4 decimals) - aggressive threshold for testing
            shiftTime: 3600, // 1 hour shift time
            minCenterPrice: 1,
            maxCenterPrice: 10000 * 1e27,
            token0Amount: token0Amount,
            token1Amount: token1Amount
        });

        // Encode the initialize function call using selector
        bytes memory initializeData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.initialize.selector,
            initParams,
            token0Amount,
            token1Amount
        );

        USDC.approve(address(dexLite), 7000 * 1e6);

        // Encode the fallback data (target address + spell data)
        bytes memory fallbackData = abi.encode(address(dexLiteAdminModule), initializeData);

        // Call the fallback function to delegate call initialize
        (bool success, ) = address(dexLite).call{value: 2 ether}(fallbackData);
        require(success, "Rebalancing Initialize failed");

        // Verify the initialization worked
        assertTrue(success, "Rebalancing ETH/USDC Dex initialization should succeed");
    }

    function _initializeWideRangeWithRebalancing(DexKey memory dexKey) internal {
        // Set larger initial liquidity for wide range testing: 10 ETH and 35000 USDC
        uint256 token0Amount = 35000 * 1e6; // 35000 USDC
        uint256 token1Amount = 10 ether;    // 10 ETH

        uint256 centerPrice_ = uint256(1e27) / 3500; // 1 ETH = 3500 USDC
        InitializeParams memory initParams = InitializeParams({
            dexKey: dexKey,
            revenueCut: 0,
            fee: 3000, // 0.3% fee (3000 = 0.3% in 4 decimals)
            rebalancingStatus: true, // Enable rebalancing
            centerPrice: centerPrice_, // 1 ETH = 3500 USDC
            centerPriceContract: 0, // No external price contract
            upperPercent: 500000, // 50% upper range (500000 = 50% in 4 decimals)
            lowerPercent: 500000, // 50% lower range (500000 = 50% in 4 decimals)
            upperShiftThreshold: 100000, // 10% threshold (100000 = 10% in 4 decimals)
            lowerShiftThreshold: 100000, // 10% threshold (100000 = 10% in 4 decimals)
            shiftTime: 3600, // 1 hour shift time
            minCenterPrice: 1,
            maxCenterPrice: 10000 * 1e27, // Allow wide price range
            token0Amount: token0Amount,
            token1Amount: token1Amount
        });

        // Encode the initialize function call using selector
        bytes memory initializeData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.initialize.selector,
            initParams,
            token0Amount,
            token1Amount
        );

        USDC.approve(address(dexLite), token0Amount);

        // Encode the fallback data (target address + spell data)
        bytes memory fallbackData = abi.encode(address(dexLiteAdminModule), initializeData);

        // Call the fallback function to delegate call initialize
        (bool success, ) = address(dexLite).call{value: token1Amount}(fallbackData);
        require(success, "Wide range initialize failed");

        // Verify the initialization worked
        assertTrue(success, "Wide range ETH/USDC Dex initialization should succeed");
    }

    function testInitializeEthUsdcDex() public {
        // Create DexKey for ETH/USDC
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(0)
        });

        _initialize(dexKey);
    }

    struct TestSwapEthUsdcExactInput {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialEthBalance;
        DexKey dexKey;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut;
        uint256 finalUsdcBalance;
        uint256 finalEthBalance;
        uint256 gasUsed;
    }

    function testSwapEthUsdcExactInput() public {
        TestSwapEthUsdcExactInput memory v_;

        // Create DexKey for ETH/USDC
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(0)
        });

        _initialize(dexKey);

        // Now perform the swap: 0.1 ETH -> USDC
        v_.swapAmount = 0.1 ether;
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialEthBalance = address(this).balance;

        // Set up swap parameters for ETH -> USDC
        v_.dexKey = dexKey;
        v_.swap0To1 = false; // ETH (token1) -> USDC (token0), so swap0To1 = false
        v_.amountSpecified = int256(v_.swapAmount); // Positive for exact input
        v_.amountLimit = 0; // Minimum USDC to receive (0 for testing)
        v_.to = address(this); // Receive USDC to this address
        v_.isCallback = false; // No callback needed for ETH
        v_.callbackData = ""; // Empty callback data
        v_.extraData = ""; // Empty extra data

        // Perform the swap
        uint256 gasBefore = gasleft();
        v_.amountOut = dexLite.swapSingle{value: v_.swapAmount}(
            v_.dexKey,
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

        // Verify the swap results
        v_.finalUsdcBalance = USDC.balanceOf(address(this));
        v_.finalEthBalance = address(this).balance;

        // Check that we received USDC
        assertGt(v_.finalUsdcBalance, v_.initialUsdcBalance, "Should receive USDC");
        assertEq(v_.finalUsdcBalance - v_.initialUsdcBalance, v_.amountOut, "USDC received should match v_.amountOut");
        
        // Check that at least the swap amount of ETH was spent (plus gas)
        assertLe(v_.finalEthBalance, v_.initialEthBalance - v_.swapAmount, "ETH should be spent for swap");
        
        // Log the swap results
        console2.log("Swapped ETH amount:", _toString(v_.swapAmount));
        console2.log("Received USDC amount:", _toString(v_.amountOut));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestSwapEthUsdcExactOutput {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialEthBalance;
        DexKey dexKey;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountIn;
        uint256 finalUsdcBalance;
        uint256 finalEthBalance;
        uint256 gasUsed;
    }

    function testSwapEthUsdcExactOutput() public {
        TestSwapEthUsdcExactOutput memory v_;

        // Create DexKey for ETH/USDC
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(0)
        });

        _initialize(dexKey);

        // We want to receive exactly 348.510100 USDC (6 decimals)
        uint256 desiredUsdcOut = 348_510100; // 348.510100 USDC (6 decimals)

        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialEthBalance = address(this).balance;

        // Set up swap parameters
        v_.dexKey = dexKey;
        v_.swap0To1 = false; // ETH (token1) -> USDC (token0), so swap0To1 = false
        v_.amountSpecified = -int256(desiredUsdcOut); // Negative for exact output
        v_.amountLimit = type(uint256).max; // Maximum ETH we're willing to spend (set to max for test)
        v_.to = address(this); // Receive USDC to this address
        v_.isCallback = false; // No callback needed for ETH
        v_.callbackData = ""; // Empty callback data
        v_.extraData = ""; // Empty extra data

        // Perform the swap. We don't know the exact ETH required, so send a large enough value.
        // We'll check that the correct amount is spent.
        uint256 gasBefore = gasleft();
        v_.amountIn = dexLite.swapSingle{value: 1 ether}(
            v_.dexKey,
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

        // Verify the swap results
        v_.finalUsdcBalance = USDC.balanceOf(address(this));
        v_.finalEthBalance = address(this).balance;

        // Check that we received exactly the desired USDC
        assertEq(v_.finalUsdcBalance - v_.initialUsdcBalance, desiredUsdcOut, "Should receive exact USDC out");

        // Check that ETH was spent (should be less than or equal to 1 ether)
        uint256 ethSpent = v_.initialEthBalance - v_.finalEthBalance;
        assertGt(ethSpent, 0, "ETH should be spent for swap");
        assertLe(ethSpent, 1 ether, "Should not spend more than 1 ether");

        // Check that the returned amountIn matches the ETH spent
        assertEq(v_.amountIn, ethSpent, "amountIn should match actual ETH spent");

        // Log the swap results
        console2.log("Swapped ETH amount:", _toString(ethSpent));
        console2.log("Received USDC amount:", _toString(desiredUsdcOut));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestSwapUsdcUsdt {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialUsdtBalance;
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
        uint256 usdcSpent;
        uint256 usdtReceived;
        uint256 gasUsed;
    }

    function testSwapUsdcToUsdt() public {
        // Determine correct token ordering (token0 = smaller address, token1 = larger address)
        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        // Create DexKey with correct token ordering
        DexKey memory dexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(0)
        });

        // Initialize the USDC/USDT pool
        _initializeUsdcUsdt(dexKey);

        TestSwapUsdcUsdt memory v_;

        // Swap amount: 1 USDC
        v_.swapAmount = 1 * 1e6; // 1 USDC

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialUsdtBalance = USDT.balanceOf(address(this));

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

        // Get final balances
        v_.finalUsdcBalance = USDC.balanceOf(address(this));
        v_.finalUsdtBalance = USDT.balanceOf(address(this));

        // Calculate actual amounts
        v_.usdcSpent = v_.initialUsdcBalance - v_.finalUsdcBalance;
        v_.usdtReceived = v_.finalUsdtBalance - v_.initialUsdtBalance;

        // Verify the swap results
        assertEq(v_.usdcSpent, v_.swapAmount, "Should spend exactly the swap amount of USDC");
        assertGt(v_.usdtReceived, 0, "Should receive some USDT");
        assertEq(v_.usdtReceived, v_.amountOut, "USDT received should match contract return value");

        // Log the swap results
        console2.log("Swapped USDC amount:", _toString(v_.swapAmount));
        console2.log("Received USDT amount:", _toString(v_.amountOut));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestSwapUsdcEth {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialEthBalance;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut;
        uint256 finalUsdcBalance;
        uint256 finalEthBalance;
        uint256 usdcSpent;
        uint256 ethReceived;
        uint256 gasUsed;
    }

    function testSwapUsdcToEth() public {
        // Create DexKey for ETH/USDC
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(0)
        });

        // Initialize the ETH/USDC pool
        _initialize(dexKey);

        TestSwapUsdcEth memory v_;

        // Swap amount: 350 USDC (approximately 0.1 ETH worth at 3500 price)
        v_.swapAmount = 350 * 1e6; // 350 USDC

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialEthBalance = address(this).balance;

        // Verify sufficient USDC balance
        assertGe(v_.initialUsdcBalance, v_.swapAmount, "Should have enough USDC for swap");

        // Set up swap parameters for USDC -> ETH
        // In ETH/USDC pair: token0=USDC, token1=ETH, so USDC->ETH is swap0To1=true
        v_.swap0To1 = true;
        v_.amountSpecified = int256(v_.swapAmount); // Positive for exact input
        v_.amountLimit = 0; // Minimum ETH to receive (0 for testing)
        v_.to = address(this); // Receive ETH to this address
        v_.isCallback = true; // Use callback for ERC20 tokens
        v_.callbackData = ""; // Callback data for USDC
        v_.extraData = ""; // Empty extra data

        // Note: We don't approve here as we'll handle it in the callback

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

        // Get final balances
        v_.finalUsdcBalance = USDC.balanceOf(address(this));
        v_.finalEthBalance = address(this).balance;

        // Calculate actual amounts (note: finalEthBalance might be lower due to gas costs)
        v_.usdcSpent = v_.initialUsdcBalance - v_.finalUsdcBalance;
        // For ETH received, we need to account for the gas spent during the transaction
        // The amountOut should represent the actual ETH received
        v_.ethReceived = v_.amountOut;

        // Verify the swap results
        assertEq(v_.usdcSpent, v_.swapAmount, "Should spend exactly the swap amount of USDC");
        assertGt(v_.ethReceived, 0, "Should receive some ETH");

        // Log the swap results
        console2.log("Swapped USDC amount:", _toString(v_.swapAmount));
        console2.log("Received ETH amount:", _toString(v_.amountOut));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestMultiHopSwap {
        uint256 initialEthAmount;
        uint256 initialUsdcBalance;
        uint256 initialUsdtBalance;
        uint256 initialEthBalance;
        address[] path;
        DexKey[] dexKeys;
        int256 amountSpecified;
        uint256[] amountLimits;
        TransferParams transferParams;
        uint256 amountOut;
        uint256 finalUsdcBalance;
        uint256 finalUsdtBalance;
        uint256 finalEthBalance;
        uint256 ethSpent;
        uint256 ethReceived;
        uint256 netEthChange;
        uint256 gasUsed;
    }

    function testMultiHopSwapEthUsdcUsdtEth() public {
        // First, set up all three required pools
        
        // 1. Create and initialize ETH/USDC pool
        DexKey memory ethUsdcDexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(0)
        });
        _initialize(ethUsdcDexKey);

        // 2. Create and initialize USDC/USDT pool
        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        DexKey memory usdcUsdtDexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(uint256(1)) // Different salt to avoid collision
        });
        _initializeUsdcUsdt(usdcUsdtDexKey);

        // 3. Create and initialize ETH/USDT pool for the final swap
        DexKey memory ethUsdtDexKey = DexKey({
            token0: address(USDT),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(2)) // Different salt to avoid collision
        });
        _initializeEthUsdt(ethUsdtDexKey);

        TestMultiHopSwap memory v_;

        // Start with 0.1 ETH for the multi-hop swap
        v_.initialEthAmount = 0.1 ether;

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialUsdtBalance = USDT.balanceOf(address(this));
        v_.initialEthBalance = address(this).balance;

        // Set up the path: ETH -> USDC -> USDT -> ETH
        v_.path = new address[](4);
        v_.path[0] = ETH_ADDRESS;    // Start with ETH
        v_.path[1] = address(USDC);  // Convert to USDC
        v_.path[2] = address(USDT);  // Convert to USDT
        v_.path[3] = ETH_ADDRESS;    // End with ETH

        // Set up the corresponding dex keys for each hop
        v_.dexKeys = new DexKey[](3);
        v_.dexKeys[0] = ethUsdcDexKey;    // ETH -> USDC (using ETH/USDC pool)
        v_.dexKeys[1] = usdcUsdtDexKey;   // USDC -> USDT (using USDC/USDT pool)
        v_.dexKeys[2] = ethUsdtDexKey;    // USDT -> ETH (using ETH/USDT pool)

        v_.amountSpecified = int256(v_.initialEthAmount); // Positive for exact input
        v_.amountLimits = new uint256[](3); // Array of limits for each hop
        v_.amountLimits[0] = 0; // Minimum USDC to receive from ETH->USDC swap
        v_.amountLimits[1] = 0; // Minimum USDT to receive from USDC->USDT swap  
        v_.amountLimits[2] = 0; // Minimum ETH to receive from USDT->ETH swap
        v_.transferParams = TransferParams({
            to: address(this), // Receive final ETH to this address
            isCallback: false, // No callback needed for ETH input
            callbackData: "", // Empty callback data
            extraData: "" // Empty extra data
        });

        // Measure gas consumption for the multi-hop swap
        uint256 gasBefore = gasleft();
        
        // Perform the multi-hop swap
        v_.amountOut = dexLite.swapHop{value: v_.initialEthAmount}(
            v_.path,
            v_.dexKeys,
            v_.amountSpecified,
            v_.amountLimits,
            v_.transferParams
        );
        
        uint256 gasAfter = gasleft();
        v_.gasUsed = gasBefore - gasAfter;

        // Get final balances
        v_.finalUsdcBalance = USDC.balanceOf(address(this));
        v_.finalUsdtBalance = USDT.balanceOf(address(this));
        v_.finalEthBalance = address(this).balance;

        // Calculate the changes
        v_.ethSpent = v_.initialEthBalance - v_.finalEthBalance; // This includes gas costs
        v_.ethReceived = v_.amountOut; // This is the pure swap output
        v_.netEthChange = v_.ethReceived; // Net ETH from the swap (not including gas)

        // Verify the swap results
        assertGt(v_.ethReceived, 0, "Should receive some ETH at the end");
        
        // The multi-hop should result in some ETH, but likely less than we started with due to fees
        // We expect some loss due to fees across multiple hops
        
        // Calculate efficiency (should be less than 100% due to fees)
        uint256 efficiency = (v_.ethReceived * 10000) / v_.initialEthAmount; // Efficiency in basis points
        
        // We expect efficiency to be reasonably high (e.g., > 95%) even with multiple fees
        assertGe(efficiency, 9000, "Multi-hop efficiency should be at least 90%");
        assertLe(efficiency, 10000, "Efficiency cannot exceed 100%");

        // Log the swap results
        console2.log("Swapped ETH amount:", _toString(v_.initialEthAmount));
        console2.log("Received ETH amount:", _toString(v_.amountOut));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestEthCallbackSwap {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialEthBalance;
        DexKey dexKey;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut;
        uint256 finalUsdcBalance;
        uint256 finalEthBalance;
        uint256 gasUsed;
    }

    function testEthCallbackSwap() public {
        // Create DexKey for ETH/USDC with unique salt for callback test
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(10)) // Unique salt for callback test
        });

        // Initialize the ETH/USDC pool
        _initialize(dexKey);

        TestEthCallbackSwap memory v_;

        // Swap amount: 0.1 ETH -> USDC using callback
        v_.swapAmount = 0.1 ether;

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialEthBalance = address(this).balance;

        // Set up swap parameters for ETH -> USDC using callback
        v_.dexKey = dexKey;
        v_.swap0To1 = false; // ETH (token1) -> USDC (token0), so swap0To1 = false
        v_.amountSpecified = int256(v_.swapAmount); // Positive for exact input
        v_.amountLimit = 0; // Minimum USDC to receive (0 for testing)
        v_.to = address(this); // Receive USDC to this address
        v_.isCallback = true; // Use callback for ETH transfer
        v_.callbackData = ""; // Callback data for ETH
        v_.extraData = ""; // Empty extra data

        // Measure gas consumption for the swap
        uint256 gasBefore = gasleft();
        
        // Perform the swap with callback (no msg.value sent with the call)
        v_.amountOut = dexLite.swapSingle(
            v_.dexKey,
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

        // Get final balances
        v_.finalUsdcBalance = USDC.balanceOf(address(this));
        v_.finalEthBalance = address(this).balance;

        // Verify the swap results
        assertGt(v_.finalUsdcBalance, v_.initialUsdcBalance, "Should receive USDC");
        assertEq(v_.finalUsdcBalance - v_.initialUsdcBalance, v_.amountOut, "USDC received should match amountOut");
        
        // Check that ETH was spent (we can't easily separate gas costs, so just check ETH was spent)
        assertLt(v_.finalEthBalance, v_.initialEthBalance, "ETH should be spent for swap");

        // Log the swap results
        console2.log("Swapped ETH amount:", _toString(v_.swapAmount));
        console2.log("Received USDC amount:", _toString(v_.amountOut));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestErc20CallbackSwap {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialEthBalance;
        DexKey dexKey;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut;
        uint256 finalUsdcBalance;
        uint256 finalEthBalance;
        uint256 gasUsed;
    }

    function testErc20CallbackSwap() public {
        // Create DexKey for ETH/USDC with unique salt for callback test
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(11)) // Unique salt for ERC20 callback test
        });

        // Initialize the ETH/USDC pool
        _initialize(dexKey);

        TestErc20CallbackSwap memory v_;

        // Swap amount: 350 USDC -> ETH using callback
        v_.swapAmount = 350 * 1e6; // 350 USDC

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialEthBalance = address(this).balance;

        // Verify sufficient USDC balance
        assertGe(v_.initialUsdcBalance, v_.swapAmount, "Should have enough USDC for swap");

        // Set up swap parameters for USDC -> ETH using callback
        v_.dexKey = dexKey;
        v_.swap0To1 = true; // USDC (token0) -> ETH (token1), so swap0To1 = true
        v_.amountSpecified = int256(v_.swapAmount); // Positive for exact input
        v_.amountLimit = 0; // Minimum ETH to receive (0 for testing)
        v_.to = address(this); // Receive ETH to this address
        v_.isCallback = true; // Use callback for USDC transfer
        v_.callbackData = ""; // Callback data for USDC
        v_.extraData = ""; // Empty extra data

        // Don't approve USDC here - the callback will handle the transfer

        // Measure gas consumption for the swap
        uint256 gasBefore = gasleft();
        
        // Perform the swap using callback (no msg.value for ERC20)
        v_.amountOut = dexLite.swapSingle(
            v_.dexKey,
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

        // Get final balances
        v_.finalUsdcBalance = USDC.balanceOf(address(this));
        v_.finalEthBalance = address(this).balance;

        // Verify the swap results
        assertEq(v_.initialUsdcBalance - v_.finalUsdcBalance, v_.swapAmount, "Should spend exactly the swap amount of USDC");
        assertGt(v_.amountOut, 0, "Should receive some ETH");
        // Note: ETH balance comparison is tricky due to gas costs, so we focus on the amountOut

        // Log the swap results
        console2.log("Swapped USDC amount:", _toString(v_.swapAmount));
        console2.log("Received ETH amount:", _toString(v_.amountOut));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestUpperRangeRebalancing {
        uint256 largeSwapAmount;
        uint256 smallSwapAmount;
        uint256 initialUsdcBalance;
        uint256 initialEthBalance;
        DexKey dexKey;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut1;
        uint256 amountOut2;
        uint256 gasUsed;
    }

    function testRebalancingUpperRangeShift() public {
        // Create DexKey for rebalancing test with unique salt
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(20)) // Unique salt for rebalancing test
        });

        // Initialize the ETH/USDC pool with rebalancing enabled
        _initializeWithRebalancing(dexKey);

        TestUpperRangeRebalancing memory v_;

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialEthBalance = address(this).balance;

        // Strategy: Perform large ETH -> USDC swaps to drive price down and trigger upper range rebalancing
        // When ETH price goes down significantly, it means we need to shift towards upper range
        v_.largeSwapAmount = 1.5 ether; // Large ETH amount to move price significantly
        v_.smallSwapAmount = 0.01 ether; // Small amount for final test

        // Set up swap parameters for ETH -> USDC (to drive ETH price down)
        v_.dexKey = dexKey;
        v_.swap0To1 = false; // ETH (token1) -> USDC (token0), so swap0To1 = false
        v_.amountSpecified = int256(v_.largeSwapAmount); // Positive for exact input
        v_.amountLimit = 0; // Minimum USDC to receive
        v_.to = address(this); // Receive USDC to this address
        v_.isCallback = false; // No callback needed for ETH
        v_.callbackData = "";
        v_.extraData = "";

        console2.log("=== UPPER RANGE REBALANCING TEST ===");
        console2.log("Initial ETH price should be around 3500 USDC");

        // Perform first large swap to drive price down
        uint256 gasBefore = gasleft();
        v_.amountOut1 = dexLite.swapSingle{value: v_.largeSwapAmount}(
            v_.dexKey,
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

        console2.log("First large swap completed - should trigger upper range rebalancing");

        // Warp time forward by 30 minutes (half the shift time)
        vm.warp(block.timestamp + 1800);

        // Perform second small swap IN OPPOSITE DIRECTION to see the rebalancing effect
        // First swap was ETH -> USDC, so second swap is USDC -> ETH
        v_.swap0To1 = true; // USDC (token0) -> ETH (token1), so swap0To1 = true
        v_.amountSpecified = int256(200 * 1e6);
        v_.isCallback = true; // Use callback for USDC transfer
        v_.callbackData = "";
        
        gasBefore = gasleft();
        v_.amountOut2 = dexLite.swapSingle(
            v_.dexKey,
            v_.swap0To1,
            v_.amountSpecified,
            v_.amountLimit,
            v_.to,
            v_.isCallback,
            v_.callbackData,
            v_.extraData
        );
        gasAfter = gasleft();

        console2.log("Second swap after 30min - center price should have shifted");

        // Verify that rebalancing had an effect
        // The amounts should be different due to center price shifting
        assertTrue(v_.amountOut1 > 0, "First swap should succeed");
        assertTrue(v_.amountOut2 > 0, "Second swap should succeed");

        // Log the swap results to show the rebalancing effect
        console2.log("Large swap ETH amount:", _toString(v_.largeSwapAmount));
        console2.log("Large swap USDC received:", _toString(v_.amountOut1));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestLowerRangeRebalancing {
        uint256 largeSwapAmount;
        uint256 smallSwapAmount;
        uint256 initialUsdcBalance;
        uint256 initialEthBalance;
        DexKey dexKey;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut1;
        uint256 amountOut2;
        uint256 gasUsed;
    }

    function testRebalancingLowerRangeShift() public {
        // Create DexKey for lower range rebalancing test with unique salt
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(21)) // Unique salt for lower range rebalancing test
        });

        // Initialize the ETH/USDC pool with rebalancing enabled
        _initializeWithRebalancing(dexKey);

        TestLowerRangeRebalancing memory v_;

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialEthBalance = address(this).balance;

        // Strategy: Perform large USDC -> ETH swaps to drive ETH price up and trigger lower range rebalancing
        // When ETH price goes up significantly, it means we need to shift towards lower range
        v_.largeSwapAmount = 5000 * 1e6; // Large USDC amount to move price significantly
        v_.smallSwapAmount = 100 * 1e6; // Small USDC amount for testing

        // Set up swap parameters for USDC -> ETH (to drive ETH price up)
        v_.dexKey = dexKey;
        v_.swap0To1 = true; // USDC (token0) -> ETH (token1), so swap0To1 = true
        v_.amountSpecified = int256(v_.largeSwapAmount); // Positive for exact input
        v_.amountLimit = 0; // Minimum ETH to receive
        v_.to = address(this); // Receive ETH to this address
        v_.isCallback = true; // Use callback for USDC transfer
        v_.callbackData = "";
        v_.extraData = "";

        console2.log("=== LOWER RANGE REBALANCING TEST ===");
        console2.log("Initial ETH price should be around 3500 USDC");

        // Perform first large swap to drive ETH price up
        uint256 gasBefore = gasleft();
        v_.amountOut1 = dexLite.swapSingle(
            v_.dexKey,
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

        console2.log("First large swap completed - should trigger lower range rebalancing");

        // Warp time forward by 30 minutes (half the shift time)
        vm.warp(block.timestamp + 1800);

        // Perform second small swap IN OPPOSITE DIRECTION to see the rebalancing effect
        // First swap was USDC -> ETH, so second swap is ETH -> USDC
        v_.swap0To1 = false; // ETH (token1) -> USDC (token0), so swap0To1 = false
        v_.amountSpecified = int256(0.01 ether);
        v_.isCallback = false; // No callback for ETH
        v_.callbackData = "";
        
        gasBefore = gasleft();
        v_.amountOut2 = dexLite.swapSingle{value: uint256(v_.amountSpecified)}(
            v_.dexKey,
            v_.swap0To1,
            v_.amountSpecified,
            v_.amountLimit,
            v_.to,
            v_.isCallback,
            v_.callbackData,
            v_.extraData
        );
        gasAfter = gasleft();

        console2.log("Second swap after 30min - center price should have shifted");

        // Verify that rebalancing had an effect
        // The amounts should be different due to center price shifting
        assertTrue(v_.amountOut1 > 0, "First swap should succeed");
        assertTrue(v_.amountOut2 > 0, "Second swap should succeed");

        // Log the swap results to show the rebalancing effect
        console2.log("Large swap USDC amount:", _toString(v_.largeSwapAmount));
        console2.log("Large swap ETH received:", _toString(v_.amountOut1));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestRangeShift {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialUsdtBalance;
        DexKey dexKey;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut1;
        uint256 amountOut2;
        uint256 amountOut3;
        uint256 gasUsed;
    }

    function testRangeShifting() public {
        // Determine correct token ordering for USDC/USDT
        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        // Create DexKey for range shifting test with unique salt
        DexKey memory dexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(uint256(30)) // Unique salt for range shifting test
        });

        // Initialize the USDC/USDT pool with 0.15% ranges (1500 = 0.15% in 4 decimals)
        _initializeUsdcUsdt(dexKey);

        TestRangeShift memory v_;

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialUsdtBalance = USDT.balanceOf(address(this));

        // Test swap amount
        v_.swapAmount = 50 * 1e6; // 50 USDC

        // Set up swap parameters for USDC -> USDT
        v_.dexKey = dexKey;
        v_.swap0To1 = (token0 == address(USDC)); // If USDC is token0, then USDC->USDT is swap0To1=true
        v_.amountSpecified = int256(v_.swapAmount);
        v_.amountLimit = 0;
        v_.to = address(this);
        v_.isCallback = false;
        v_.callbackData = "";
        v_.extraData = "";

        // Approve USDC for swaps
        USDC.approve(address(dexLite), v_.swapAmount * 3);

        console2.log("=== RANGE SHIFTING TEST ===");
        console2.log("Initial ranges: +-0.15%");

        // Perform initial swap to establish baseline
        uint256 gasBefore = gasleft();
        v_.amountOut1 = dexLite.swapSingle(
            v_.dexKey,
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

        console2.log("Initial swap completed with 0.15% ranges");

        // Now trigger range shift from 0.15% to 0.2% over 1 hour
        // 2000 = 0.2% in 4 decimals, 3600 = 1 hour in seconds
        bytes memory updateRangeData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.updateRangePercents.selector,
            dexKey,
            2000, // 0.2% upper range
            2000, // 0.2% lower range
            3600  // 1 hour shift time
        );

        // Encode the fallback data for admin call
        bytes memory fallbackData = abi.encode(address(dexLiteAdminModule), updateRangeData);

        // Call the admin function to trigger range shift
        (bool success, ) = address(dexLite).call(fallbackData);
        require(success, "Range shift trigger failed");

        console2.log("Range shift triggered: 0.15% -> 0.2% over 1 hour");

        // Warp time forward by 30 minutes (half the shift time)
        vm.warp(block.timestamp + 1800);

        // Perform second swap during the range shift
        gasBefore = gasleft();
        v_.amountOut2 = dexLite.swapSingle(
            v_.dexKey,
            v_.swap0To1,
            v_.amountSpecified,
            v_.amountLimit,
            v_.to,
            v_.isCallback,
            v_.callbackData,
            v_.extraData
        );
        gasAfter = gasleft();

        console2.log("Second swap after 30min - ranges should be shifting");

        // Warp time forward by another 30 minutes (completing the shift)
        vm.warp(block.timestamp + 1801);

        // Perform third swap after range shift is complete
        gasBefore = gasleft();
        v_.amountOut3 = dexLite.swapSingle(
            v_.dexKey,
            v_.swap0To1,
            v_.amountSpecified,
            v_.amountLimit,
            v_.to,
            v_.isCallback,
            v_.callbackData,
            v_.extraData
        );
        gasAfter = gasleft();

        console2.log("Third swap after full shift - ranges should be 0.2%");

        // Log the swap results to show the range shifting effect
        console2.log("Swapped USDC amount:", _toString(v_.swapAmount));
        console2.log("USDT received (final swap):", _toString(v_.amountOut3));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct TestThresholdShift {
        uint256 swapAmount;
        uint256 initialUsdcBalance;
        uint256 initialUsdtBalance;
        DexKey dexKey;
        bool swap0To1;
        int256 amountSpecified;
        uint256 amountLimit;
        address to;
        bool isCallback;
        bytes callbackData;
        bytes extraData;
        uint256 amountOut1;
        uint256 amountOut2;
        uint256 amountOut3;
        uint256 gasUsed;
    }

    function testThresholdShifting() public {
        // Determine correct token ordering for USDC/USDT
        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        // Create DexKey for threshold shifting test with unique salt
        DexKey memory dexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(uint256(31)) // Unique salt for threshold shifting test
        });

        // Initialize the USDC/USDT pool (rebalancing disabled by default in _initializeUsdcUsdt)
        _initializeUsdcUsdt(dexKey);

        TestThresholdShift memory v_;

        // Get initial balances
        v_.initialUsdcBalance = USDC.balanceOf(address(this));
        v_.initialUsdtBalance = USDT.balanceOf(address(this));

        // Test swap amount
        v_.swapAmount = 50 * 1e6; // 50 USDC

        // Set up swap parameters for USDC -> USDT
        v_.dexKey = dexKey;
        v_.swap0To1 = (token0 == address(USDC)); // If USDC is token0, then USDC->USDT is swap0To1=true
        v_.amountSpecified = int256(v_.swapAmount);
        v_.amountLimit = 0;
        v_.to = address(this);
        v_.isCallback = false;
        v_.callbackData = "";
        v_.extraData = "";

        // Approve USDC for swaps
        USDC.approve(address(dexLite), v_.swapAmount * 3);

        console2.log("=== THRESHOLD SHIFTING TEST ===");
        console2.log("Rebalancing disabled initially");

        // First, enable rebalancing status using admin function
        bytes memory enableRebalancingData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.updateRebalancingStatus.selector,
            dexKey,
            true // Enable rebalancing
        );

        // Encode the fallback data for admin call
        bytes memory fallbackData = abi.encode(address(dexLiteAdminModule), enableRebalancingData);

        // Call the admin function to enable rebalancing
        (bool success, ) = address(dexLite).call(fallbackData);
        require(success, "Enable rebalancing failed");

        console2.log("Rebalancing enabled via admin function");

        // Perform initial swap to establish baseline
        uint256 gasBefore = gasleft();
        v_.amountOut1 = dexLite.swapSingle(
            v_.dexKey,
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

        console2.log("Initial swap completed with rebalancing enabled");

        // Now trigger threshold shift from default to new thresholds over 1 hour
        // Current thresholds in _initializeUsdcUsdt are 0, so we shift to 10% and 10%
        // 100000 = 10% in 4 decimals, 3600 = 1 hour in seconds
        bytes memory updateThresholdData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.updateThresholdPercent.selector,
            dexKey,
            100000, // 10% upper threshold
            100000, // 10% lower threshold
            3600    // 1 hour shift time
        );

        // Encode the fallback data for admin call
        fallbackData = abi.encode(address(dexLiteAdminModule), updateThresholdData);

        // Call the admin function to trigger threshold shift
        (success, ) = address(dexLite).call(fallbackData);
        require(success, "Threshold shift trigger failed");

        console2.log("Threshold shift triggered: 0% -> 10% over 1 hour");

        // Warp time forward by 30 minutes (half the shift time)
        vm.warp(block.timestamp + 1800);

        // Perform second swap during the threshold shift
        gasBefore = gasleft();
        v_.amountOut2 = dexLite.swapSingle(
            v_.dexKey,
            v_.swap0To1,
            v_.amountSpecified,
            v_.amountLimit,
            v_.to,
            v_.isCallback,
            v_.callbackData,
            v_.extraData
        );
        gasAfter = gasleft();

        console2.log("Second swap after 30min - thresholds should be shifting");

        // Warp time forward by another 30 minutes + 1 second (completing the shift)
        vm.warp(block.timestamp + 1801);

        // Perform third swap after threshold shift is complete
        gasBefore = gasleft();
        v_.amountOut3 = dexLite.swapSingle(
            v_.dexKey,
            v_.swap0To1,
            v_.amountSpecified,
            v_.amountLimit,
            v_.to,
            v_.isCallback,
            v_.callbackData,
            v_.extraData
        );
        gasAfter = gasleft();

        console2.log("Third swap after full shift - thresholds should be 10%");

        // Log the swap results to show the threshold shifting effect
        console2.log("Swapped USDC amount:", _toString(v_.swapAmount));
        console2.log("USDT received (final swap):", _toString(v_.amountOut3));
        console2.log("Gas used for swap:", _toString(v_.gasUsed));
    }

    struct SelectorInfo {
        bytes4 selector;
        string functionName;
    }

    function testFunctionSelectorOrder() public pure {
        // Get all external function selectors for FluidDexLite
        bytes4[3] memory selectors = [
            FluidDexLite.swapSingle.selector,
            FluidDexLite.swapHop.selector,
            FluidDexLite.readFromStorage.selector
        ];
        
        // Create array of selector-function name pairs for sorting
        SelectorInfo[3] memory selectorInfos = [
            SelectorInfo(selectors[0], "swapSingle"),
            SelectorInfo(selectors[1], "swapHop"), 
            SelectorInfo(selectors[2], "readFromStorage")
        ];
        
        // Sort selectors in ascending order using bubble sort
        for (uint256 i = 0; i < selectorInfos.length - 1; i++) {
            for (uint256 j = 0; j < selectorInfos.length - i - 1; j++) {
                if (uint32(selectorInfos[j].selector) > uint32(selectorInfos[j + 1].selector)) {
                    SelectorInfo memory temp = selectorInfos[j];
                    selectorInfos[j] = selectorInfos[j + 1];
                    selectorInfos[j + 1] = temp;
                }
            }
        }
        
        // Log the sorted order for debugging
        console2.log("Function selector order (lowest to highest):");
        for (uint256 i = 0; i < selectorInfos.length; i++) {
            console2.log(string.concat(
                _toString(i + 1), 
                ". ", 
                selectorInfos[i].functionName, 
                " - 0x", 
                _toString(uint256(uint32(selectorInfos[i].selector)))
            ));
        }
        
        // Verify that swapSingle has the lowest selector
        assertEq(
            selectorInfos[0].functionName, 
            "swapSingle", 
            "swapSingle function should have the lowest selector"
        );
        
        // Verify that swapHop has the second lowest selector
        assertEq(
            selectorInfos[1].functionName, 
            "swapHop", 
            "swapHop function should have the second lowest selector"
        );
    }

    struct TestFeeAndRevenueCut {
        // Test configuration
        uint256 feePercent;
        uint256 revenueCutPercent;
        uint256 swapAmount;
        uint256 reverseSwapAmount;
        uint256 tolerance;
        
        // DexKey and tokens
        DexKey dexKey;
        address token0;
        address token1;
        bool swap0To1;
        
        // Expected calculations
        uint256 expectedFee;
        uint256 expectedRevenueCut;
        uint256 expectedLiquidityIncrease;
        uint256 reverseExpectedFee;
        uint256 reverseExpectedRevenueCut;
        
        // Reserve tracking
        uint256 initialToken0Reserve;
        uint256 initialToken1Reserve;
        uint256 finalToken0Reserve;
        uint256 finalToken1Reserve;
        
        // Swap results
        uint256 amountOut;
        uint256 reverseAmountOut;
        uint256 gasUsed;
        
        // Verification values
        uint256 expectedToken0Increase;
        uint256 actualToken0Increase;
        uint256 expectedToken1Decrease;
        uint256 actualToken1Decrease;
        uint256 effectiveInputAmount;
    }

    function _initializeWithFeeAndRevenueCut(DexKey memory dexKey, uint256 fee, uint256 revenueCut) internal {
        uint256 token0Amount = 1000 * 1e6;
        uint256 token1Amount = 1000 * 1e6;

        InitializeParams memory initParams = InitializeParams({
            dexKey: dexKey,
            revenueCut: revenueCut * 10000, // Convert to 4 decimals (e.g., 20 becomes 200000 for 20%)
            fee: fee, // Already in correct format (e.g., 10000 = 1% fee)
            rebalancingStatus: false,
            centerPrice: 1e27, // 1:1 center price
            centerPriceContract: 0,
            upperPercent: 50000, // 5% upper range
            lowerPercent: 50000, // 5% lower range
            upperShiftThreshold: 0,
            lowerShiftThreshold: 0,
            shiftTime: 3600,
            minCenterPrice: 1,
            maxCenterPrice: type(uint256).max,
            token0Amount: token0Amount,
            token1Amount: token1Amount
        });

        if (dexKey.token0 == address(USDC)) {
            USDC.approve(address(dexLite), token0Amount);
            USDT.approve(address(dexLite), token1Amount);
        } else {
            USDT.approve(address(dexLite), token0Amount);
            USDC.approve(address(dexLite), token1Amount);
        }

        bytes memory initializeData = abi.encodeWithSelector(
            FluidDexLiteAdminModule.initialize.selector,
            initParams
        );

        bytes memory fallbackData = abi.encode(address(dexLiteAdminModule), initializeData);
        (bool success, ) = address(dexLite).call(fallbackData);
        require(success, "Initialize with fee and revenue cut failed");
    }

    function _getReserves(DexKey memory dexKey) internal view returns (uint256 token0Reserve, uint256 token1Reserve) {
        bytes8 dexId = bytes8(keccak256(abi.encode(dexKey)));
        bytes32 storageSlot = DSL.calculateMappingStorageSlot(DSL.DEX_LITE_DEX_VARIABLES_SLOT, dexId);
        uint256 dexVariables = dexLite.readFromStorage(storageSlot);
        
        // Get reserves in adjusted amounts (9 decimals)
        uint256 token0ReserveAdjusted = (dexVariables >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) & X60;
        uint256 token1ReserveAdjusted = (dexVariables >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED) & X60;
        
        // Convert from 9 decimals (adjusted) to 6 decimals (USDC/USDT native decimals)
        // Both USDC and USDT have 6 decimals, so we divide by 10^(9-6) = 1000
        token0Reserve = token0ReserveAdjusted / 1000;
        token1Reserve = token1ReserveAdjusted / 1000;
    }

    function testFeeAndRevenueCutCharging() public {
        TestFeeAndRevenueCut memory v_;
        
        // Initialize test configuration
        v_.token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        v_.token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        v_.dexKey = DexKey({
            token0: v_.token0,
            token1: v_.token1,
            salt: bytes32(uint256(100)) // Unique salt for fee test
        });

        v_.feePercent = 5000; // 0.5% fee (5000 = 0.5% in 4 decimals)
        v_.revenueCutPercent = 20; // 20% of fees go to protocol
        v_.swapAmount = 100 * 1e6; // 100 tokens
        v_.reverseSwapAmount = 50 * 1e6; // 50 tokens in reverse direction
        v_.tolerance = 2; // 2 wei tolerance for rounding
        v_.swap0To1 = true;
        
        _initializeWithFeeAndRevenueCut(v_.dexKey, v_.feePercent, v_.revenueCutPercent);

        console2.log("=== FEE AND REVENUE CUT TEST ===");
        console2.log("Fee: 1%, Revenue Cut: 20%");
        console2.log("Swap Amount: 100 tokens");

        // Get initial reserves
        (v_.initialToken0Reserve, v_.initialToken1Reserve) = _getReserves(v_.dexKey);

        // Calculate expected fees
        v_.expectedFee = (v_.swapAmount * v_.feePercent) / 1000000; // 1% of swap amount
        v_.expectedRevenueCut = (v_.expectedFee * v_.revenueCutPercent) / 100; // 20% of fee
        v_.expectedLiquidityIncrease = v_.expectedFee - v_.expectedRevenueCut; // 80% of fee stays in pool

        console2.log("Expected fee:", _toString(v_.expectedFee));
        console2.log("Expected revenue cut:", _toString(v_.expectedRevenueCut));
        console2.log("Expected liquidity increase:", _toString(v_.expectedLiquidityIncrease));

        // Approve the swap amount
        if (v_.token0 == address(USDC)) {
            USDC.approve(address(dexLite), v_.swapAmount);
        } else {
            USDT.approve(address(dexLite), v_.swapAmount);
        }

        uint256 gasBefore = gasleft();
        v_.amountOut = dexLite.swapSingle(
            v_.dexKey,
            v_.swap0To1,
            int256(v_.swapAmount),
            0, // No minimum output for test
            address(this),
            false, // No callback
            "",
            ""
        );
        uint256 gasAfter = gasleft();
        v_.gasUsed = gasBefore - gasAfter;

        // Get final reserves
        (v_.finalToken0Reserve, v_.finalToken1Reserve) = _getReserves(v_.dexKey);

        console2.log("Amount received:", _toString(v_.amountOut));
        console2.log("Gas used:", _toString(v_.gasUsed));

        // Verify fee calculations
        v_.effectiveInputAmount = v_.swapAmount - v_.expectedFee;
        v_.expectedToken0Increase = v_.swapAmount - v_.expectedRevenueCut;
        v_.actualToken0Increase = v_.finalToken0Reserve - v_.initialToken0Reserve;
        v_.expectedToken1Decrease = v_.amountOut;
        v_.actualToken1Decrease = v_.initialToken1Reserve - v_.finalToken1Reserve;
        
        console2.log("Expected token0 increase:", _toString(v_.expectedToken0Increase));
        console2.log("Actual token0 increase:", _toString(v_.actualToken0Increase));
        console2.log("Expected token1 decrease:", _toString(v_.expectedToken1Decrease));
        console2.log("Actual token1 decrease:", _toString(v_.actualToken1Decrease));

        assertApproxEqAbs(
            v_.actualToken0Increase,
            v_.expectedToken0Increase,
            v_.tolerance,
            "Token0 reserve increase should account for fee and revenue cut"
        );
        
        assertApproxEqAbs(
            v_.actualToken1Decrease,
            v_.expectedToken1Decrease,
            v_.tolerance,
            "Token1 reserve decrease should equal amount out"
        );

        // Test reverse direction swap to ensure fees work both ways
        console2.log("\n=== REVERSE DIRECTION SWAP ===");
        
        v_.reverseExpectedFee = (v_.reverseSwapAmount * v_.feePercent) / 1000000;
        v_.reverseExpectedRevenueCut = (v_.reverseExpectedFee * v_.revenueCutPercent) / 100;
        
        // Approve reverse swap
        if (v_.token1 == address(USDC)) {
            USDC.approve(address(dexLite), v_.reverseSwapAmount);
        } else {
            USDT.approve(address(dexLite), v_.reverseSwapAmount);
        }

        v_.reverseAmountOut = dexLite.swapSingle(
            v_.dexKey,
            false, // token1 -> token0
            int256(v_.reverseSwapAmount),
            0,
            address(this),
            false,
            "",
            ""
        );

        console2.log("Reverse swap amount:", _toString(v_.reverseSwapAmount));
        console2.log("Reverse amount received:", _toString(v_.reverseAmountOut));
        console2.log("Reverse expected fee:", _toString(v_.reverseExpectedFee));
        console2.log("Reverse expected revenue cut:", _toString(v_.reverseExpectedRevenueCut));

        // Verify the reverse swap also applies fees correctly
        assertTrue(v_.reverseAmountOut > 0, "Reverse swap should succeed");
        assertTrue(v_.reverseAmountOut < v_.reverseSwapAmount, "Output should be less than input due to fees");
    }

    function testSwapSingleRevertsWithExtraDataZeroAddress() public {
        // Create DexKey for ETH/USDC
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(200)) // Unique salt for extra data test
        });

        // Initialize the pool
        _initialize(dexKey);

        // Prepare swap parameters with non-empty extraData that is NOT ESTIMATE_SWAP
        bool swap0To1 = false; // ETH -> USDC
        int256 amountSpecified = int256(0.1 ether);
        uint256 amountLimit = 0;
        address to = address(this);
        bool isCallback = false;
        bytes memory callbackData = "";
        bytes memory extraData = abi.encode("some extra data"); // Non-empty extra data that is not ESTIMATE_SWAP

        // Expect the call to revert because extra data slot address is zero
        vm.expectRevert(); // Should revert with ZeroAddress()
        
        dexLite.swapSingle{value: 0.1 ether}(
            dexKey,
            swap0To1,
            amountSpecified,
            amountLimit,
            to,
            isCallback,
            callbackData,
            extraData
        );
    }

    function testSwapHopRevertsWithExtraDataZeroAddress() public {
        // Set up pools for multihop: ETH -> USDC -> USDT
        
        // 1. ETH/USDC pool
        DexKey memory ethUsdcDexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(201)) // Unique salt
        });
        _initialize(ethUsdcDexKey);

        // 2. USDC/USDT pool
        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        DexKey memory usdcUsdtDexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(uint256(202)) // Unique salt
        });
        _initializeUsdcUsdt(usdcUsdtDexKey);

        // Set up multihop path: ETH -> USDC -> USDT
        address[] memory path = new address[](3);
        path[0] = ETH_ADDRESS;
        path[1] = address(USDC);
        path[2] = address(USDT);

        DexKey[] memory dexKeys = new DexKey[](2);
        dexKeys[0] = ethUsdcDexKey;    // ETH -> USDC
        dexKeys[1] = usdcUsdtDexKey;   // USDC -> USDT

        // Prepare swap parameters with non-empty extraData that is NOT ESTIMATE_SWAP
        int256 amountSpecified = int256(0.1 ether);
        uint256[] memory amountLimits = new uint256[](2);
        amountLimits[0] = 0; // Minimum USDC to receive from ETH->USDC swap
        amountLimits[1] = 0; // Minimum USDT to receive from USDC->USDT swap
        TransferParams memory transferParams = TransferParams({
            to: address(this),
            isCallback: false,
            callbackData: "",
            extraData: abi.encode("some extra data for multihop") // Non-empty extra data that is not ESTIMATE_SWAP
        });

        // Expect the call to revert because extra data slot address is zero
        vm.expectRevert(); // Should revert with ZeroAddress()
        
        dexLite.swapHop{value: 0.1 ether}(
            path,
            dexKeys,
            amountSpecified,
            amountLimits,
            transferParams
        );
    }

    function testSwapSingleReentrancyProtection() public {
        // Create DexKey for reentrancy test
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(300)) // Unique salt for reentrancy test
        });

        // Initialize the pool
        _initialize(dexKey);

        console2.log("=== SWAP SINGLE REENTRANCY TEST ===");

        // Perform the swap - callback will attempt reentrancy
        uint256 amountOut = dexLite.swapSingle(
            dexKey,
            true,
            int256(350 * 1e6),
            0,
            address(this),
            true,
            abi.encode(true),
            ""
        );

        // Verify the main swap succeeded
        assertGt(amountOut, 0, "Main swap should succeed");
        console2.log("Reentrancy successfully blocked during swapSingle");
    }

    function testSwapHopReentrancyProtection() public {
        // Set up pools for multihop reentrancy test
        
        // 1. ETH/USDC pool (not used for multihop, but exists for consistency)
        DexKey memory ethUsdcDexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(301)) // Unique salt
        });
        _initialize(ethUsdcDexKey);

        // 2. USDC/USDT pool (for main multihop)
        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        DexKey memory usdcUsdtDexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(uint256(302)) // Unique salt
        });
        _initializeUsdcUsdt(usdcUsdtDexKey);

        console2.log("=== SWAP MULTIHOP REENTRANCY TEST ===");

        // Set up multihop path: USDC -> USDT
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(USDT);

        DexKey[] memory dexKeys = new DexKey[](1);
        dexKeys[0] = usdcUsdtDexKey; // USDC -> USDT

        uint256[] memory amountLimits = new uint256[](1);
        amountLimits[0] = 0; // Minimum USDT to receive from USDC->USDT swap

        TransferParams memory transferParams = TransferParams({
            to: address(this),
            isCallback: true,
            callbackData: abi.encode(true),
            extraData: ""
        });

        // Perform the multihop swap - callback will attempt reentrancy
        uint256 amountOut = dexLite.swapHop(
            path,
            dexKeys,
            int256(100 * 1e6),
            amountLimits,
            transferParams
        );

        // Verify the main swap succeeded
        assertGt(amountOut, 0, "Main multihop swap should succeed");
        console2.log("Reentrancy successfully blocked during swapHop");
    }

    function testSwapSingleEstimation() public {
        // First, perform actual swap to get the real result
        DexKey memory actualDexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(400))
        });
        _initialize(actualDexKey);
        
        uint256 actualAmount = dexLite.swapSingle{value: 0.1 ether}(
            actualDexKey,
            false, // ETH -> USDC
            int256(0.1 ether),
            0,
            address(this),
            false,
            "",
            ""
        );

        // Now test estimation with fresh pool (same initial state)
        DexKey memory estimateDexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(401))
        });
        _initialize(estimateDexKey);

        bytes32 estimateSwap = keccak256(bytes("ESTIMATE_SWAP"));
        bytes memory extraData = abi.encodePacked(estimateSwap);

        // Expect revert with specific estimated amount
        vm.expectRevert(abi.encodeWithSelector(EstimateSwap.selector, actualAmount));
        
        dexLite.swapSingle{value: 0.1 ether}(
            estimateDexKey,
            false, // ETH -> USDC
            int256(0.1 ether),
            0,
            address(this),
            false,
            "",
            extraData
        );
    }

    function testSwapHopEstimation() public {
        // First, perform actual multihop swap to get the real result
        
        // Set up pools for actual swap: ETH -> USDC -> USDT
        DexKey memory actualEthUsdcDexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(500))
        });
        _initialize(actualEthUsdcDexKey);

        address token0 = address(USDC) < address(USDT) ? address(USDC) : address(USDT);
        address token1 = address(USDC) < address(USDT) ? address(USDT) : address(USDC);
        
        DexKey memory actualUsdcUsdtDexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(uint256(501))
        });
        _initializeUsdcUsdt(actualUsdcUsdtDexKey);

        address[] memory actualPath = new address[](3);
        actualPath[0] = ETH_ADDRESS;
        actualPath[1] = address(USDC);
        actualPath[2] = address(USDT);

        DexKey[] memory actualDexKeys = new DexKey[](2);
        actualDexKeys[0] = actualEthUsdcDexKey;
        actualDexKeys[1] = actualUsdcUsdtDexKey;

        uint256[] memory actualAmountLimits = new uint256[](2);
        actualAmountLimits[0] = 0;
        actualAmountLimits[1] = 0;
        
        TransferParams memory actualTransferParams = TransferParams({
            to: address(this),
            isCallback: false,
            callbackData: "",
            extraData: ""
        });

        uint256 actualAmount = dexLite.swapHop{value: 0.1 ether}(
            actualPath,
            actualDexKeys,
            int256(0.1 ether),
            actualAmountLimits,
            actualTransferParams
        );

        // Now test estimation with fresh pools (same initial state)
        DexKey memory estimateEthUsdcDexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(502))
        });
        _initialize(estimateEthUsdcDexKey);
        
        DexKey memory estimateUsdcUsdtDexKey = DexKey({
            token0: token0,
            token1: token1,
            salt: bytes32(uint256(503))
        });
        _initializeUsdcUsdt(estimateUsdcUsdtDexKey);

        address[] memory estimatePath = new address[](3);
        estimatePath[0] = ETH_ADDRESS;
        estimatePath[1] = address(USDC);
        estimatePath[2] = address(USDT);

        DexKey[] memory estimateDexKeys = new DexKey[](2);
        estimateDexKeys[0] = estimateEthUsdcDexKey;
        estimateDexKeys[1] = estimateUsdcUsdtDexKey;

        uint256[] memory estimateAmountLimits = new uint256[](2);
        estimateAmountLimits[0] = 0;
        estimateAmountLimits[1] = 0;
        
        bytes32 estimateSwap = keccak256(bytes("ESTIMATE_SWAP"));
        TransferParams memory estimateTransferParams = TransferParams({
            to: address(this),
            isCallback: false,
            callbackData: "",
            extraData: abi.encodePacked(estimateSwap)
        });

        // Expect revert with specific estimated amount
        vm.expectRevert(abi.encodeWithSelector(EstimateSwap.selector, actualAmount));
        
        dexLite.swapHop{value: 0.1 ether}(
            estimatePath,
            estimateDexKeys,
            int256(0.1 ether),
            estimateAmountLimits,
            estimateTransferParams
        );
    }

    function testWideRangeRebalancingEthUsdc() public {
        // Initialize ETH/USDC pool with ±50% ranges and rebalancing enabled
        DexKey memory dexKey = DexKey({
            token0: address(USDC),
            token1: ETH_ADDRESS,
            salt: bytes32(uint256(600))
        });
        _initializeWideRangeWithRebalancing(dexKey);

        // Phase 1: Large ETH sell to test price impact with wide ranges
        uint256 initialPrice = 3500 * 1e6; // Expected initial price
        uint256 ethSellAmount = 5 ether;
        uint256 usdcReceived = dexLite.swapSingle{value: ethSellAmount}(
            dexKey, false, int256(ethSellAmount), 0, address(this), false, "", ""
        );
        uint256 priceAfterSell = (usdcReceived * 1e18) / ethSellAmount;
        
        // Verify price dropped but stayed within reasonable bounds due to wide range
        assertLt(priceAfterSell, initialPrice, "Price should drop after large sell");
        assertGt(priceAfterSell, initialPrice * 80 / 100, "Price should not drop more than 20% with wide range");

        // Phase 2: Time progression for rebalancing
        vm.warp(block.timestamp + 3600);
        uint256 smallSwapResult = dexLite.swapSingle{value: 0.01 ether}(
            dexKey, false, int256(0.01 ether), 0, address(this), false, "", ""
        );
        assertGt(smallSwapResult, 0, "Small swap should succeed after rebalancing period");

        // Phase 3: Large USDC buy to test opposite direction
        uint256 usdcBuyAmount = 20000 * 1e6;
        USDC.approve(address(dexLite), usdcBuyAmount);
        uint256 ethReceived = dexLite.swapSingle(
            dexKey, true, int256(usdcBuyAmount), 0, address(this), true, "", ""
        );
        uint256 priceAfterBuy = (usdcBuyAmount * 1e18) / ethReceived;
        
        // Verify price recovered
        assertGt(priceAfterBuy, priceAfterSell, "Price should recover after large buy");

        // Phase 4: Verify normal operation continues
        vm.warp(block.timestamp + 3600);
        uint256 normalSwapResult = dexLite.swapSingle{value: 0.1 ether}(
            dexKey, false, int256(0.1 ether), 0, address(this), false, "", ""
        );
        assertGt(normalSwapResult, 0, "Normal swaps should continue working");
    }

    // Needed to receive ETH during swaps
    receive() external payable {}
}