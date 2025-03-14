// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { IERC721 } from "@openzeppelin/contracts/interfaces/IERC721.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { IFluidVaultFactory } from "../../../protocols/vault/interfaces/iVaultFactory.sol";

import { FluidWallet } from "../wallet/proxy.sol";

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

contract FluidWalletFactoryVariables is Initializable, OwnableUpgradeable {
    /***********************************|
    |   Constants/Immutables            |
    |__________________________________*/
    IFluidVaultFactory immutable public VAULT_T1_FACTORY;

    address immutable public WALLET_PROXY;

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
    /// @dev fluid wallet implementation address. 
    /// Can be updated by owner for newer version.
    address internal _implementation;

    constructor(
        address vaultT1Factory_,
        address fluidWalletFactoryProxy_
    ) {
        VAULT_T1_FACTORY = IFluidVaultFactory(vaultT1Factory_);
        WALLET_PROXY = address(new FluidWallet(address(fluidWalletFactoryProxy_)));
    }
}

contract FluidWalletFactoryErrorsAndEvents {
    error FluidWalletFactory__InvalidOperation();
    error FluidWalletFactory__NotAllowed();

    event Executed(
        address indexed owner,
        uint256 indexed nft
    );

    event FluidImplementationUpdate(
        address indexed oldImplementation_,
        address indexed newImplementation_
    );
}

contract FluidWalletFactory is FluidWalletFactoryVariables, FluidWalletFactoryErrorsAndEvents, UUPSUpgradeable {
    struct Action {
        address target;
        bytes data;
        uint256 value;
        uint8 operation;
    }

    struct StrategyParams {
        uint256 nftId;
        address owner;
        address wallet;
        Action[] actions;
    }

    constructor(address vaultT1Factory_, address fluidWalletFactoryProxy_) FluidWalletFactoryVariables(vaultT1Factory_, fluidWalletFactoryProxy_) {
        // ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /// @notice initializes the contract with `owner_` as owner
    function initialize(address owner_) public initializer {
        _transferOwnership(owner_);
    }

    /***********************************|
    |         Action Execution          |
    |__________________________________*/

    /// @dev                    ERC721 callback used Fluid Vault Factory and executes actions encoded in `data_`
    ///                         Caller should be Vault T1 Factory.
    /// @param operator_        operator_ caller to transfer the the given token ID
    /// @param from_            from_ previous owner of the given token ID
    /// @param tokenId_         tokenId_ id of the ERC721
    /// @param data_            data bytes containing the `abi.encoded()` actions that are executed like in `Action[]`
    function onERC721Received(
        address operator_,
        address from_,
        uint256 tokenId_,
        bytes calldata data_
    ) external returns (bytes4) {
        if (msg.sender != address(VAULT_T1_FACTORY)) revert FluidWalletFactory__NotAllowed();
        if (operator_ != from_) revert FluidWalletFactory__NotAllowed();
        if (data_.length == 0) revert FluidWalletFactory__NotAllowed();

        StrategyParams memory params_;
        params_.nftId = tokenId_;
        params_.owner = from_;
        params_.actions = abi.decode(data_, (Action[]));
        params_.wallet = deploy(params_.owner);

        VAULT_T1_FACTORY.safeTransferFrom(
            address(this),
            params_.wallet,
            params_.nftId,
            abi.encode(params_.owner, params_.actions)
        );

        if (VAULT_T1_FACTORY.ownerOf(tokenId_) != params_.owner) revert FluidWalletFactory__InvalidOperation();
        if (VAULT_T1_FACTORY.balanceOf(address(this)) > 0) revert FluidWalletFactory__InvalidOperation();

        emit Executed(params_.owner, params_.nftId);
        return this.onERC721Received.selector;
    }

    /***********************************|
    |     Wallet Deployment functions   |
    |__________________________________*/

    function deploy(address owner_) public returns (address wallet_) {
        bytes32 salt_ = keccak256(abi.encode(owner_));
        wallet_ = Clones.predictDeterministicAddress(WALLET_PROXY, salt_, address(this));
        if (wallet_.code.length == 0) {
            Clones.cloneDeterministic(WALLET_PROXY, salt_);
            FluidWallet(payable(wallet_)).initialize(owner_);
        }
    }

    function walletImplementation() public returns (address) {
        return _implementation;
    }

    function computeWallet(address owner_) public view returns (address wallet_) {
        return Clones.predictDeterministicAddress(WALLET_PROXY, keccak256(abi.encode(owner_)), address(this));
    }

    /***********************************|
    |       Owner related functions     |
    |__________________________________*/

    function spell(address[] memory targets_, bytes[] memory calldatas_) public onlyOwner {
        for (uint256 i = 0; i < targets_.length; i++) {
            Address.functionDelegateCall(targets_[i], calldatas_[i]);
        }
    }

    function changeImplementation(address implementation_) public onlyOwner {
        emit FluidImplementationUpdate(_implementation, implementation_);
        _implementation = implementation_;
    }

    /// @notice override renounce ownership as it could leave the contract in an unwanted state if called by mistake.
    function renounceOwnership() public view override onlyOwner {
        revert FluidWalletFactory__InvalidOperation();
    }

    receive() external payable {}

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}