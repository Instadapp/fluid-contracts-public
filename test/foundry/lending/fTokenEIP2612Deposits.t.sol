//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { MockERC20Permit } from "../utils/mocks/MockERC20Permit.sol";
import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityAdminModule } from "../../../contracts/liquidity/adminModule/main.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";

import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { LendingRewardsRateMockModel } from "./mocks/rewardsMock.sol";
import { RandomAddresses } from "../utils/RandomAddresses.sol";

import { SigUtils } from "./helper/sigUtils.sol";
import { fTokenBaseSetUp } from "./fToken.t.sol";

interface IERC2612 is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

abstract contract fTokenEIP2612DepositsTestTestBase is fTokenBaseSetUp {
    function _createToken(FluidLendingFactory lendingFactory_, IERC20 asset_) internal virtual override returns (IERC4626) {
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        vm.prank(admin);
        return IERC4626(lendingFactory_.createToken(address(asset_), "fToken", false));
    }

    function _createUnderlying() internal virtual override returns (address) {
        MockERC20Permit mockERC20 = new MockERC20Permit("TestPermitToken", "TestPRM");

        return address(mockERC20);
    }
}

contract fTokenEIP2612DepositsTest is fTokenEIP2612DepositsTestTestBase, RandomAddresses {
    uint256 constant MINIMUM_AMOUNT_OUT = DEFAULT_AMOUNT;

    function test_depositWithSignatureEIP2612_RevertWhenSharesDoNotMeetMinimumAmount() public {
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(underlying)),
                alice,
                address(lendingFToken),
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MinAmountOut));
        lendingFToken.depositWithSignatureEIP2612(DEFAULT_AMOUNT, alice, MINIMUM_AMOUNT_OUT + 1, deadline, signature);
    }

    function test_depositWithSignatureEIP2612() public {
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(underlying)),
                alice,
                address(lendingFToken),
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        lendingFToken.depositWithSignatureEIP2612(DEFAULT_AMOUNT, alice, MINIMUM_AMOUNT_OUT, deadline, signature);

        assertEq(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);
    }

    function test_mintWithSignatureEIP2612_RevertWhenMaxAssetsIsSurpassed() public {
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(underlying)),
                alice,
                address(lendingFToken),
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(alice);

        // will cause a revert because DEFAULT_AMOUNT of assets is required to mint DEFAULT_AMOUNT of shares at exchange price 1 = 1
        uint256 maximumAmountIn_ = DEFAULT_AMOUNT - 1;

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MaxAmount));
        lendingFToken.mintWithSignatureEIP2612(DEFAULT_AMOUNT, alice, maximumAmountIn_, deadline, signature);
    }

    function test_mintWithSignatureEIP2612() public {
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(underlying)),
                alice,
                address(lendingFToken),
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        lendingFToken.mintWithSignatureEIP2612(DEFAULT_AMOUNT, alice, DEFAULT_AMOUNT, deadline, signature);

        assertEq(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);
    }

    function test_liquidityCallback_RevertIfSenderIsNotLiquidityContract() public {
        // vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.liquidityCallback(address(underlying), DEFAULT_AMOUNT, new bytes(0));
    }

    function test_liquidityCallback_RevertIfAssetIsInvalid() public {
        address invalidAsset = randomAddresses[0];
        vm.prank(address(liquidity));
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.liquidityCallback(invalidAsset, DEFAULT_AMOUNT, new bytes(0));
    }

    function test_liquidityCallback() public {
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(underlying)),
                alice,
                address(lendingFToken),
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        uint256 liquidityBalanceBefore = IERC20(address(underlying)).balanceOf(address(liquidity));
        uint256 aliceBalanceBefore = IERC20(address(underlying)).balanceOf(address(alice));
        vm.prank(alice);
        lendingFToken.depositWithSignatureEIP2612(DEFAULT_AMOUNT, alice, MINIMUM_AMOUNT_OUT, deadline, signature); // will reach callback
        uint256 liquidityBalanceAfter = IERC20(address(underlying)).balanceOf(address(liquidity));
        uint256 aliceBalanceAfter = IERC20(address(underlying)).balanceOf(address(alice));
        assertEq(aliceBalanceAfter, aliceBalanceBefore - DEFAULT_AMOUNT);
        assertEq(liquidityBalanceAfter, liquidityBalanceBefore + DEFAULT_AMOUNT);
    }

    function _getPermitHash(
        IERC2612 token,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) private view returns (bytes32 h) {
        bytes32 domainHash = token.DOMAIN_SEPARATOR();
        bytes32 typeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", domainHash, structHash));
    }
}
