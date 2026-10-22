// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidStETHResolver } from "../../../../contracts/periphery/resolvers/steth/main.sol";
import { IFluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { IFluidStETHQueue } from "../../../../contracts/protocols/steth/interfaces/iStETHQueue.sol";
import { Structs as StETHQueueStructs } from "../../../../contracts/protocols/steth/structs.sol";
import { ILidoWithdrawalQueue } from "../../../../contracts/protocols/steth/interfaces/external/iLidoWithdrawalQueue.sol";

contract MockStETHQueueClaims {
    mapping(address => mapping(uint256 => StETHQueueStructs.Claim)) internal _claims;

    function setClaim(address claimTo_, uint256 requestIdFrom_, uint40 requestIdTo_) external {
        _claims[claimTo_][requestIdFrom_] = StETHQueueStructs.Claim({
            borrowAmountRaw: 1,
            checkpoint: 1,
            requestIdTo: requestIdTo_
        });
    }

    function claims(address claimTo_, uint256 requestIdFrom_) external view returns (StETHQueueStructs.Claim memory) {
        return _claims[claimTo_][requestIdFrom_];
    }
}

contract MockLidoWithdrawalQueueStatus {
    mapping(uint256 => bool) public finalized;

    function setFinalized(uint256 requestId_, bool finalized_) external {
        finalized[requestId_] = finalized_;
    }

    function getWithdrawalStatus(
        uint256[] calldata requestIds_
    ) external view returns (ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses_) {
        statuses_ = new ILidoWithdrawalQueue.WithdrawalRequestStatus[](requestIds_.length);
        for (uint256 i; i < requestIds_.length; ++i) {
            statuses_[i].isFinalized = finalized[requestIds_[i]];
        }
    }
}

contract FluidStETHResolverClaimableTest is Test {
    address internal alice = makeAddr("alice");

    MockStETHQueueClaims internal queue;
    MockLidoWithdrawalQueueStatus internal lidoQueue;
    FluidStETHResolver internal resolver;

    function setUp() public {
        queue = new MockStETHQueueClaims();
        lidoQueue = new MockLidoWithdrawalQueueStatus();
        resolver = new FluidStETHResolver(
            IFluidStETHQueue(address(queue)),
            IFluidLiquidityResolver(makeAddr("liquidityResolver")),
            ILidoWithdrawalQueue(address(lidoQueue))
        );
    }

    function test_isClaimable_SingleRequest() public {
        queue.setClaim(alice, 7, 7);
        assertFalse(resolver.isClaimable(alice, 7));

        lidoQueue.setFinalized(7, true);
        assertTrue(resolver.isClaimable(alice, 7));
    }

    function test_isClaimable_MultiRequestAllFinalized() public {
        queue.setClaim(alice, 10, 12);
        lidoQueue.setFinalized(10, true);
        lidoQueue.setFinalized(11, true);
        lidoQueue.setFinalized(12, true);

        assertTrue(resolver.isClaimable(alice, 10));
    }

    function test_isClaimable_MultiRequestOneNotFinalized() public {
        queue.setClaim(alice, 10, 12);
        lidoQueue.setFinalized(10, true);
        lidoQueue.setFinalized(12, true);

        assertFalse(resolver.isClaimable(alice, 10));
    }

    function test_isClaimable_RevertIfNoClaimQueued() public {
        vm.expectRevert(FluidStETHResolver.FluidStETHResolver__NoClaimQueued.selector);
        resolver.isClaimable(alice, 1);
    }
}
