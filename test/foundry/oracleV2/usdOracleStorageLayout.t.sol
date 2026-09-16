// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsdOracle } from "../../../contracts/oracleV2/usdOracle/main.sol";
import { Structs } from "../../../contracts/oracleV2/usdOracle/structs.sol";
import { FluidUsdOracleHarness, IOracleAdminMulticall } from "./usdOracleForkTestBase.sol";

contract MockReadFromStorageLayout {
    mapping(bytes32 => uint256) public storageValues;

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        return storageValues[slot_];
    }

    function setStorage(bytes32 slot_, uint256 value_) external {
        storageValues[slot_] = value_;
    }
}

contract MockChainlinkFeedForLayout {
    int256 internal _answer;

    constructor(int256 answer_) {
        _answer = answer_;
    }

    function setAnswer(int256 answer_) external {
        _answer = answer_;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _answer, 1, 1, 1);
    }
}

/// @dev Locks in `_tokenSources` / `_additionalTokenSources` storage layout and hot-path SLOAD counts.
///
/// ## Why the first version of this test did NOT catch the metadata packing bug
///
/// The original test asserted the layout Solidity produces for a **nested** `TokenMetadata` struct on
/// `TokenSourceConfig` (separate from `primarySrc`):
///   - mapping word 0 = `TokenMetadata` only
///   - mapping word 1 = `__placeholder1`
///   - mapping word 2 = `primarySrc` slot 0 (`source1` + types)
///
/// Current layout flattens metadata into `TokenSources` slot 0 on `primarySrc` (see `structs.sol`).
///
/// That matches the official rule that **structs always start a new slot** (see Solidity docs:
/// https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html ). So the test passed
/// even though the **documented product goal** was the opposite: metadata + source1 + sourceType1-3
/// in a **single** word (2-SLOAD `getPrice` path).
///
/// It also never used `vm.record` / `vm.accesses`, so it could not detect extra runtime SLOADs.
///
/// These tests assert the **flattened** layout and runtime reads. `testStorageLayout_source1MustLiveInMappingWordZero`
/// is the direct regression guard: if metadata is nested again, `source1` moves to word 2 and this fails.
contract FluidUSDOracleStorageLayoutTest is Test, Structs {
    uint8 internal constant SOURCE_NOT_SET = 0;
    uint8 internal constant SOURCE_CAPPED_RATE = 1;
    uint8 internal constant SOURCE_CHAINLINK = 2;
    uint8 internal constant SOURCE_STABLE = 3;
    uint8 internal constant SOURCE_REDSTONE = 4;
    uint8 internal constant SOURCE_FLUID_ORACLE = 5;

    uint8 internal constant TOKEN_TYPE_VOLATILE = 3;
    uint8 internal constant TOKEN_TYPE_PEG = 1;
    uint8 internal constant FLAG_HAS_ALT_SOURCE = 1;
    uint8 internal constant FLAG_HAS_ADDITIONAL_SOURCES = 2;
    uint8 internal constant FLAG_GOVERNANCE_APPROVED = 8;
    uint8 internal constant KEY_FLAG_FALLBACK = 1;
    uint8 internal constant PRICE_MODE_MARKET = 1;

    uint256 internal constant CONFIGS_MAPPING_SLOT = 0;
    uint256 internal constant TOKEN_SOURCES_MAPPING_SLOT = 3;
    uint256 internal constant ADDITIONAL_TOKEN_SOURCES_MAPPING_SLOT = 4;
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address internal constant TOKEN = address(0xBEEF);

    FluidUsdOracle internal usdOracle;
    MockReadFromStorageLayout internal liquidityMock;
    MockChainlinkFeedForLayout internal chainlinkMock;
    MockChainlinkFeedForLayout internal altChainlinkMock;
    MockChainlinkFeedForLayout internal additionalChainlinkMock;

    address internal admin;

    function setUp() public {
        admin = makeAddr("admin");

        liquidityMock = new MockReadFromStorageLayout();
        chainlinkMock = new MockChainlinkFeedForLayout(1e8);
        altChainlinkMock = new MockChainlinkFeedForLayout(2e8);
        additionalChainlinkMock = new MockChainlinkFeedForLayout(3e8);

        liquidityMock.setStorage(LIQUIDITY_GOVERNANCE_SLOT, uint256(uint160(admin)));
        // Harness only for its `multicall`; it declares no storage, so the layout assertions below
        // still describe `FluidUsdOracle` itself.
        usdOracle = new FluidUsdOracleHarness(address(liquidityMock));

        vm.mockCall(TOKEN, abi.encodeWithSignature("decimals()"), abi.encode(uint8(6)));

        SourceConfig memory src1_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(chainlinkMock),
            capOperand: 0
        });
        SourceConfig memory src2_ = SourceConfig({ sourceType: SOURCE_NOT_SET, source: address(0), capOperand: 0 });
        SourceConfig memory src3_ = SourceConfig({ sourceType: SOURCE_NOT_SET, source: address(0), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setTokenType(TOKEN, TOKEN_TYPE_VOLATILE);
        usdOracle.setSourceConfig(TOKEN, src1_, src2_, src3_);
        vm.stopPrank();
    }

    // ---- Regression: metadata + source1 share mapping word 0 ----

    function testStorageLayout_source1MustLiveInMappingWordZero() public view {
        bytes32 baseSlot_ = _tokenSourceBaseSlot(TOKEN);
        uint256 word0_ = uint256(vm.load(address(usdOracle), baseSlot_));

        assertEq(
            address(uint160(word0_)),
            address(chainlinkMock),
            "source1 must be in mapping word 0 (nested TokenMetadata would place it at word 2)"
        );
        assertEq(uint8(word0_ >> 216), TOKEN_TYPE_VOLATILE, "tokenType must be readable from the same word as source1");
    }

    function testStorageLayout_tokenSourcesPacksMetadataIntoPrimarySlot0() public view {
        bytes32 baseSlot_ = _tokenSourceBaseSlot(TOKEN);

        uint256 primarySlot1_ = uint256(vm.load(address(usdOracle), baseSlot_));
        uint256 primarySlot2_ = uint256(vm.load(address(usdOracle), bytes32(uint256(baseSlot_) + 1)));
        uint256 primarySlot3_ = uint256(vm.load(address(usdOracle), bytes32(uint256(baseSlot_) + 2)));

        assertEq(
            primarySlot1_,
            _packPrimarySlot1(
                address(chainlinkMock),
                int8(19),
                SOURCE_CHAINLINK,
                SOURCE_NOT_SET,
                SOURCE_NOT_SET,
                0,
                0,
                TOKEN_TYPE_VOLATILE,
                6,
                FLAG_GOVERNANCE_APPROVED
            ),
            "primary slot 0 should contain source and metadata"
        );
        assertEq(primarySlot2_, 0, "one-source primary config should not populate slot 1");
        assertEq(primarySlot3_, 0, "one-source primary config should not populate slot 2");
    }

    function testStorageLayout_primarySlot1_whenTwoLegConfig() public {
        SourceConfig memory src1_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(chainlinkMock),
            capOperand: 0
        });
        SourceConfig memory src2_ = SourceConfig({ sourceType: SOURCE_STABLE, source: address(0), capOperand: 50 });
        SourceConfig memory src3_ = SourceConfig({ sourceType: SOURCE_NOT_SET, source: address(0), capOperand: 0 });

        vm.prank(admin);
        usdOracle.setSourceConfig(TOKEN, src1_, src2_, src3_);

        bytes32 baseSlot_ = _tokenSourceBaseSlot(TOKEN);
        uint256 slot2_ = uint256(vm.load(address(usdOracle), bytes32(uint256(baseSlot_) + 1)));
        uint256 slot3_ = uint256(vm.load(address(usdOracle), bytes32(uint256(baseSlot_) + 2)));

        assertEq(
            slot2_,
            _packPrimarySlot2(0, address(0), 50),
            "primary slot 1 should pack multiplier2, source2, capOperand2"
        );
        assertEq(slot3_, 0, "two-leg config should not populate primary slot 2");
    }

    function testStorageLayout_primarySlot2_whenThreeLegConfig() public {
        SourceConfig memory src1_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(chainlinkMock),
            capOperand: 0
        });
        SourceConfig memory src2_ = SourceConfig({ sourceType: SOURCE_STABLE, source: address(0), capOperand: 0 });
        SourceConfig memory src3_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(additionalChainlinkMock),
            capOperand: 0
        });

        vm.prank(admin);
        usdOracle.setSourceConfig(TOKEN, src1_, src2_, src3_);

        bytes32 baseSlot_ = _tokenSourceBaseSlot(TOKEN);
        uint256 slot3_ = uint256(vm.load(address(usdOracle), bytes32(uint256(baseSlot_) + 2)));

        assertEq(
            slot3_,
            _packPrimarySlot2(19, address(additionalChainlinkMock), 0),
            "primary slot 2 uses the same shape as slot 1 (multiplier, source, capOperand)"
        );
    }

    // ---- Alt bucket: words 3-5 of TokenSourceConfig ----

    function testStorageLayout_altSingleSourceUsesOnlyFirstAltSlot() public {
        _setAltSourceConfig();

        bytes32 baseSlot_ = _tokenSourceBaseSlot(TOKEN);
        uint256 primarySlot1_ = uint256(vm.load(address(usdOracle), baseSlot_));
        uint256 altSlot1_ = uint256(vm.load(address(usdOracle), bytes32(uint256(baseSlot_) + 3)));
        uint256 altSlot2_ = uint256(vm.load(address(usdOracle), bytes32(uint256(baseSlot_) + 4)));
        uint256 altSlot3_ = uint256(vm.load(address(usdOracle), bytes32(uint256(baseSlot_) + 5)));

        assertEq(
            primarySlot1_,
            _packPrimarySlot1(
                address(chainlinkMock),
                int8(19),
                SOURCE_CHAINLINK,
                SOURCE_NOT_SET,
                SOURCE_NOT_SET,
                0,
                0,
                TOKEN_TYPE_VOLATILE,
                6,
                FLAG_HAS_ALT_SOURCE | FLAG_GOVERNANCE_APPROVED
            ),
            "primary slot should only flip the alt-exists flag"
        );
        assertEq(
            altSlot1_,
            _packPrimarySlot1(
                address(altChainlinkMock),
                int8(19),
                SOURCE_CHAINLINK,
                SOURCE_NOT_SET,
                SOURCE_NOT_SET,
                0,
                0,
                0,
                0,
                0
            ),
            "alt slot 3 should contain the single alt source (metadata bytes zero)"
        );
        assertEq(altSlot2_, 0, "one-source alt config should not populate slot 4");
        assertEq(altSlot3_, 0, "one-source alt config should not populate slot 5");
    }

    // ---- Additional sources mapping (PEG market path); metadata bytes stay zero in word 0 ----

    function testStorageLayout_additionalSourcesPrimarySlot0_noMetadataInWordZero() public {
        SourceConfig memory market1_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(additionalChainlinkMock),
            capOperand: 0
        });
        SourceConfig memory empty_ = SourceConfig({ sourceType: SOURCE_NOT_SET, source: address(0), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setTokenType(TOKEN, TOKEN_TYPE_PEG);
        usdOracle.setSourceConfig(
            TOKEN,
            SourceConfig({ sourceType: SOURCE_CHAINLINK, source: address(chainlinkMock), capOperand: 0 }),
            empty_,
            empty_
        );
        usdOracle.setAdditionalSourceConfig(TOKEN, market1_, empty_, empty_);
        vm.stopPrank();

        bytes32 addBase_ = _additionalTokenSourceBaseSlot(TOKEN);
        uint256 word0_ = uint256(vm.load(address(usdOracle), addBase_));

        assertEq(address(uint160(word0_)), address(additionalChainlinkMock));
        assertEq(uint8(word0_ >> 208), 0, "pauseState unused on additional mapping");
        assertEq(uint8(word0_ >> 216), 0, "tokenType unused on additional mapping");
        assertEq(uint8(word0_ >> 224), 0, "decimals unused on additional mapping");
        assertEq(uint8(word0_ >> 232), 0, "flagsBitmap unused on additional mapping");
    }

    // ---- Runtime SLOAD checks (vm.accesses) ----

    function testReadPath_oneSourceMarketReadsOnlyKeyConfigAndPrimarySlot0() public {
        _setMarketKey(false);

        bytes32 keyConfigSlot_ = _oracleKeyConfigSlot(TOKEN, 0, 1, 1);
        bytes32 primarySlot1_ = _tokenSourceBaseSlot(TOKEN);

        vm.record();
        assertEq(usdOracle.getPriceView(TOKEN, 0, true, true), 1e27);
        (bytes32[] memory reads_, ) = vm.accesses(address(usdOracle));

        _assertRead(reads_, keyConfigSlot_, "key config must be read");
        _assertRead(reads_, primarySlot1_, "primary slot 0 must be read");
        _assertNotRead(reads_, bytes32(uint256(primarySlot1_) + 1), "primary slot 1 must not be read");
        _assertNotRead(reads_, bytes32(uint256(primarySlot1_) + 2), "primary slot 2 must not be read");
        _assertNotRead(reads_, bytes32(uint256(primarySlot1_) + 3), "alt slot 3 must not be read");
    }

    function testReadPath_twoLegConfigReadsPrimarySlot0And1Only() public {
        SourceConfig memory src1_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(chainlinkMock),
            capOperand: 0
        });
        SourceConfig memory src2_ = SourceConfig({ sourceType: SOURCE_STABLE, source: address(0), capOperand: 0 });
        SourceConfig memory src3_ = SourceConfig({ sourceType: SOURCE_NOT_SET, source: address(0), capOperand: 0 });

        vm.prank(admin);
        usdOracle.setSourceConfig(TOKEN, src1_, src2_, src3_);
        _setMarketKey(false);

        bytes32 keyConfigSlot_ = _oracleKeyConfigSlot(TOKEN, 0, 1, 1);
        bytes32 primarySlot1_ = _tokenSourceBaseSlot(TOKEN);
        bytes32 primarySlot2_ = bytes32(uint256(primarySlot1_) + 1);

        vm.record();
        usdOracle.getPriceView(TOKEN, 0, true, true);
        (bytes32[] memory reads_, ) = vm.accesses(address(usdOracle));

        _assertRead(reads_, keyConfigSlot_, "key config must be read");
        _assertRead(reads_, primarySlot1_, "primary slot 0 must be read");
        _assertRead(reads_, primarySlot2_, "primary slot 1 must be read for leg 2");
        _assertNotRead(reads_, bytes32(uint256(primarySlot1_) + 2), "primary slot 2 must not be read");
        _assertNotRead(reads_, bytes32(uint256(primarySlot1_) + 3), "alt slot 3 must not be read");
    }

    function testReadPath_threeLegConfigReadsPrimarySlots0Through2() public {
        SourceConfig memory src1_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(chainlinkMock),
            capOperand: 0
        });
        SourceConfig memory src2_ = SourceConfig({ sourceType: SOURCE_STABLE, source: address(0), capOperand: 0 });
        SourceConfig memory src3_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(additionalChainlinkMock),
            capOperand: 0
        });

        vm.prank(admin);
        usdOracle.setSourceConfig(TOKEN, src1_, src2_, src3_);
        _setMarketKey(false);

        bytes32 keyConfigSlot_ = _oracleKeyConfigSlot(TOKEN, 0, 1, 1);
        bytes32 primarySlot1_ = _tokenSourceBaseSlot(TOKEN);

        vm.record();
        usdOracle.getPriceView(TOKEN, 0, true, true);
        (bytes32[] memory reads_, ) = vm.accesses(address(usdOracle));

        _assertRead(reads_, keyConfigSlot_, "key config must be read");
        _assertRead(reads_, primarySlot1_, "primary slot 0 must be read");
        _assertRead(reads_, bytes32(uint256(primarySlot1_) + 1), "primary slot 1 must be read");
        _assertRead(reads_, bytes32(uint256(primarySlot1_) + 2), "primary slot 2 must be read");
        _assertNotRead(reads_, bytes32(uint256(primarySlot1_) + 3), "alt slot 3 must not be read");
    }

    function testReadPath_oneSourceFallbackReadsOnlyPrimarySlot0AndAltSlot3() public {
        _setAltSourceConfig();
        _setMarketKey(true);
        chainlinkMock.setAnswer(0);

        bytes32 keyConfigSlot_ = _oracleKeyConfigSlot(TOKEN, 0, 1, 1);
        bytes32 primarySlot1_ = _tokenSourceBaseSlot(TOKEN);
        bytes32 altSlot1_ = bytes32(uint256(primarySlot1_) + 3);

        vm.record();
        assertEq(usdOracle.getPriceView(TOKEN, 0, true, true), 2e27);
        (bytes32[] memory reads_, ) = vm.accesses(address(usdOracle));

        _assertRead(reads_, keyConfigSlot_, "key config must be read");
        _assertRead(reads_, primarySlot1_, "primary slot 0 must be read");
        _assertRead(reads_, altSlot1_, "alt slot 3 must be read");
        _assertNotRead(reads_, bytes32(uint256(primarySlot1_) + 1), "primary slot 1 must not be read");
        _assertNotRead(reads_, bytes32(uint256(primarySlot1_) + 2), "primary slot 2 must not be read");
        _assertNotRead(reads_, bytes32(uint256(altSlot1_) + 1), "alt slot 4 must not be read");
        _assertNotRead(reads_, bytes32(uint256(altSlot1_) + 2), "alt slot 5 must not be read");
    }

    function _tokenSourceBaseSlot(address token_) internal pure returns (bytes32) {
        return keccak256(abi.encode(token_, uint256(TOKEN_SOURCES_MAPPING_SLOT)));
    }

    function _additionalTokenSourceBaseSlot(address token_) internal pure returns (bytes32) {
        return keccak256(abi.encode(token_, uint256(ADDITIONAL_TOKEN_SOURCES_MAPPING_SLOT)));
    }

    function _oracleKeyConfigSlot(
        address token_,
        uint256 eMode_,
        uint256 isOperate_,
        uint256 isCollateral_
    ) internal pure returns (bytes32) {
        bytes32 keyHash_ = keccak256(abi.encode(token_, eMode_, isOperate_, isCollateral_));
        return keccak256(abi.encode(keyHash_, uint256(CONFIGS_MAPPING_SLOT)));
    }

    /// @dev TokenSources slot 0: source1, multiplier1, sourceType1-3, capOperand1, metadata, future slot 0 expansion.
    function _packPrimarySlot1(
        address source1_,
        int8 multiplier1_,
        uint8 sourceType1_,
        uint8 sourceType2_,
        uint8 sourceType3_,
        uint16 capOperand1_,
        uint8 pauseState_,
        uint8 tokenType_,
        uint8 decimals_,
        uint8 flagsBitmap_
    ) internal pure returns (uint256 packed_) {
        packed_ = uint256(uint160(source1_));
        packed_ |= uint256(uint8(uint256(int256(multiplier1_)))) << 160;
        packed_ |= uint256(sourceType1_) << 168;
        packed_ |= uint256(sourceType2_) << 176;
        packed_ |= uint256(sourceType3_) << 184;
        packed_ |= uint256(capOperand1_) << 192;
        packed_ |= uint256(pauseState_) << 208;
        packed_ |= uint256(tokenType_) << 216;
        packed_ |= uint256(decimals_) << 224;
        packed_ |= uint256(flagsBitmap_) << 232;
    }

    /// @dev TokenSources slots 1 / 2: multiplier at byte 0, source at byte 1, capOperand at byte 21.
    function _packPrimarySlot2(
        int8 multiplier_,
        address source_,
        uint16 capOperand_
    ) internal pure returns (uint256 packed_) {
        packed_ = uint256(uint8(uint256(int256(multiplier_))));
        packed_ |= uint256(uint160(source_)) << 8;
        packed_ |= uint256(capOperand_) << 168;
    }

    /// @dev Batched: the transient key does not survive the transaction boundary that separate
    ///      top-level calls would put between it and its setters.
    function _setMarketKey(bool enableFallback_) internal {
        bytes[] memory calls_ = new bytes[](enableFallback_ ? 3 : 2);
        calls_[0] = abi.encodeWithSelector(
            usdOracle.registerTransientOracleKey.selector,
            OracleKey({ token: TOKEN, eMode: 0, isOperate: 1, isCollateral: 1 })
        );
        calls_[1] = abi.encodeWithSelector(usdOracle.setPriceMode.selector, PRICE_MODE_MARKET);
        if (enableFallback_) {
            calls_[2] = abi.encodeWithSelector(usdOracle.enableFallback.selector);
        }

        vm.prank(admin);
        IOracleAdminMulticall(address(usdOracle)).multicall(calls_);
    }

    function _setAltSourceConfig() internal {
        SourceConfig memory alt1_ = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(altChainlinkMock),
            capOperand: 0
        });
        SourceConfig memory empty_ = SourceConfig({ sourceType: SOURCE_NOT_SET, source: address(0), capOperand: 0 });

        vm.prank(admin);
        usdOracle.setAltSourceConfig(TOKEN, alt1_, empty_, empty_);
    }

    function _assertRead(bytes32[] memory reads_, bytes32 slot_, string memory message_) internal pure {
        for (uint256 i = 0; i < reads_.length; i++) {
            if (reads_[i] == slot_) {
                return;
            }
        }
        revert(message_);
    }

    function _assertNotRead(bytes32[] memory reads_, bytes32 slot_, string memory message_) internal pure {
        for (uint256 i = 0; i < reads_.length; i++) {
            if (reads_[i] == slot_) {
                revert(message_);
            }
        }
    }
}
