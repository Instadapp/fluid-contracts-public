// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidDexReservesResolver } from "../../../../contracts/periphery/resolvers/dexReserves/main.sol";
import { Structs } from "../../../../contracts/periphery/resolvers/dexReserves/structs.sol";
import { Structs as LiquidityResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { IFluidDexT1 } from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";

contract MockDexReservesToken {
    mapping(address => uint256) public balanceOf;

    function setBalance(address account_, uint256 amount_) external {
        balanceOf[account_] = amount_;
    }
}

contract MockDexReservesDex {
    address public immutable token0;
    address public immutable token1;
    uint256 public immutable dexVariables2;

    constructor(address token0_, address token1_) {
        token0 = token0_;
        token1 = token1_;
        dexVariables2 = (uint256(1000) << 228) | (uint256(1000) << 238);
    }

    function readFromStorage(bytes32) external view returns (uint256) {
        return dexVariables2;
    }

    function constantsView() external view returns (IFluidDexT1.ConstantViews memory constantsView_) {
        constantsView_.token0 = token0;
        constantsView_.token1 = token1;
    }
}

contract MockDexReservesLiquidityResolver {
    mapping(address => LiquidityResolverStructs.UserSupplyData) internal userSupplyData;
    mapping(address => LiquidityResolverStructs.OverallTokenData) internal overallTokenData;

    function setSupplyData(
        address token_,
        uint256 supply_,
        uint256 withdrawable_,
        uint256 totalSupply_,
        uint256 totalBorrow_
    ) external {
        userSupplyData[token_].supply = supply_;
        userSupplyData[token_].withdrawable = withdrawable_;
        userSupplyData[token_].expandPercent = 10000;
        userSupplyData[token_].expandDuration = 1 days;

        overallTokenData[token_].totalSupply = totalSupply_;
        overallTokenData[token_].totalBorrow = totalBorrow_;
        overallTokenData[token_].maxUtilization = 10000;
    }

    function getUserSupplyData(
        address,
        address token_
    )
        external
        view
        returns (
            LiquidityResolverStructs.UserSupplyData memory userSupplyData_,
            LiquidityResolverStructs.OverallTokenData memory overallTokenData_
        )
    {
        return (userSupplyData[token_], overallTokenData[token_]);
    }

    function getUserBorrowData(
        address,
        address
    )
        external
        pure
        returns (
            LiquidityResolverStructs.UserBorrowData memory userBorrowData_,
            LiquidityResolverStructs.OverallTokenData memory overallTokenData_
        )
    {
        userBorrowData_.maxBorrowLimit = type(uint256).max;
        return (userBorrowData_, overallTokenData_);
    }
}

contract FluidDexReservesResolverLimitsMockedTest is Test {
    address internal constant LIQUIDITY = address(0x1111);

    function test_getDexLimits_UsesToken0WithdrawableForToken0Cap() public {
        MockDexReservesToken token0_ = new MockDexReservesToken();
        MockDexReservesToken token1_ = new MockDexReservesToken();
        token0_.setBalance(LIQUIDITY, 1_000);
        token1_.setBalance(LIQUIDITY, 1_000);

        MockDexReservesDex dex_ = new MockDexReservesDex(address(token0_), address(token1_));
        MockDexReservesLiquidityResolver liquidityResolver_ = new MockDexReservesLiquidityResolver();

        // token0 utilization leaves 50 available, but its user withdrawable cap is 11.
        // token1 withdrawable is deliberately higher than 50 to catch token0/token1 mixups.
        liquidityResolver_.setSupplyData(address(token0_), 1_000, 11, 1_000, 950);
        liquidityResolver_.setSupplyData(address(token1_), 1_000, 99, 1_000, 900);

        FluidDexReservesResolver resolver_ = new FluidDexReservesResolver(
            address(0),
            LIQUIDITY,
            address(liquidityResolver_)
        );
        Structs.DexLimits memory limits_ = resolver_.getDexLimits(address(dex_));

        assertEq(limits_.withdrawableToken0.available, 11);
    }
}
