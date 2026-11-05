// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { CREATE3 } from "solady/utils/CREATE3.sol";
import { SSTORE2 } from "solady/utils/SSTORE2.sol";

import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { FluidSmartLendingFactory } from "../../../contracts/protocols/dex/smartLending/factory/main.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";

contract SoladyCompatibilityHarness {
    function write(bytes memory data_) external returns (address) {
        return SSTORE2.write(data_);
    }

    function read(address pointer_) external view returns (bytes memory) {
        return SSTORE2.read(pointer_);
    }

    function predict(bytes32 salt_) external view returns (address) {
        return CREATE3.predictDeterministicAddress(salt_);
    }

    function deploy(bytes memory creationCode_, bytes32 salt_) external returns (address) {
        return CREATE3.deployDeterministic(0, creationCode_, salt_);
    }
}

contract Create3Target {
    uint256 public immutable value;

    constructor(uint256 value_) {
        value = value_;
    }
}

contract SoladyCompatibilityTest is Test {
    bytes32 internal constant CREATE3_PROXY_INITCODE_HASH =
        0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

    SoladyCompatibilityHarness internal harness;

    function setUp() public {
        harness = new SoladyCompatibilityHarness();
    }

    function testSstore2UsesLegacyCompatiblePointerFormat() public {
        bytes memory data_ = hex"010203040506";
        address pointer_ = harness.write(data_);

        assertEq(harness.read(pointer_), data_);

        bytes memory runtimeCode_ = pointer_.code;
        assertEq(uint8(runtimeCode_[0]), 0);
        assertEq(_sliceAfterStop(runtimeCode_), data_);
    }

    function testCreate3PredictionMatchesLegacyFormulaAndDeployment() public {
        bytes32 salt_ = keccak256("fluid-solady-migration");
        address predicted_ = _legacyCreate3Address(address(harness), salt_);

        assertEq(harness.predict(salt_), predicted_);

        address deployed_ = harness.deploy(abi.encodePacked(type(Create3Target).creationCode, abi.encode(42)), salt_);
        assertEq(deployed_, predicted_);
        assertEq(Create3Target(deployed_).value(), 42);
    }

    function testCreate3ProxyHashMatchesSolmateProxyBytecode() public {
        assertEq(CREATE3.PROXY_INITCODE_HASH, keccak256(hex"67363d3d37363d34f03d5260086018f3"));
        assertEq(CREATE3_PROXY_INITCODE_HASH, keccak256(hex"67363d3d37363d34f03d5260086018f3"));
    }

    function testSoladyReadsSolmateFormatPointers() public {
        uint256[] memory lengths_ = new uint256[](4);
        lengths_[0] = 0;
        lengths_[1] = 1;
        lengths_[2] = 33;
        lengths_[3] = 24_575;

        for (uint256 i = 0; i < lengths_.length; ++i) {
            uint256 len_ = lengths_[i];
            bytes memory data_ = new bytes(len_);
            for (uint256 j = 0; j < len_; ++j) {
                data_[j] = bytes32(keccak256(abi.encode(j)))[0];
            }

            bytes memory initCode_ = abi.encodePacked(hex"600B5981380380925939F3", hex"00", data_);
            address pointer_;
            assembly {
                pointer_ := create(0, add(initCode_, 0x20), mload(initCode_))
            }
            require(pointer_ != address(0));

            assertEq(harness.read(pointer_), data_);
            assertEq(pointer_.code.length, data_.length + 1);
        }
    }

    function testCreate3KeepsLiveFTokenAddresses() public {
        address liquidity_ = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
        address owner_ = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
        address factoryMainnet_ = 0x54B91A0D94cb471F37f949c60F7Fa7935b551D03;

        FluidLendingFactory local_ = new FluidLendingFactory(IFluidLiquidity(liquidity_), owner_);
        vm.etch(factoryMainnet_, address(local_).code);
        FluidLendingFactory factory_ = FluidLendingFactory(factoryMainnet_);

        address usdc_ = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address usdt_ = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address wsteth_ = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        address gho_ = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
        address weth_ = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        assertEq(factory_.computeToken(usdc_, "fToken"), 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33);
        assertEq(factory_.computeToken(usdt_, "fToken"), 0x5C20B550819128074FD538Edf79791733ccEdd18);
        assertEq(factory_.computeToken(wsteth_, "fToken"), 0x2411802D8BEA09be0aF8fD8D08314a63e706b29C);
        assertEq(factory_.computeToken(gho_, "fToken"), 0x6A29A46E21C730DcA1d8b23d637c101cec605C5B);
        assertEq(factory_.computeToken(weth_, "NativeUnderlying"), 0x90551c1795392094FE6D29B758EcCD233cFAa260);
    }

    function testCreate3KeepsLiveSmartLendingAddresses() public {
        address dexFactory_ = 0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085;
        address liquidity_ = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
        address owner_ = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
        address factoryMainnet_ = 0xe57227C7d5900165344b190fc7aa580bceb53B9B;

        FluidSmartLendingFactory local_ = new FluidSmartLendingFactory(dexFactory_, liquidity_, owner_);
        vm.etch(factoryMainnet_, address(local_).code);
        FluidSmartLendingFactory factory_ = FluidSmartLendingFactory(factoryMainnet_);

        assertEq(factory_.getSmartLendingAddress(19), 0xb210249Bc59FE77D29eb5F0e566D60CB2B010EF1);
        assertEq(factory_.getSmartLendingAddress(20), 0x9b1f75ea07723F331996831f6d04AD4900d1A3B3);
        assertEq(factory_.getSmartLendingAddress(23), 0xD2245ee5C3099d65a3d0fdCecA0f71Cc4aA8f0FF);
    }

    function _legacyCreate3Address(address deployer_, bytes32 salt_) internal pure returns (address) {
        address proxy_ = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer_, salt_, CREATE3_PROXY_INITCODE_HASH))))
        );
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy_, hex"01")))));
    }

    function _sliceAfterStop(bytes memory code_) internal pure returns (bytes memory data_) {
        data_ = new bytes(code_.length - 1);
        for (uint256 i = 1; i < code_.length; ++i) {
            data_[i - 1] = code_[i];
        }
    }
}
