// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { SafeApprove } from "../../../contracts/libraries/safeApprove.sol";
import { SafeTransfer } from "../../../contracts/libraries/safeTransfer.sol";
import { LibsErrorTypes } from "../../../contracts/libraries/errorTypes.sol";

contract SafeTransferHarness {
    function transferFrom(address token_, address from_, address to_, uint256 amount_) external {
        SafeTransfer.safeTransferFrom(token_, from_, to_, amount_);
    }

    function transfer(address token_, address to_, uint256 amount_) external {
        SafeTransfer.safeTransfer(token_, to_, amount_);
    }

    function approve(address token_, address to_, uint256 amount_) external {
        SafeApprove.safeApprove(token_, to_, amount_);
    }

    function transferNative(address to_, uint256 amount_) external {
        SafeTransfer.safeTransferNative(to_, amount_);
    }

    /// @dev Calls the library with dirty upper bits on the address arguments and reports the memory the
    /// library must leave intact: the free memory pointer, the zero slot and an allocation made before the call.
    function transferProbe(
        address token_,
        address to_,
        uint256 amount_,
        uint96 dirt_
    ) external returns (uint256 fmpBefore_, uint256 fmpAfter_, uint256 zeroSlot_, bool canaryIntact_) {
        bytes memory canary_ = _canary();
        address dirtyTo_;
        assembly {
            fmpBefore_ := mload(0x40)
            dirtyTo_ := or(shl(160, dirt_), to_)
        }
        SafeTransfer.safeTransfer(token_, dirtyTo_, amount_);
        assembly {
            fmpAfter_ := mload(0x40)
            zeroSlot_ := mload(0x60)
        }
        canaryIntact_ = _canaryIntact(canary_);
    }

    function transferFromProbe(
        address token_,
        address from_,
        address to_,
        uint256 amount_,
        uint96 dirt_
    ) external returns (uint256 fmpBefore_, uint256 fmpAfter_, uint256 zeroSlot_, bool canaryIntact_) {
        bytes memory canary_ = _canary();
        address dirtyFrom_;
        address dirtyTo_;
        assembly {
            fmpBefore_ := mload(0x40)
            dirtyFrom_ := or(shl(160, dirt_), from_)
            dirtyTo_ := or(shl(160, not(dirt_)), to_)
        }
        SafeTransfer.safeTransferFrom(token_, dirtyFrom_, dirtyTo_, amount_);
        assembly {
            fmpAfter_ := mload(0x40)
            zeroSlot_ := mload(0x60)
        }
        canaryIntact_ = _canaryIntact(canary_);
    }

    function approveProbe(
        address token_,
        address to_,
        uint256 amount_,
        uint96 dirt_
    ) external returns (uint256 fmpBefore_, uint256 fmpAfter_, uint256 zeroSlot_, bool canaryIntact_) {
        bytes memory canary_ = _canary();
        address dirtyTo_;
        assembly {
            fmpBefore_ := mload(0x40)
            dirtyTo_ := or(shl(160, dirt_), to_)
        }
        SafeApprove.safeApprove(token_, dirtyTo_, amount_);
        assembly {
            fmpAfter_ := mload(0x40)
            zeroSlot_ := mload(0x60)
        }
        canaryIntact_ = _canaryIntact(canary_);
    }

    function _canary() internal pure returns (bytes memory canary_) {
        canary_ = new bytes(77);
        for (uint256 i; i < canary_.length; ++i) {
            canary_[i] = bytes1(uint8(0xA0 + (i % 16)));
        }
    }

    function _canaryIntact(bytes memory canary_) internal pure returns (bool intact_) {
        intact_ = canary_.length == 77;
        for (uint256 i; intact_ && i < canary_.length; ++i) {
            intact_ = canary_[i] == bytes1(uint8(0xA0 + (i % 16)));
        }
    }

    receive() external payable {}
}

