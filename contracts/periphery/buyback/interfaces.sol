//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.29;

interface IDSA {
    function cast(string[] calldata _targetNames, bytes[] calldata _datas, address _origin)
        external
        payable
        returns (bytes32);
}

interface IInstaIndex {
    function build(address owner_, uint256 accountVersion_, address origin_) external returns (address account_);
}
