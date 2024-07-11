//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { IFluidLendingRewardsRateModel  } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { IAllowanceTransfer } from "../../../contracts/protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";

import { Variables, Constants } from "../../../contracts/protocols/lending/fToken/variables.sol";
import { MockERC20 } from "../utils/mocks/MockERC20.sol";
import { RandomAddresses } from "../utils/RandomAddresses.sol";

import { Test } from "forge-std/Test.sol";

contract VariablesTest is Test, RandomAddresses {
    VariablesExposed variables;

    function setUp() public {
        address liquidityAddress = randomAddresses[0];
        address lendingFactoryAddress = randomAddresses[1];
        MockERC20 asset = new MockERC20("TestName", "TestSymbol");

        variables = new VariablesExposed(
            IFluidLiquidity(liquidityAddress),
            IFluidLendingFactory(lendingFactoryAddress),
            IERC20(asset)
        );
    }

    function test_initialState() public {
        assertEq(variables.name(), "Fluid TestName", "Token name should be prefixed");
        assertEq(variables.symbol(), "fTestSymbol", "Token symbol should be prefixed");
    }

    function test_validAddressModifier() public {
        (bool success, ) = address(variables).call(abi.encodeWithSignature("validAddress(address)", address(0)));
        assertTrue(!success, "Should revert for zero address");
    }
}

contract ConstantsTest is Test, RandomAddresses {
    ConstantsExposed constants;
    address liquidityAddress;
    address lendingFactoryAddress;
    MockERC20 asset;

    function setUp() public {
        liquidityAddress = randomAddresses[0];
        lendingFactoryAddress = randomAddresses[1];
        asset = new MockERC20("TestName", "TestSymbol");

        constants = new ConstantsExposed(
            IFluidLiquidity(liquidityAddress),
            IFluidLendingFactory(lendingFactoryAddress),
            IERC20(asset)
        );
    }

    function test_getLiquiditySlotLinksAsset() public {
        assertEq(address(asset), constants.exposed_getLiquiditySlotLinksAsset());
    }

    function test_LIQUIDITY() public {
        address liquidity = address(constants.exposed_LIQUIDITY());
        assertEq(liquidity, liquidityAddress);
    }

    function test_ASSET() public {
        address asset_ = address(constants.exposed_ASSET());
        assertEq(asset_, address(asset));
    }

    function test_LENDING_FACTORY() public {
        address lendingFactory = address(constants.exposed_LENDING_FACTORY());
        assertEq(lendingFactory, lendingFactoryAddress);
    }
}

contract VariablesExposed is Variables {
    constructor(
        IFluidLiquidity liquidity_,
        IFluidLendingFactory lendingFactory_,
        IERC20 asset_
    ) Variables(liquidity_, lendingFactory_, asset_) {}

    function exposed_liquidityExchangePrice() external view returns (uint64) {
        return _liquidityExchangePrice;
    }

    function exposed_tokenExchangePrice() external view returns (uint64) {
        return _tokenExchangePrice;
    }

    function exposed_lastUpdateTimestamp() external view returns (uint40) {
        return _lastUpdateTimestamp;
    }

    function exposed_status() external view returns (uint8) {
        return _status;
    }

    function exposed_rewardsActive() external view returns (bool) {
        return _rewardsActive;
    }

    function exposed_rewardsRateModel() external view returns (IFluidLendingRewardsRateModel ) {
        return _rewardsRateModel;
    }

    function getData()
        external
        pure
        override
        returns (
            IFluidLiquidity,
            IFluidLendingFactory,
            IFluidLendingRewardsRateModel ,
            IAllowanceTransfer,
            address,
            bool,
            uint256,
            uint256,
            uint256
        )
    {
        revert("Not implemented");
    }

    function asset() external pure override returns (address) {
        revert("Not implemented");
    }

    function convertToAssets(uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function convertToShares(uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function deposit(uint256, address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function rescueFunds(address) external pure override {
        revert("Not implemented");
    }

    function rebalance() external payable override returns (uint256) {
        revert("Not implemented");
    }

    function updateRebalancer(address) external pure override {
        revert("Not implemented");
    }

    function liquidityCallback(address, uint256, bytes calldata) external pure override {
        revert("Not implemented");
    }

    function maxDeposit(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function maxMint(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function maxRedeem(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function maxWithdraw(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function minDeposit() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function mint(uint256, address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function previewDeposit(uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function previewMint(uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function previewRedeem(uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function previewWithdraw(uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function redeem(uint256, address, address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function totalAssets() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function updateRates() external pure override returns (uint256, uint256) {
        revert("Not implemented");
    }

    function withdraw(uint256, address, address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function updateRewards(IFluidLendingRewardsRateModel ) external pure override {
        revert("Not implemented");
    }

    function depositWithSignature(
        uint256,
        address,
        uint256,
        IAllowanceTransfer.PermitSingle calldata,
        bytes calldata
    ) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function mintWithSignature(
        uint256,
        address,
        uint256,
        IAllowanceTransfer.PermitSingle calldata,
        bytes calldata
    ) external pure override returns (uint256) {
        revert("Not implemented");
    }
}

contract ConstantsExposed is Constants {
    constructor(
        IFluidLiquidity liquidity_,
        IFluidLendingFactory lendingFactory_,
        IERC20 asset_
    ) Constants(liquidity_, lendingFactory_, asset_) {}

    function exposed_getLiquiditySlotLinksAsset() external view returns (address) {
        return _getLiquiditySlotLinksAsset();
    }

    function exposed_LIQUIDITY() external view returns (IFluidLiquidity) {
        return LIQUIDITY;
    }

    function exposed_LENDING_FACTORY() external view returns (IFluidLendingFactory) {
        return LENDING_FACTORY;
    }

    function exposed_ASSET() external view returns (IERC20) {
        return ASSET;
    }
}
