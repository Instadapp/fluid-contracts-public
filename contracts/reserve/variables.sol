// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Structs } from "./structs.sol";

abstract contract Constants {
    /// @dev address that is mapped to the chain native token
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
}

abstract contract Variables is Constants, Initializable, OwnableUpgradeable, Structs {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ------------ storage variables from inherited contracts (Initializable, OwnableUpgradeable) come before vars here --------
    // @dev variables here start at storage slot 101, before is:
    // - Initializable with storage slot 0:
    // uint8 private _initialized;
    // bool private _initializing;
    // - OwnableUpgradeable with slots 1 to 100:
    // uint256[50] private __gap; (from ContextUpgradeable, slot 1 until slot 50)
    // address private _owner; (at slot 51)
    // uint256[49] private __gap; (slot 52 until slot 100)

    // ----------------------- slot 101 ---------------------------
    /// @notice Maps address to there status as an Auth
    mapping(address => bool) public isAuth;

    /// @notice Maps address to there status as a Rebalancer
    mapping(address => bool) public isRebalancer;

    /// @notice Mapping of protocol addresses to the tokens that are allowed to be used by that protocol
    mapping(address => EnumerableSet.AddressSet) internal _protocolTokens;

    /// @notice Mapping of protocol addresses to the amount of tokens that are allowed to be used by that protocol
    mapping(address => uint256) public nativeTokenAllowances;

    /// @notice Array of all the protocols that had tokens allowed to be used
    EnumerableSet.AddressSet internal _protocols;
}
