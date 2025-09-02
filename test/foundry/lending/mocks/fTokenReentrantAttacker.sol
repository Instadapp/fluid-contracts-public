//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";

import { fToken } from "../../../../contracts/protocols/lending/fToken/main.sol";
import { ErrorTypes } from "../../../../contracts/protocols/lending/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/lending/error.sol";

contract ReentrantAttacker {
    fToken public target;
    MaliciousToken public maliciousToken;

    constructor(fToken _target) {
        target = _target;
        maliciousToken = new MaliciousToken(_target);
    }

    function attack() external {
        maliciousToken.mint(address(target), 1000);
        target.rescueFunds(address(maliciousToken));
    }

    fallback() external {
        target.rescueFunds(address(1));
    }
}

contract MaliciousToken is MockERC20, Test {
    fToken public target;

    constructor(fToken _target) MockERC20("Malcious", "MAL", 18) {
        target = _target;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        super.transfer(recipient, amount);
        // attempt to re-enter the rescueFunds function
        try target.rescueFunds(address(this)) {
            assertEq(true, false, "Reentrancy attack should have failed");
        } catch (bytes memory lowLevelData) {
            assertEq(
                keccak256(abi.encodePacked(lowLevelData)),
                keccak256(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Reentrancy))
            );
        }
        return true;
    }
}
