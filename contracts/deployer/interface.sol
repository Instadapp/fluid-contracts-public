//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidContractFactory {
    function totalContracts() external view returns (uint256);

    function getContractAddress(uint256 nonce_) external view returns (address contractAddress_);

    function deployContract(
        bytes calldata contractCode_
    ) external returns (address contractAddress_);

    function updateDeployer(address deployer_, uint16 count_) external;

    function deployer(address deployer_) external view returns (uint256);

}
