// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.29;

import {Events} from "./events.sol";
import {Variables} from "./variables.sol";
import {IDSA} from "./interfaces.sol";
import {SafeTransfer} from "../../libraries/safeTransfer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

abstract contract FluidBuybackCore is Variables {
    error BuybackContract__AddressZero();
    error BuybackContract__NotOwner();
    error BuybackContract__NotRebalancer();
    error BuybackContract__AlreadyInitialized();
    error BuybackContract__ETHTransferFailed();
    error BuybackContract__LessAmountReceived();
    error BuybackContract__RenounceOwnershipUnsupported();

    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert BuybackContract__AddressZero();
        }
        _;
    }
    /**
     * @dev modifier to check if the caller is a rebalancer.
     */
    modifier onlyRebalancer() {
        if (!rebalancers[msg.sender]) revert BuybackContract__NotRebalancer();
        _;
    }
}

abstract contract ReentrancyGuard is FluidBuybackCore {
    error BuybackContract__Reentrancy();

    uint8 internal constant REENTRANCY_NOT_ENTERED = 1;
    uint8 internal constant REENTRANCY_ENTERED = 2;

    constructor() {
        _status = REENTRANCY_ENTERED; // set status to entered on logic contract so only delegateCalls are possible
    }

    /// @dev Prevents a contract from calling itself, directly or indirectly.
    /// See OpenZeppelin implementation for more info
    modifier nonReentrant() {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status != REENTRANCY_NOT_ENTERED) {
            revert BuybackContract__Reentrancy();
        }

        // Any calls to nonReentrant after this point will fail
        _status = REENTRANCY_ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = REENTRANCY_NOT_ENTERED;
    }
}

contract FluidBuyback is ReentrancyGuard, Events, UUPSUpgradeable {
    constructor() {
        // ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /// @notice initializes the contract with `owner_` as owner and `rebalancers_` as rebalancers and build the buyback DSA
    /// @param owner_ the owner of the contract
    /// @param rebalancers_ the rebalancers of the contract
    function initialize(address owner_, address[] memory rebalancers_) public initializer validAddress(owner_) {
        _transferOwnership(owner_);

        for (uint256 i = 0; i < rebalancers_.length; i++) {
            rebalancers[rebalancers_[i]] = true;
            emit LogUpdateRebalancer(rebalancers_[i], true);
        }

        address buybackDsaAddress_ = INSTA_INDEX_CONTRACT.build(address(this), 2, address(this));
        buybackDSA = IDSA(buybackDsaAddress_);
        
        _status = REENTRANCY_NOT_ENTERED; // set reentrancy to not entered on proxy
    }

    /// @notice UUPS Upgrade authorization - only owner can authorize upgrades
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice override renounce ownership as it could leave the contract in an unwanted state if called by mistake.
    function renounceOwnership() public view override onlyOwner {
        revert BuybackContract__RenounceOwnershipUnsupported();
    }

    /// @notice swaps `sellAmount_` of `tokenIn_` for `tokenOut_`
    /// @param tokenIn_ the token to sell
    /// @param tokenOut_ the token to buy
    /// @param sellAmount_ the amount of `tokenIn_` to sell
    /// @param minBuyAmount_ the minimum amount of `tokenOut_` to buy
    /// @param swapConnectors_ the connectors to use for the swap
    /// @param swapCalldatas_ the calldatas to use for the swap
    /// @return buyAmount_ the amount of `tokenOut_` bought
    function swap(
        address tokenIn_,
        address tokenOut_,
        uint256 sellAmount_,
        uint256 minBuyAmount_,
        string[] memory swapConnectors_,
        bytes[] memory swapCalldatas_
    ) public onlyRebalancer nonReentrant returns (uint256 buyAmount_) {
        string[] memory targets = new string[](2);
        bytes[] memory calldatas = new bytes[](2);

        uint256 buyTokenBalanceBefore_ =
            tokenOut_ == ETH_ADDRESS ? address(this).balance : IERC20(tokenOut_).balanceOf(address(this));

        if (tokenIn_ != ETH_ADDRESS) {
            SafeTransfer.safeTransfer(tokenIn_, address(buybackDSA), sellAmount_);
        } else {
            SafeTransfer.safeTransferNative(address(buybackDSA), sellAmount_);
        }

        // Swap the tokens using the swap connectors
        targets[0] = "SWAP-AGGREGATOR-A";
        calldatas[0] = abi.encodeWithSignature("swap(string[],bytes[])", swapConnectors_, swapCalldatas_);

        // Transfer the swapped tokens from the DSA to this contract
        // BASIC-A handles both ETH and ERC20 tokens
        targets[1] = "BASIC-A";
        calldatas[1] = abi.encodeWithSignature(
            "withdraw(address,uint256,address,uint256,uint256)", tokenOut_, type(uint256).max, address(this), 0, 0
        );

        buybackDSA.cast(targets, calldatas, address(this));

        buyAmount_ = tokenOut_ == ETH_ADDRESS
            ? address(this).balance - buyTokenBalanceBefore_
            : IERC20(tokenOut_).balanceOf(address(this)) - buyTokenBalanceBefore_;

        if (buyAmount_ < minBuyAmount_) revert BuybackContract__LessAmountReceived();

        // If the token out is the Fluid token, emit the buyback swap event, otherwise emit the token swap event
        if (tokenOut_ == FLUID_TOKEN_ADDRESS) {
            emit LogBuyback(tokenIn_, tokenOut_, sellAmount_, buyAmount_);
        } else {
            emit LogTokenSwap(tokenIn_, tokenOut_, sellAmount_, buyAmount_);
        }
    }

    /// @notice collects `amount_` of Fluid tokens to the treasury - only rebalancers can collect Fluid tokens
    /// @param amount_ the amount of Fluid tokens to collect
    function collectFluidTokensToTreasury(uint256 amount_) public onlyRebalancer nonReentrant {
        SafeTransfer.safeTransfer(FLUID_TOKEN_ADDRESS, TREASURY_ADDRESS, amount_);
        emit LogCollectFluidTokensToTreasury(amount_);
    }

    /// @notice collects `amount_` of `token_` to the treasury - only owner can collect tokens
    /// @param token_ the token to collect
    /// @param amount_ the amount of `token_` to collect
    function collectTokensToTreasury(address token_, uint256 amount_) public onlyOwner nonReentrant {
        if (token_ != ETH_ADDRESS) {
            SafeTransfer.safeTransfer(token_, TREASURY_ADDRESS, amount_);
        } else {
            SafeTransfer.safeTransferNative(TREASURY_ADDRESS, amount_);
        }
        emit LogCollectTokensToTreasury(token_, amount_);
    }

    /// @notice updates the rebalancer status - only owner can update the rebalancer status
    /// @param rebalancer_ the rebalancer to update
    /// @param isActive_ the status of the rebalancer
    function updateRebalancer(address rebalancer_, bool isActive_) public onlyOwner nonReentrant {
        rebalancers[rebalancer_] = isActive_;
        emit LogUpdateRebalancer(rebalancer_, isActive_);
    }

    // Buyback Implementation needs to have a receive function in order for BASIC-A to return ETH
    receive() external payable {}
}
