// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Owned } from "solmate/src/auth/Owned.sol";

import { IFluidVaultT1 } from "../../protocols/vault/interfaces/iVaultT1.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/interfaces/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH9 } from "../../protocols/lending/interfaces/external/iWETH9.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IFluidVaultFactory } from "../../protocols/vault/interfaces/iVaultFactory.sol";

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

contract VaultT1Migrator is Owned {
    using SafeERC20 for IERC20;

    uint internal constant X32 = 0xffffffff;
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IFluidVaultFactory immutable public VAULT_T1_FACTORY_OLD;
    IFluidVaultFactory immutable public VAULT_T1_FACTORY_NEW;

    InstaFlashInterface immutable public FLA;
    IWETH9 immutable public WETH;

    struct FlashloanConfig {
        uint256 amount;
        uint256 route;
    }

    mapping (address => FlashloanConfig) public flashloanConfig;

    error FluidVaultT1Migrator__InvalidOperation();
    error FluidVaultT1Migrator__NotAllowed();

    event Migrated(
        uint256 indexed vaultId,
        address indexed owner,
        uint256 indexed nft,
        uint256 collateral,
        uint256 debt
    );

    event Withdraw(
        address indexed to,
        address indexed token,
        uint256 amount
    );

    event SetFlashloanConfig (
        address indexed token, 
        uint256 indexed route,
        uint256 amount
    );

    constructor(
        address owner_,
        address fla_,
        address weth_,
        address oldFactory_,
        address newFactory_
    ) Owned(owner_) {
        FLA = InstaFlashInterface(fla_);
        WETH = IWETH9(weth_);

        VAULT_T1_FACTORY_OLD = IFluidVaultFactory(oldFactory_);
        VAULT_T1_FACTORY_NEW = IFluidVaultFactory(newFactory_);
    }

    function setFlashloanConfig(address token_, uint256 route_, uint256 amount_) public onlyOwner {
        flashloanConfig[token_] = FlashloanConfig({
            amount: amount_,
            route: route_
        });
        emit SetFlashloanConfig(token_, route_, amount_);
    }

    function spell(address[] memory targets_, bytes[] memory calldatas_) public onlyOwner {
        for (uint256 i = 0; i < targets_.length; i++) {
            Address.functionDelegateCall(targets_[i], calldatas_[i]);
        }
    }

    function withdraw(address to_, address[] memory tokens_, uint256[] memory amounts_) public onlyOwner {
        for (uint i = 0; i < tokens_.length; i++) {
            if (tokens_[i] == ETH_ADDRESS) {
                Address.sendValue(payable(to_), amounts_[i]);
            } else {
                IERC20(tokens_[i]).safeTransfer(to_, amounts_[i]);
            }
            emit Withdraw(to_, tokens_[i], amounts_[i]);
        }
    }

    struct MigratorParams {
        uint256 nftId;
        address owner;
        address supply;
        address borrow;
        uint256 vaultId;
        address vaultFrom;
        address vaultTo;
        uint256 supplyAmount;
        uint256 borrowAmount;
        int256 withdrawAmount;
        int256 paybackAmount;
        uint256 route;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        if (msg.sender != address(VAULT_T1_FACTORY_OLD)) revert FluidVaultT1Migrator__NotAllowed();
        if (operator != from) revert FluidVaultT1Migrator__NotAllowed();

        MigratorParams memory params_;
        params_.nftId = tokenId;
        params_.owner = from;

        (params_.vaultId, params_.vaultFrom) = vaultByNftId(tokenId);
        (params_.supply, params_.borrow) = vaultConfig(params_.vaultFrom);
        params_.vaultTo = getVaultAddress(address(VAULT_T1_FACTORY_NEW), params_.vaultId);

        if (data.length > 0) {
            (params_.route, params_.borrowAmount) = abi.decode(data, (uint256, uint256));
        } else {
            FlashloanConfig memory c_ = flashloanConfig[params_.borrow];
            (params_.route, params_.borrowAmount) = (c_.route, c_.amount);
        }

        if (params_.route == 0) revert FluidVaultT1Migrator__NotAllowed();

        address[] memory tokens = new address[](1);
        uint256[] memory amts = new uint256[](1);

        // Take flashloan in borrow token of the vault
        tokens[0] = params_.borrow == ETH_ADDRESS ? address(WETH) : params_.borrow;
        amts[0] = params_.borrowAmount * 150 / 100; // increase by 50%

        bytes memory data_ = abi.encode(params_);

        FLA.flashLoan(tokens, amts, params_.route, data_, abi.encode());

        if (VAULT_T1_FACTORY_NEW.balanceOf(address(this)) > 0) revert FluidVaultT1Migrator__NotAllowed();
        
        return this.onERC721Received.selector;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata _data
    ) external returns (bool) {
        if (msg.sender != address(FLA)) revert FluidVaultT1Migrator__NotAllowed();
        if (initiator != address(this)) revert FluidVaultT1Migrator__NotAllowed();
        MigratorParams memory params_ = abi.decode(_data, (MigratorParams));

        uint256 value_;
        {
            if (params_.borrow != ETH_ADDRESS) {
                IERC20(params_.borrow).safeApprove(params_.vaultFrom, 0);
                IERC20(params_.borrow).safeApprove(params_.vaultFrom, params_.borrowAmount);
                value_ = 0;
            } else {
                WETH.withdraw(params_.borrowAmount);
                value_ = params_.borrowAmount;
            }

            (
                ,
                params_.withdrawAmount,
                params_.paybackAmount
            ) = IFluidVaultT1(params_.vaultFrom).operate{value: value_}(
                params_.nftId,
                type(int256).min,
                type(int256).min,
                address(this)
            );

            params_.withdrawAmount = -params_.withdrawAmount;
            params_.paybackAmount = -params_.paybackAmount;
            params_.supplyAmount = uint256(params_.withdrawAmount);
            params_.borrowAmount = uint256(params_.paybackAmount);
        }

        {
            if (params_.supply != ETH_ADDRESS) {
                IERC20(params_.supply).safeApprove(params_.vaultTo, 0);
                IERC20(params_.supply).safeApprove(params_.vaultTo, params_.supplyAmount);
                value_ = 0;
            } else {
                value_ = params_.supplyAmount;
            }

            (
                uint256 nftId_,
                ,

            ) = IFluidVaultT1(params_.vaultTo).operate{value: value_}(
                0,
                params_.withdrawAmount,
                params_.paybackAmount,
                address(this)

            );

            IERC721(VAULT_T1_FACTORY_NEW).transferFrom(address(this), params_.owner, nftId_);
        }

        uint256 flashloanAmount_ = amounts[0] + premiums[0] + 10;
        if (params_.borrow == ETH_ADDRESS) {
            uint256 wethBalance_ = WETH.balanceOf(address(this));
            if (wethBalance_ < flashloanAmount_) {
                WETH.deposit{value: flashloanAmount_ - wethBalance_}();
            }
        }
        IERC20(assets[0]).safeTransfer(msg.sender, flashloanAmount_);

        emit Migrated(
            params_.vaultId,
            params_.owner,
            params_.nftId,
            uint256(-params_.withdrawAmount),
            uint256(-params_.paybackAmount)
        );

        return true;
    }

    function vaultByNftId(uint nftId_) public view returns (uint256 vaultId_, address vault_) {
        uint tokenConfig_ = VAULT_T1_FACTORY_OLD.readFromStorage(calculateStorageSlotUintMapping(3, nftId_));
        vaultId_ = (tokenConfig_ >> 192) & X32;
        vault_ = getVaultAddress(address(VAULT_T1_FACTORY_OLD), vaultId_);
    }

    function vaultConfig(address vault_) public view returns(address supply_, address borrow_) {
        IFluidVaultT1.ConstantViews memory constants_ = IFluidVaultT1(vault_).constantsView();

        supply_ = constants_.supplyToken;
        borrow_ = constants_.borrowToken;
    }

    function calculateStorageSlotUintMapping(uint256 slot_, uint key_) public pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    function getVaultAddress(address vaultFactory_, uint256 vaultId_) public pure returns (address vault_) {
        // @dev based on https://ethereum.stackexchange.com/a/61413
        bytes memory data;
        if (vaultId_ == 0x00) {
            // nonce of smart contract always starts with 1. so, with nonce 0 there won't be any deployment
            return address(0);
        } else if (vaultId_ <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), address(vaultFactory_), uint8(vaultId_));
        } else if (vaultId_ <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), address(vaultFactory_), bytes1(0x81), uint8(vaultId_));
        } else if (vaultId_ <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), address(vaultFactory_), bytes1(0x82), uint16(vaultId_));
        } else if (vaultId_ <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), address(vaultFactory_), bytes1(0x83), uint24(vaultId_));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), address(vaultFactory_), bytes1(0x84), uint32(vaultId_));
        }

        return address(uint160(uint256(keccak256(data))));
    }

    receive() payable external {}
}