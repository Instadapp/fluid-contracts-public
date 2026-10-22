//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TestERC20 is ERC20, ERC20Burnable {
    bool public blocked;

    bool public noReturnData;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        blocked = false;
        noReturnData = false;
    }

    function blockTransfer(bool blocking) external {
        blocked = blocking;
    }

    function setNoReturnData(bool noReturn) external {
        noReturnData = noReturn;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external returns (bool) {
        _burn(from, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool ok) {
        if (blocked) {
            return false;
        }

        super.transferFrom(from, to, amount);

        if (noReturnData) {
            assembly {
                return(0, 0)
            }
        }

        ok = true;
    }
}
