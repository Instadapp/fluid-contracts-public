pragma solidity 0.8.21;

import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

contract MockonERC721Received {
    error ERC721Error();
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        if (data.length != 0) {
            address owner = abi.decode(data, (address));

            require(owner == operator, "owner-not-same");
            if (operator != from) revert ERC721Error();

            address child = address(new MockonERC721ReceivedChild());

            // Transfer to Child contract
            IERC721Enumerable(msg.sender).safeTransferFrom(address(this), child, tokenId, data);

            // Transfer to owner back.
            IERC721Enumerable(msg.sender).safeTransferFrom(address(this), operator, tokenId);
        }

        return MockonERC721Received(address(this)).onERC721Received.selector;
    }
}

contract MockonERC721ReceivedChild {
    error ERC721Error();

    address immutable FACTORY;
    constructor () {
        FACTORY = msg.sender;
    }
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        (address toTransfer) = abi.decode(data, (address));

        if (operator != from) revert ERC721Error();

        IERC721Enumerable(msg.sender).safeTransferFrom(address(this), FACTORY, tokenId);

        return MockonERC721Received(address(this)).onERC721Received.selector;
    }
}

