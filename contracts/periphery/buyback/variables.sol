// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.29;

import {IDSA, IInstaIndex} from "./interfaces.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Constants {
    IInstaIndex internal constant INSTA_INDEX_CONTRACT = IInstaIndex(0x2971AdFa57b20E5a416aE5a708A8655A9c74f723);
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant FLUID_TOKEN_ADDRESS = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;
    address internal constant TREASURY_ADDRESS = 0x28849D2b63fA8D361e5fc15cB8aBB13019884d09;
}

contract Variables is Constants, Initializable, OwnableUpgradeable {
    // ------------ storage variables from inherited contracts (Initializable, OwnableUpgradeable) come before vars here --------
    // @dev variables here start at storage slot 101, before is:
    // - Initializable with storage slot 0:
    // uint8 private _initialized;
    // bool private _initializing;
    // - OwnableUpgradeable with slots 1 to 100:
    // uint256[50] private __gap; (from ContextUpgradeable, slot 1 until slot 50)
    // address private _owner; (at slot 51)
    // uint256[49] private __gap; (slot 52 until slot 100)
    
    // @notice The status of the contract
    // 1: open; 2: closed
    uint8 internal _status;

    // @notice The rebalancers of the contract
    mapping(address => bool) public rebalancers;

    // @notice The DSA contract for the buyback
    IDSA public buybackDSA;
}
