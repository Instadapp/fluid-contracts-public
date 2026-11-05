//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

import { FluidLendingStakingRewards } from "../../../contracts/protocols/lending/stakingRewards/main.sol";
import { IERC2612 } from "../../../contracts/protocols/lending/interfaces/permit2/IERC2612.sol";

/// @dev minimal EIP-2612 token kept outside the Liquidity module so a multi-billion-token balance
///      doesn't hit Liquidity's own supply-amount bound instead of the one under test here.
contract MockPermitToken is ERC20, ERC20Permit {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC20Permit(name_) {}

    function mint(address to_, uint256 amount_) external {
        _mint(to_, amount_);
    }
}

/// @title Fork-free port of stakingRewards.t.sol's uint128 accounting-bound regression tests.
/// @dev stakingRewards.t.sol is excluded from CI by `.github/fork-test-paths.txt` (it forks for an
///      unrelated native-underlying scenario in the same file), so its bound tests never run there.
///      This harness reaches the same production code without a fork.
contract FluidLendingStakingRewardsUint128BoundTest is Test {
    FluidLendingStakingRewards internal stakingRewards;
    MockPermitToken internal stakeToken;
    MockPermitToken internal rewardsToken;

    address internal alice;
    uint256 internal alicePrivateKey;

    // `_balances` is slot 7 on `FluidLendingStakingRewards` (verified via `forge inspect storage-layout`).
    uint256 internal constant BALANCES_SLOT = 7;

    function setUp() public {
        (alice, alicePrivateKey) = makeAddrAndKey("alice");

        stakeToken = new MockPermitToken("Mock Stake", "STK");
        rewardsToken = new MockPermitToken("Mock Reward", "RWD");
        stakingRewards = new FluidLendingStakingRewards(
            makeAddr("stakingOwner"),
            IERC20(address(rewardsToken)),
            IERC20(address(stakeToken)),
            100 days
        );
    }

    function _mintAndApprove(address user_, uint256 amount_) internal {
        stakeToken.mint(user_, amount_);
        vm.prank(user_);
        stakeToken.approve(address(stakingRewards), amount_);
    }

    function _getPermitHash(
        IERC2612 token_,
        address owner_,
        address spender_,
        uint256 value_,
        uint256 nonce_,
        uint256 deadline_
    ) private view returns (bytes32) {
        bytes32 typeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, owner_, spender_, value_, nonce_, deadline_));
        return keccak256(abi.encodePacked("\x19\x01", token_.DOMAIN_SEPARATOR(), structHash));
    }

    // `_totalSupply` is uint128; `stake`/`stakeWithPermit`/`withdraw` must reject amounts that would
    // silently truncate it instead of reverting.

    function test_stake_RevertOnUint128Overflow() public {
        uint256 overflow = uint256(type(uint128).max) + 1;
        _mintAndApprove(alice, overflow);

        vm.prank(alice);
        vm.expectRevert("Amount exceeds uint128");
        stakingRewards.stake(overflow);
    }

    function test_stake_AcceptsUint128MaxBoundary() public {
        // fresh `_totalSupply` is 0, so 0 + uint128(type(uint128).max) cannot overflow.
        uint256 boundary = type(uint128).max;
        _mintAndApprove(alice, boundary);

        vm.prank(alice);
        stakingRewards.stake(boundary);

        assertEq(stakingRewards.totalSupply(), boundary);
        assertEq(stakingRewards.balanceOf(alice), boundary);
    }

    function test_stakeWithPermit_RevertOnUint128Overflow() public {
        uint256 overflow = uint256(type(uint128).max) + 1;

        // alice must actually hold the tokens for the truncation to be observable on unpatched code
        // (a bad-signature revert on base would otherwise mask the missing bound, not prove it).
        stakeToken.mint(alice, overflow);

        uint256 deadline = block.timestamp + 10 minutes;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(IERC2612(address(stakeToken)), alice, address(stakingRewards), overflow, 0, deadline)
        );

        vm.prank(alice);
        vm.expectRevert("Amount exceeds uint128");
        stakingRewards.stakeWithPermit(overflow, deadline, v, r, s);
    }

    function test_withdraw_RevertOnUint128Overflow() public {
        uint256 overflow = uint256(type(uint128).max) + 1;

        // fund the contract with real tokens so a non-reverting withdraw on unpatched code would
        // actually pay out, not just skip for lack of balance.
        stakeToken.mint(address(stakingRewards), overflow);

        // isolate `withdraw()`'s own guard: inject the balance it would see post-stake directly,
        // instead of re-deriving it through the already-covered `stake()` path.
        vm.store(address(stakingRewards), keccak256(abi.encode(alice, BALANCES_SLOT)), bytes32(overflow));

        vm.prank(alice);
        vm.expectRevert("Amount exceeds uint128");
        stakingRewards.withdraw(overflow);
    }
}
