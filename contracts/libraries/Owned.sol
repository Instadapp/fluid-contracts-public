// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

/// @notice Simple single owner authorization mixin.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/effa6fb87f0059ddab2d2f2dcd1d61b559f74dca/src/auth/Owned.sol)
/// @dev Vendored MIT copy, reverting with a custom error instead of a string. Solmate is not a project dependency.
abstract contract Owned {
    error Access__Unauthorized();

    event OwnershipTransferred(address indexed user, address indexed newOwner);

    address public owner;

    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert Access__Unauthorized();

        _;
    }

    constructor(address _owner) {
        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        owner = newOwner;

        emit OwnershipTransferred(msg.sender, newOwner);
    }
}
