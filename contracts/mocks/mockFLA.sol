// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface InstaFlashInterface {
    function flashLoan(address[] memory tokens, uint256[] memory amts, uint route, bytes memory data, bytes memory extraData) external;
}

interface InstaFlashReceiverInterface {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata _data
    ) external returns (bool);
}

contract MockFLA {
    using SafeERC20 for IERC20;
    
    function flashLoan(address[] memory tokens, uint256[] memory amts, uint route, bytes memory data, bytes memory extraData) external {
        uint256[] memory premiums = new uint256[](1);
        premiums[0] = 0;
        IERC20(tokens[0]).safeTransfer(msg.sender, amts[0]);
        InstaFlashReceiverInterface(msg.sender).executeOperation(
            tokens,
            amts,
            premiums,
            msg.sender,
            data
        );
    }
}