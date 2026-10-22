// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidSmartLending } from "../../../../contracts/protocols/dex/smartLending/main.sol";
import { IFluidDexFactory } from "../../../../contracts/protocols/dex/interfaces/iDexFactory.sol";
import { FluidSmartLendingFactory } from "../../../../contracts/protocols/dex/smartLending/factory/main.sol";
import { IFluidDexT1 } from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";

/// @dev Regression tests pinning Smart Lending storage layout.
contract FluidSmartLendingStorageLayoutTest is Test {
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal constant LIQUIDITY_PLACEHOLDER = address(0xBEEF);
    address internal constant DEX_FACTORY_PLACEHOLDER = address(0xDEF0);
    address internal constant SMART_LENDING_FACTORY_PLACEHOLDER = address(0xD0D0);
    address internal constant DEX_PLACEHOLDER = address(0x1111);

    address internal constant TOKEN0 = address(0xAAA0);
    address internal constant TOKEN1 = address(0xBBB1);

    uint256 internal constant DEX_ID = 42;

    FluidSmartLending internal smartLending;

    function setUp() public {
        // stub `DEX_FACTORY.getDexAddress(DEX_ID)` to return our placeholder DEX.
        vm.mockCall(
            DEX_FACTORY_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexFactory.getDexAddress.selector, DEX_ID),
            abi.encode(DEX_PLACEHOLDER)
        );

        // stub `DEX.constantsView()` with a minimal payload. Only `token0`, `token1`, and
        // `liquidity` are read by the constructor (the rest of the struct is ignored).
        IFluidDexT1.ConstantViews memory cv;
        cv.dexId = DEX_ID;
        cv.liquidity = LIQUIDITY_PLACEHOLDER;
        cv.token0 = TOKEN0;
        cv.token1 = TOKEN1;
        vm.mockCall(DEX_PLACEHOLDER, abi.encodeWithSelector(IFluidDexT1.constantsView.selector), abi.encode(cv));

        smartLending = new FluidSmartLending(
            DEX_ID,
            LIQUIDITY_PLACEHOLDER,
            DEX_FACTORY_PLACEHOLDER,
            SMART_LENDING_FACTORY_PLACEHOLDER
        );
    }

    // ------------------------------------------------------------------
    // ERC20 base (slots 0..4) — still inherited, slots must be intact.
    // ------------------------------------------------------------------

    function test_ERC20_NameAndSymbol_PersistAtDynamicSlots() public {
        string memory name = smartLending.name();
        string memory symbol = smartLending.symbol();
        // "Fluid Smart Lending 42" and "fSL42" from the constructor prefixes.
        assertEq(name, "Fluid Smart Lending 42");
        assertEq(symbol, "fSL42");
        // initial supply is 0 — confirms the ERC20 `_totalSupply` slot is reachable via the
        // public getter (i.e. not shadowed by a separate ERC20 copy).
        assertEq(smartLending.totalSupply(), 0);
    }

    // ------------------------------------------------------------------
    // Slot 5 — packed: uint40 lastTimestamp (offset 0),
    //                 int32 feeOrReward (offset 5),
    //                 uint184 exchangePrice (offset 9).
    // ------------------------------------------------------------------

    function test_Slot5_PackedRateTuple_LayoutPinned() public {
        bytes32 slot5 = vm.load(address(smartLending), bytes32(uint256(5)));

        uint40 lastTimestampRaw = uint40(uint256(slot5));
        int32 feeOrRewardRaw = int32(int256(uint256(slot5) >> 40));
        uint184 exchangePriceRaw = uint184(uint256(slot5) >> 72);

        assertEq(
            uint256(lastTimestampRaw),
            uint256(smartLending.lastTimestamp()),
            "lastTimestamp must live at slot 5 offset 0 (bits 0..39)"
        );
        assertEq(feeOrRewardRaw, smartLending.feeOrReward(), "feeOrReward must live at slot 5 offset 5 (bits 40..71)");
        assertEq(
            uint256(exchangePriceRaw),
            uint256(smartLending.exchangePrice()),
            "exchangePrice must live at slot 5 offset 9 (bits 72..255)"
        );

        // constructor-assigned invariants
        assertEq(uint256(exchangePriceRaw), 1e18, "initial exchangePrice = 1e18");
        assertEq(feeOrRewardRaw, int32(0), "initial feeOrReward = 0");
        assertEq(uint256(lastTimestampRaw), block.timestamp, "lastTimestamp = block.timestamp at ctor");
    }

    // ------------------------------------------------------------------
    // Slot 6 — address rebalancer.
    // ------------------------------------------------------------------

    function test_Slot6_Rebalancer_LayoutPinned() public {
        bytes32 slot6 = vm.load(address(smartLending), bytes32(uint256(6)));
        address rebalancerRaw = address(uint160(uint256(slot6)));
        assertEq(rebalancerRaw, smartLending.rebalancer(), "rebalancer must live at slot 6 offset 0");
    }

    // ------------------------------------------------------------------
    // Slot 7 — packed: address dexFromAddress (offset 0, 20 bytes),
    //                 uint8 _status        (offset 20, 1 byte).
    // ------------------------------------------------------------------

    function test_Slot7_DexFromAddressAndStatus_LayoutPinned() public {
        bytes32 slot7 = vm.load(address(smartLending), bytes32(uint256(7)));
        address dexFromAddressRaw = address(uint160(uint256(slot7)));
        uint8 statusRaw = uint8(uint256(slot7) >> 160);

        assertEq(dexFromAddressRaw, smartLending.dexFromAddress(), "dexFromAddress must live at slot 7 offset 0");
        // constructor sets `dexFromAddress = DEAD_ADDRESS = 0x…dEaD`.
        assertEq(dexFromAddressRaw, address(0x000000000000000000000000000000000000dEaD));

        // `_status` is internal — we only know it must be `REENTRANCY_NOT_ENTERED = 1`
        // outside of an active call (set by the `ReentrancyGuard` constructor).
        assertEq(uint256(statusRaw), uint256(1), "_status must be NOT_ENTERED(=1) at slot 7 offset 20");
    }

    // ------------------------------------------------------------------
    // Belt-and-suspenders: writing through slot 5 must be visible in the
    // public getters (and vice versa). Catches any future encoding drift.
    // ------------------------------------------------------------------

    function test_Slot5_WriteThroughMatchesGetters() public {
        // Encode: lastTimestamp = 0x11223344 (32 bits), feeOrReward = -123 (int32),
        //         exchangePrice = some 184-bit value.
        uint40 lastTimestamp = 0x11223344;
        int32 feeOrReward = -123;
        uint184 exchangePrice = uint184(5e17 + 42);

        uint256 packed;
        packed |= uint256(lastTimestamp);
        packed |= uint256(uint32(feeOrReward)) << 40;
        packed |= uint256(exchangePrice) << 72;

        vm.store(address(smartLending), bytes32(uint256(5)), bytes32(packed));

        assertEq(uint256(smartLending.lastTimestamp()), uint256(lastTimestamp));
        assertEq(smartLending.feeOrReward(), feeOrReward);
        assertEq(uint256(smartLending.exchangePrice()), uint256(exchangePrice));
    }
}
