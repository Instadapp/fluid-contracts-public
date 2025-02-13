//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { IAllowanceTransfer } from "../../../contracts/protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";
import { IFToken } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";

import { fTokenBaseSetUp } from "./fToken.t.sol";
import { UserModuleMock } from "./mocks/userModuleMock.sol";

abstract contract fTokenPermit2DepositsTestBase is fTokenBaseSetUp {
    bytes32 public constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
    bytes32 public constant _PERMIT_SINGLE_TYPEHASH =
        keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    uint160 constant defaultAmount = 10 ** 18;

    function _createToken(FluidLendingFactory lendingFactory_, IERC20 asset_) internal virtual override returns (IERC4626) {
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        vm.prank(admin);
        return IERC4626(lendingFactory_.createToken(address(asset_), "fToken", false));
    }

    function createPermit() internal view returns (IAllowanceTransfer.PermitSingle memory) {
        return
            IAllowanceTransfer.PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: address(underlying),
                    amount: defaultAmount,
                    expiration: type(uint48).max,
                    nonce: 0
                }),
                spender: address(lendingFToken),
                sigDeadline: block.timestamp
            });
    }

    function getSignature(IAllowanceTransfer.PermitSingle memory permit) internal view returns (bytes memory) {
        (, , , IAllowanceTransfer permit2, , , , , ) = lendingFToken.getData();
        return getPermitSignature(permit, alicePrivateKey, permit2.DOMAIN_SEPARATOR());
    }

    
    function getPermitSignatureRaw(
        IAllowanceTransfer.PermitSingle memory permit,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 permitHash = keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, permit.details));

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(_PERMIT_SINGLE_TYPEHASH, permitHash, permit.spender, permit.sigDeadline))
            )
        );

        (v, r, s) = vm.sign(privateKey, msgHash);
    }

    function getPermitSignature(
        IAllowanceTransfer.PermitSingle memory permit,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignatureRaw(permit, privateKey, domainSeparator);
        return bytes.concat(r, s, bytes1(v));
    }
}

contract fTokenPermit2DepositsTest is fTokenPermit2DepositsTestBase {
    function setUp() public virtual override {
        // native underlying tests must run in fork for WETH support
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        super.setUp();

        (, , , IAllowanceTransfer permit2, , , , , ) = lendingFToken.getData();
        // approve permit2 contract for alice
        _setApproval(underlying, address(permit2), alice);
    }

    function test_SetUpState() public {
        (, , , IAllowanceTransfer permit2, , , , , ) = lendingFToken.getData();
        assertEq(address(permit2), 0x000000000022D473030F116dDEE9F6B43aC78BA3);
    }

    function test_depositWithSignature() public {
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        IAllowanceTransfer.PermitSingle memory permit = createPermit();
        bytes memory signature = getSignature(permit);

        vm.prank(alice);
        uint256 shares = lendingFToken.depositWithSignature(defaultAmount, alice, 0, permit, signature);

        assertEqDecimal(shares, defaultAmount, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), defaultAmount, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), defaultAmount);
    }

    function test_depositWithSignature_RevertIfMinAmountOut() public {
        IAllowanceTransfer.PermitSingle memory permit = createPermit();
        bytes memory signature = getSignature(permit);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MinAmountOut));
        lendingFToken.depositWithSignature(defaultAmount, alice, defaultAmount + 1, permit, signature);
    }

    function test_mintWithSignature() public {
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        IAllowanceTransfer.PermitSingle memory permit = createPermit();
        bytes memory signature = getSignature(permit);

        vm.prank(alice);
        uint256 shares = lendingFToken.mintWithSignature(defaultAmount, alice, defaultAmount, permit, signature);

        assertEqDecimal(shares, defaultAmount, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), defaultAmount, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), defaultAmount);
    }

    function test_mintWithSignature_RevertIfMaxAssetsIsSurpassed() public {
        IAllowanceTransfer.PermitSingle memory permit = createPermit();
        bytes memory signature = getSignature(permit);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MaxAmount));
        lendingFToken.mintWithSignature(defaultAmount, alice, defaultAmount - 1, permit, signature);
    }

    function test_liquidityCallback_RevertIfSenderIsNotLiquidityContract() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.liquidityCallback(address(underlying), 0, new bytes(0));
    }

    function test_liquidityCallback_RevertIfSenderIsNotAssetContract() public {
        vm.prank(address(liquidity));
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.liquidityCallback(address(0), 0, new bytes(0));
    }

    function test_liquidityCallback_RevertIfIsNotPermit2() public virtual {
        address originalUserModule = liquidity.getSigsImplementation(UserModuleMock.operate.selector);
        vm.prank(admin);
        liquidity.removeImplementation(originalUserModule);

        // this UserModuleMock returns abi.encode(from_, false) as a callback.
        UserModuleMock userModuleMock = new UserModuleMock();

        vm.prank(admin);
        liquidity.addImplementation(address(userModuleMock), userSigs);

        IAllowanceTransfer.PermitSingle memory permit = createPermit();
        bytes memory signature = getSignature(permit);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__InvalidParams));
        lendingFToken.depositWithSignature(defaultAmount, alice, defaultAmount, permit, signature);
    }
}

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

contract fTokenPermit2DepositsEIP2612RevertsTest is fTokenPermit2DepositsTestBase {
    function test_depositWithSignatureEIP2612_Revert() public {
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
        vm.expectRevert();
        vm.prank(alice);
        lendingFToken.depositWithSignatureEIP2612(DEFAULT_AMOUNT, alice, 0, deadline, signature);
    }

    function test_mintWithSignatureEIP2612_Revert() public {
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
        vm.expectRevert();
        vm.prank(alice);
        lendingFToken.depositWithSignatureEIP2612(DEFAULT_AMOUNT, alice, DEFAULT_AMOUNT, deadline, signature);
    }

    function _getPermitHash(
        IERC2612 /* token */,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) private pure returns (bytes32 h) {
        bytes32 domainHash = keccak256("token.DOMAIN_SEPARATOR()"); // for revert test just use some bytes32
        bytes32 typeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", domainHash, structHash));
    }
}
