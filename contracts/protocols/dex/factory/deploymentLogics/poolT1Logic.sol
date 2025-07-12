// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";

import { Error } from "../../error.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { IFluidDexFactory } from "../../interfaces/iDexFactory.sol";
import { MiniDeployer } from "../deploymentHelpers/miniDeployer.sol";
import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";
import { BytesSliceAndConcat } from "../../../../libraries/bytesSliceAndConcat.sol";

import { IFluidDexT1 } from "../../interfaces/iDexT1.sol";
import { FluidDexT1Shift } from "../../poolT1/coreModule/core/shift.sol";
import { FluidDexT1Admin } from "../../poolT1/adminModule/main.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract FluidDexT1DeploymentLogic is Error {
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev SSTORE2 pointer for the PoolT1 creation code. Stored externally to reduce factory bytecode (in 2 parts)
    address internal immutable POOL_T1_CREATIONCODE_ADDRESS_1;
    address internal immutable POOL_T1_CREATIONCODE_ADDRESS_2;

    /// @dev SSTORE2 pointers for the creation code of various operations contracts
    address internal immutable COL_OPERATIONS_CREATIONCODE_ADDRESS;
    address internal immutable DEBT_OPERATIONS_CREATIONCODE_ADDRESS;
    address internal immutable PERFECT_OPERATIONS_AND_SWAP_OUT_CREATIONCODE_ADDRESS_1;
    address internal immutable PERFECT_OPERATIONS_AND_SWAP_OUT_CREATIONCODE_ADDRESS_2;

    /// @notice address of liquidity contract
    address public immutable LIQUIDITY;

    /// @notice address of dexfactory contract
    address public immutable DEX_FACTORY;

    /// @notice address of Admin implementation
    address public immutable ADMIN_IMPLEMENTATION;

    /// @notice address of Shift implementation
    address public immutable SHIFT_IMPLEMENTATION;

    /// @notice address of Deployer Contract
    address public immutable CONTRACT_DEPLOYER;

    /// @notice address of MiniDeployer Contract
    MiniDeployer public immutable MINI_DEPLOYER;

    /// @notice address of this contract
    address public immutable ADDRESS_THIS;

    /// @notice Emitted when a new dexT1 is deployed.
    /// @param dex The address of the newly deployed dex.
    /// @param dexId The id of the newly deployed dex.
    /// @param supplyToken The address of the supply token.
    /// @param borrowToken The address of the borrow token.
    event DexT1Deployed(address indexed dex, uint256 dexId, address indexed supplyToken, address indexed borrowToken);

    /// @dev                            Deploys a contract using the CREATE opcode with the provided bytecode (`bytecode_`).
    ///                                 This is an internal function, meant to be used within the contract to facilitate the deployment of other contracts.
    /// @param bytecode_                The bytecode of the contract to be deployed.
    /// @return address_                Returns the address of the deployed contract.
    function _deploy(bytes memory bytecode_) internal returns (address address_) {
        if (bytecode_.length == 0) {
            revert FluidDexError(ErrorTypes.DexFactory__InvalidOperation);
        }
        /// @solidity memory-safe-assembly
        assembly {
            address_ := create(0, add(bytecode_, 0x20), mload(bytecode_))
        }
        if (address_ == address(0)) {
            revert FluidDexError(ErrorTypes.DexFactory__InvalidOperation);
        }
    }

    constructor(
        address liquidity_,
        address dexFactory_,
        address contractDeployer_,
        address colOperations_,
        address debtOperations_,
        address perfectOperationsAndSwapOut1_,
        address perfectOperationsAndSwapOut2_,
        address mainAddress1_,
        address mainAddress2_
    ) {
        LIQUIDITY = liquidity_;
        DEX_FACTORY = dexFactory_;
        CONTRACT_DEPLOYER = contractDeployer_;

        POOL_T1_CREATIONCODE_ADDRESS_1 = mainAddress1_;
        POOL_T1_CREATIONCODE_ADDRESS_2 = mainAddress2_;

        ADDRESS_THIS = address(this);

        // Deploy mini deployer
        MINI_DEPLOYER = new MiniDeployer(DEX_FACTORY);

        // Deploy admin implementation
        FluidDexT1Admin adminImplementation = new FluidDexT1Admin();
        ADMIN_IMPLEMENTATION = address(adminImplementation);

        // Deploy shift implementation
        FluidDexT1Shift shiftImplementation = new FluidDexT1Shift(CONTRACT_DEPLOYER);
        SHIFT_IMPLEMENTATION = address(shiftImplementation);

        COL_OPERATIONS_CREATIONCODE_ADDRESS = colOperations_;
        DEBT_OPERATIONS_CREATIONCODE_ADDRESS = debtOperations_;
        PERFECT_OPERATIONS_AND_SWAP_OUT_CREATIONCODE_ADDRESS_1 = perfectOperationsAndSwapOut1_;
        PERFECT_OPERATIONS_AND_SWAP_OUT_CREATIONCODE_ADDRESS_2 = perfectOperationsAndSwapOut2_;
    }

    function dexT1(
        address token0_,
        address token1_,
        uint256 oracleMapping_
    ) external returns (bytes memory dexCreationBytecode_) {
        if (address(this) == ADDRESS_THIS) revert FluidDexError(ErrorTypes.DexFactory__OnlyDelegateCallAllowed);

        if (token0_ == token1_) revert FluidDexError(ErrorTypes.DexFactory__SameTokenNotAllowed);
        if (token0_ > token1_) revert FluidDexError(ErrorTypes.DexFactory__TokenConfigNotProper);

        IFluidDexT1.ConstantViews memory constants_;
        constants_.liquidity = LIQUIDITY;
        constants_.factory = address(this);
        constants_.implementations.shift = SHIFT_IMPLEMENTATION;
        constants_.deployerContract = CONTRACT_DEPLOYER;
        constants_.token0 = token0_;
        constants_.token1 = token1_;
        constants_.dexId = IFluidDexFactory(address(this)).totalDexes();
        constants_.oracleMapping = oracleMapping_;

        address dex_ = IFluidDexFactory(address(this)).getDexAddress(constants_.dexId);

        constants_ = _calculateLiquidityDexSlots(constants_, dex_);

        // Deploy perfect operations and oracle implementation
        address perfectOperationsAndOracle_ = MINI_DEPLOYER.deployContract(
            abi.encodePacked(perfectOperationsCreationCode(), abi.encode(constants_))
        );

        // Deploy col operations implementation through mini deployer
        address colOperations_ = MINI_DEPLOYER.deployContract(
            abi.encodePacked(colOperationsCreationCode(), abi.encode(constants_))
        );

        // Deploy debt operations implementation
        address debtOperations_ = MINI_DEPLOYER.deployContract(
            abi.encodePacked(debtOperationsCreationCode(), abi.encode(constants_))
        );

        constants_.implementations.admin = ADMIN_IMPLEMENTATION;
        constants_.implementations.perfectOperationsAndOracle = perfectOperationsAndOracle_;
        constants_.implementations.colOperations = colOperations_;
        constants_.implementations.debtOperations = debtOperations_;

        dexCreationBytecode_ = abi.encodePacked(dexT1CreationBytecode(), abi.encode(constants_));

        emit DexT1Deployed(dex_, constants_.dexId, token0_, token1_);

        return dexCreationBytecode_;
    }

    /// @notice returns the stored DexT1 creation bytecode
    function dexT1CreationBytecode() public view returns (bytes memory) {
        return
            BytesSliceAndConcat.bytesConcat(
                SSTORE2.read(POOL_T1_CREATIONCODE_ADDRESS_1),
                SSTORE2.read(POOL_T1_CREATIONCODE_ADDRESS_2)
            );
    }

    /// @dev Retrieves the creation code for the FluidDexT1OperationsCol contract
    function colOperationsCreationCode() public view returns (bytes memory) {
        return SSTORE2.read(COL_OPERATIONS_CREATIONCODE_ADDRESS);
    }

    /// @dev Retrieves the creation code for the FluidDexT1OperationsDebt contract
    function debtOperationsCreationCode() public view returns (bytes memory) {
        return SSTORE2.read(DEBT_OPERATIONS_CREATIONCODE_ADDRESS);
    }

    /// @dev Retrieves the creation code for the FluidDexT1PerfectOperations contract
    function perfectOperationsCreationCode() public view returns (bytes memory) {
        return
            BytesSliceAndConcat.bytesConcat(
                SSTORE2.read(PERFECT_OPERATIONS_AND_SWAP_OUT_CREATIONCODE_ADDRESS_1),
                SSTORE2.read(PERFECT_OPERATIONS_AND_SWAP_OUT_CREATIONCODE_ADDRESS_2)
            );
    }

    /// @dev                          Calculates the liquidity dex slots for the given supply token, borrow token, and dex (`dex_`).
    /// @param constants_             Constants struct as used in Dex T1
    /// @param dex_                   The address of the dex.
    /// @return liquidityDexSlots_    Returns the calculated liquidity dex slots set in the `IFluidDexT1.ConstantViews` struct.
    function _calculateLiquidityDexSlots(
        IFluidDexT1.ConstantViews memory constants_,
        address dex_
    ) private pure returns (IFluidDexT1.ConstantViews memory) {
        constants_.supplyToken0Slot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            dex_,
            constants_.token0
        );
        constants_.borrowToken0Slot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            dex_,
            constants_.token0
        );
        constants_.supplyToken1Slot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            dex_,
            constants_.token1
        );
        constants_.borrowToken1Slot = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            dex_,
            constants_.token1
        );
        constants_.exchangePriceToken0Slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.token0
        );
        constants_.exchangePriceToken1Slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            constants_.token1
        );

        return constants_;
    }
}