contract RecordingToken {
    bytes public lastCalldata;
    bytes internal _returnData;
    bool internal _reverts;

    function setReturnData(bytes memory returnData_) external {
        _returnData = returnData_;
        _reverts = false;
    }

    function setReverts() external {
        _reverts = true;
    }

    fallback() external {
        lastCalldata = msg.data;
        if (_reverts) revert();

        bytes memory returnData_ = _returnData;
        assembly {
            return(add(returnData_, 0x20), mload(returnData_))
        }
    }
}

contract RevertingNativeReceiver {
    receive() external payable {
        revert();
    }
}

contract SafeTransferTest is Test {
    SafeTransferHarness internal harness;
    RecordingToken internal token;

    function setUp() public {
        harness = new SafeTransferHarness();
        token = new RecordingToken();
        token.setReturnData(abi.encode(uint256(1)));
    }

    function test_transferMethods_AcceptTrueAndNoReturnData() public {
        harness.transfer(address(token), address(2), 3);
        harness.transferFrom(address(token), address(1), address(2), 3);
        harness.approve(address(token), address(2), 3);

        token.setReturnData("");
        harness.transfer(address(token), address(2), 3);
        harness.transferFrom(address(token), address(1), address(2), 3);
        harness.approve(address(token), address(2), 3);
    }

    function test_transferMethods_RevertIfFalseReturnData() public {
        token.setReturnData(abi.encode(uint256(0)));

        vm.expectRevert(abi.encodeWithSelector(SafeTransfer.FluidSafeTransferError.selector, 71002));
        harness.transfer(address(token), address(2), 3);

        vm.expectRevert(abi.encodeWithSelector(SafeTransfer.FluidSafeTransferError.selector, 71001));
        harness.transferFrom(address(token), address(1), address(2), 3);

        vm.expectRevert(abi.encodeWithSelector(SafeApprove.FluidSafeApproveError.selector, 81001));
        harness.approve(address(token), address(2), 3);
    }

    function test_transferMethods_TargetWithoutCode() public {
        address noCode_ = address(0xBEEF);

        harness.transfer(noCode_, address(2), 3);

        harness.transferFrom(noCode_, address(1), address(2), 3);

        vm.expectRevert(abi.encodeWithSelector(SafeApprove.FluidSafeApproveError.selector, 81001));
        harness.approve(noCode_, address(2), 3);
    }

    function test_safeTransferNative_SuccessAndRevertingReceiver() public {
        vm.deal(address(harness), 2 ether);
        address receiver_ = address(0xCAFE);

        harness.transferNative(receiver_, 1 ether);
        assertEq(receiver_.balance, 1 ether);

        RevertingNativeReceiver revertingReceiver_ = new RevertingNativeReceiver();
        vm.expectRevert(abi.encodeWithSelector(SafeTransfer.FluidSafeTransferError.selector, 71002));
        harness.transferNative(address(revertingReceiver_), 1 ether);
    }

    function test_fuzz_safeTransfer_CalldataAndReturnDataRules(
        uint8 mode_,
        address to_,
        uint256 amount_,
        uint96 dirt_
    ) public {
        bool accepted_ = _setReturnMode(uint8(bound(mode_, 0, 11)));
        bytes memory expectedCalldata_ = abi.encodeWithSignature("transfer(address,uint256)", to_, amount_);

        vm.expectCall(address(token), expectedCalldata_);
        if (!accepted_) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SafeTransfer.FluidSafeTransferError.selector,
                    LibsErrorTypes.SafeTransfer__TransferFailed
                )
            );
        }
        (uint256 fmpBefore_, uint256 fmpAfter_, uint256 zeroSlot_, bool canaryIntact_) = harness.transferProbe(
            address(token),
            to_,
            amount_,
            dirt_
        );

        if (accepted_) {
            assertEq(token.lastCalldata(), expectedCalldata_);
            _assertMemoryIntact(fmpBefore_, fmpAfter_, zeroSlot_, canaryIntact_);
        }
    }

    function test_fuzz_safeTransferFrom_CalldataAndReturnDataRules(
        uint8 mode_,
        address from_,
        address to_,
        uint256 amount_,
        uint96 dirt_
    ) public {
        bool accepted_ = _setReturnMode(uint8(bound(mode_, 0, 11)));
        bytes memory expectedCalldata_ = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            from_,
            to_,
            amount_
        );

        vm.expectCall(address(token), expectedCalldata_);
        if (!accepted_) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SafeTransfer.FluidSafeTransferError.selector,
                    LibsErrorTypes.SafeTransfer__TransferFromFailed
                )
            );
        }
        (uint256 fmpBefore_, uint256 fmpAfter_, uint256 zeroSlot_, bool canaryIntact_) = harness.transferFromProbe(
            address(token),
            from_,
            to_,
            amount_,
            dirt_
        );

        if (accepted_) {
            assertEq(token.lastCalldata(), expectedCalldata_);
            _assertMemoryIntact(fmpBefore_, fmpAfter_, zeroSlot_, canaryIntact_);
        }
    }

    function test_fuzz_safeApprove_CalldataAndReturnDataRules(
        uint8 mode_,
        address to_,
        uint256 amount_,
        uint96 dirt_
    ) public {
        bool accepted_ = _setReturnMode(uint8(bound(mode_, 0, 11)));
        bytes memory expectedCalldata_ = abi.encodeWithSignature("approve(address,uint256)", to_, amount_);

        vm.expectCall(address(token), expectedCalldata_);
        if (!accepted_) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SafeApprove.FluidSafeApproveError.selector,
                    LibsErrorTypes.SafeApprove__ApproveFailed
                )
            );
        }
        (uint256 fmpBefore_, uint256 fmpAfter_, uint256 zeroSlot_, bool canaryIntact_) = harness.approveProbe(
            address(token),
            to_,
            amount_,
            dirt_
        );

        if (accepted_) {
            assertEq(token.lastCalldata(), expectedCalldata_);
            _assertMemoryIntact(fmpBefore_, fmpAfter_, zeroSlot_, canaryIntact_);
        }
    }

    /// @dev Accepted: a first word of exactly 1 with at least 32 bytes returned, or no return data at all.
    function _setReturnMode(uint8 mode_) internal returns (bool accepted_) {
        if (mode_ == 0) {
            token.setReturnData(abi.encode(uint256(1)));
            return true;
        }
        if (mode_ == 1) {
            token.setReturnData("");
            return true;
        }
        if (mode_ == 2) {
            token.setReturnData(abi.encodePacked(uint256(1), uint8(0xff)));
            return true;
        }
        if (mode_ == 3) {
            token.setReturnData(abi.encode(uint256(1), uint256(0)));
            return true;
        }
        if (mode_ == 4) {
            token.setReturnData(abi.encodePacked(bytes31(0), uint8(1), uint8(0)));
            return true;
        }
        if (mode_ == 5) {
            token.setReturnData(abi.encode(uint256(0)));
            return false;
        }
        if (mode_ == 6) {
            token.setReturnData(abi.encode(uint256(2)));
            return false;
        }
        if (mode_ == 7) {
            token.setReturnData(hex"01");
            return false;
        }
        if (mode_ == 8) {
            token.setReturnData(abi.encodePacked(bytes30(0), uint8(1)));
            return false;
        }
        if (mode_ == 9) {
            token.setReturnData(abi.encode(uint256(0), uint256(1)));
            return false;
        }
        if (mode_ == 10) {
            token.setReturnData(abi.encode((uint256(1) << 255) | 1));
            return false;
        }
        token.setReverts();
        return false;
    }

    function _assertMemoryIntact(
        uint256 fmpBefore_,
        uint256 fmpAfter_,
        uint256 zeroSlot_,
        bool canaryIntact_
    ) internal {
        assertEq(fmpAfter_, fmpBefore_, "free memory pointer changed");
        assertEq(zeroSlot_, 0, "zero slot dirty");
        assertTrue(canaryIntact_, "earlier allocation overwritten");
    }
}
