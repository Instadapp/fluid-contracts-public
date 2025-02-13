// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { ILidoWithdrawalQueue } from "./interfaces/external/iLidoWithdrawalQueue.sol";
import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Error } from "./error.sol";
import { Events } from "./events.sol";
import { Variables } from "./variables.sol";
import { LiquidityCalcs } from "../../libraries/liquidityCalcs.sol";

abstract contract StETHQueueCore is Variables, Events, Error {
    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert StETHQueueError(ErrorTypes.StETH__AddressZero);
        }
        _;
    }

    /// @dev reads the current, updated borrow exchange price for Native ETH at Liquidity
    function _getLiquidityExchangePrice() internal view returns (uint256 borrowExchangePrice_) {
        (, borrowExchangePrice_) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(LIQUIDITY_EXCHANGE_PRICES_SLOT)
        );
    }
}

/// @dev ReentrancyGuard based on OpenZeppelin implementation.
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.8/contracts/security/ReentrancyGuard.sol
abstract contract ReentrancyGuard is StETHQueueCore {
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
            revert StETHQueueError(ErrorTypes.StETH__Reentrancy);
        }

        // Any calls to nonReentrant after this point will fail
        _status = REENTRANCY_ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = REENTRANCY_NOT_ENTERED;
    }
}

/// @dev FluidStETHQueue admin related methods
abstract contract StETHQueueAdmin is Variables, ReentrancyGuard {
    /// @dev only auths guard
    modifier onlyAuths() {
        if (!isAuth(msg.sender)) {
            revert StETHQueueError(ErrorTypes.StETH__Unauthorized);
        }
        _;
    }

    /// @notice reads if a certain `auth_` address is an allowed auth or not
    function isAuth(address auth_) public view returns (bool) {
        return auth_ == owner() || _auths[auth_] == 1;
    }

    /// @notice reads if a certain `guardian_` address is an allowed guardian or not
    function isGuardian(address guardian_) public view returns (bool) {
        return guardian_ == owner() || _guardians[guardian_] == 1;
    }

    /// @notice reads if a certain `user_` address is an allowed user or not
    function isUserAllowed(address user_) public view returns (bool) {
        return _allowed[user_] == 1;
    }

    /// @notice reads if the protocol is paused or not
    function isPaused() public view returns (bool){
        return _status == REENTRANCY_ENTERED;
    }

    /// @notice                   Sets an address as allowed auth or not. Only callable by owner.
    /// @param auth_              address to set auth value for
    /// @param allowed_           bool flag for whether address is allowed as auth or not
    function setAuth(address auth_, bool allowed_) external onlyOwner validAddress(auth_) {
        _auths[auth_] = allowed_ ? 1 : 0;

        emit LogSetAuth(auth_, allowed_);
    }

    /// @notice                   Sets an address as allowed guardian or not. Only callable by owner.
    /// @param guardian_          address to set guardian value for
    /// @param allowed_           bool flag for whether address is allowed as guardian or not
    function setGuardian(address guardian_, bool allowed_) external onlyOwner validAddress(guardian_) {
        _guardians[guardian_] = allowed_ ? 1 : 0;

        emit LogSetGuardian(guardian_, allowed_);
    }

    /// @notice                   Sets an address as allowed user or not. Only callable by auths.
    /// @param user_              address to set allowed value for
    /// @param allowed_           bool flag for whether address is allowed as user or not
    function setUserAllowed(address user_, bool allowed_) external onlyAuths validAddress(user_) {
        _allowed[user_] = allowed_ ? 1 : 0;

        emit LogSetAllowed(user_, allowed_);
    }

    /// @notice                   Sets `maxLTV` to `maxLTV_` (in 1e2: 1% = 100, 100% = 10000). Must be > 0 and < 100%.
    function setMaxLTV(uint16 maxLTV_) external onlyAuths {
        if (maxLTV_ == 0) {
            revert StETHQueueError(ErrorTypes.StETH__MaxLTVZero);
        }
        if (maxLTV_ >= HUNDRED_PERCENT) {
            revert StETHQueueError(ErrorTypes.StETH__MaxLTVAboveCap);
        }

        maxLTV = maxLTV_;
        emit LogSetMaxLTV(maxLTV_);
    }

    /// @notice Pauses the protocol (blocks queue() and claim()). Only callable by guardians.
    function pause() external {
        if (!isGuardian(msg.sender)) {
            revert StETHQueueError(ErrorTypes.StETH__Unauthorized);
        }

        _status = REENTRANCY_ENTERED;

        emit LogPaused();
    }

    /// @notice Unpauses the protocol (enables queue() and claim()). Only callable by owner.
    function unpause() external onlyOwner(){
        _status = REENTRANCY_NOT_ENTERED;

        emit LogUnpaused();
    }

    /// @notice Sets `allowListActive` flag to `status_`. Only callable by owner.
    function setAllowListActive(bool status_) external onlyOwner {
        allowListActive = status_;

        emit LogSetAllowListActive(status_);
    }
}

/// @title StETHQueue
/// @notice queues an amount of stETH at the Lido WithdrawalQueue, using it as collateral to borrow an amount
/// of ETH that is paid back when Lido Withdrawal is claimable. Useful e.g. to deleverage a stETH / ETH borrow position.
/// User target group are whales that want to deleverage stETH / ETH without having to swap (no slippage).
/// @dev claims are referenced to via the claimTo address and the Lido requestIdFrom, which must be tracked from the moment
/// of queuing, where it is emitted in the `LogQueue` event, to pass in that information later for `claim()`.
/// @dev For view methods / accessing data, use the "StETHResolver" periphery contract.
//
// @dev Note that as a precaution if any claim fails for unforeseen, unexpected reasons, this contract is upgradeable so
// that Governance could rescue the funds.
// Note that claiming at Lido Withdrawal Queue is gas-cost-wise cheaper than queueing. So any queue process that passes
// below block gas limit, also passes at claiming.
contract FluidStETHQueue is Variables, StETHQueueCore, StETHQueueAdmin, UUPSUpgradeable {
    constructor(
        IFluidLiquidity liquidity_,
        ILidoWithdrawalQueue lidoWithdrawalQueue_,
        IERC20 stETH_
    )
        validAddress(address(liquidity_))
        validAddress(address(lidoWithdrawalQueue_))
        validAddress(address(stETH_))
        Variables(liquidity_, lidoWithdrawalQueue_, stETH_)
    {
        // ensure logic contract initializer is not abused by disabling initializing
        // see https://forum.openzeppelin.com/t/security-advisory-initialize-uups-implementation-contracts/15301
        // and https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
        _disableInitializers();
    }

    /// @notice initializes the contract with `owner_` as owner
    function initialize(address owner_) public initializer validAddress(owner_) {
        _transferOwnership(owner_);

        // approve infinite stETH to Lido withdrawal queue for requesting withdrawals
        SafeERC20.safeApprove(STETH, address(LIDO_WITHDRAWAL_QUEUE), type(uint256).max);

        _status = REENTRANCY_NOT_ENTERED; // set reentrancy to not entered on proxy

        allowListActive = true; // start protocol in a protected state with allow list being active

        // Borrow a minor dust amount of ETH (`DUST_BORROW_AMOUNT`) from Liquidity to avoid any potential reverts
        // because of rounding differences etc
        LIQUIDITY.operate(NATIVE_TOKEN_ADDRESS, 0, int256(DUST_BORROW_AMOUNT), address(0), address(this), new bytes(0));
    }

    receive() external payable {}

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice override renounce ownership as it could leave the contract in an unwanted state if called by mistake.
    function renounceOwnership() public view override onlyOwner {
        revert StETHQueueError(ErrorTypes.StETH__RenounceOwnershipUnsupported);
    }

    /// @notice queues an amount of stETH at the Lido WithdrawalQueue, using it as collateral to borrow an amount
    /// of ETH from Liquidity that is paid back when Lido Withdrawal is claimable, triggered with `claim()`.
    /// @dev if `allowListActive` == true, then only allowed users can call this method.
    /// @param ethBorrowAmount_ amount of ETH to borrow and send to `borrowTo_`
    /// @param stETHAmount_ amount of stETH to queue at Lido Withdrawal Queue and use as collateral
    /// @param borrowTo_ receiver of the `ethBorrowAmount_`
    /// @param claimTo_ receiver of the left over stETH funds at time of `claim()`
    /// @return requestIdFrom_ first request id at Lido withdrawal queue. Used to identify claims
    function queue(
        uint256 ethBorrowAmount_,
        uint256 stETHAmount_,
        address borrowTo_,
        address claimTo_
    ) public nonReentrant validAddress(borrowTo_) validAddress(claimTo_) returns (uint256 requestIdFrom_) {
        if (allowListActive && !isUserAllowed(msg.sender)) {
            revert StETHQueueError(ErrorTypes.StETH__Unauthorized);
        }

        // 1. sanity checks
        if (ethBorrowAmount_ == 0 || stETHAmount_ == 0) {
            revert StETHQueueError(ErrorTypes.StETH__InputAmountZero);
        }
        // validity check ltv of borrow amount / collateral is below configured maxLTV
        if ((ethBorrowAmount_ * HUNDRED_PERCENT) / stETHAmount_ > maxLTV) {
            revert StETHQueueError(ErrorTypes.StETH__MaxLTV);
        }

        // 2. get `stETHAmount_` from msg.sender. must be approved to this contract
        SafeERC20.safeTransferFrom(STETH, msg.sender, address(this), stETHAmount_);

        // 3. queue stETH withdrawal at Lido, receive withdrawal NFT
        uint256[] memory amounts_;
        {
            // maximum amount of stETH that is possible to withdraw by a single request at Lido (should be 1_000 stETH).
            uint256 maxStETHWithdrawalAmount_ = LIDO_WITHDRAWAL_QUEUE.MAX_STETH_WITHDRAWAL_AMOUNT();
            // minimum amount of stETH that is possible to withdraw by a single request at Lido (should be 100 wei).
            uint256 minStETHWithdrawalAmount_ = LIDO_WITHDRAWAL_QUEUE.MIN_STETH_WITHDRAWAL_AMOUNT();

            if (stETHAmount_ > maxStETHWithdrawalAmount_) {
                // if withdraw amount is > MAX_STETH_WITHDRAWAL_AMOUNT it must be split into multiple smaller amounts
                // each of maximum MAX_STETH_WITHDRAWAL_AMOUNT

                bool lastAmountExact_;
                uint256 fullAmountsLength_ = stETHAmount_ / maxStETHWithdrawalAmount_;
                unchecked {
                    // check if remainder for last amount in array is exactly matching MAX_STETH_WITHDRAWAL_AMOUNT
                    lastAmountExact_ = stETHAmount_ % maxStETHWithdrawalAmount_ == 0;
                    // total elements are count of full amounts + 1 (unless lastAmountExact_ is true)
                    amounts_ = new uint256[](fullAmountsLength_ + (lastAmountExact_ ? 0 : 1));
                }
                // fill amounts array with MAX_STETH_WITHDRAWAL_AMOUNT except for last element
                for (uint256 i; i < fullAmountsLength_; ) {
                    amounts_[i] = maxStETHWithdrawalAmount_;

                    unchecked {
                        ++i;
                    }
                }

                if (!lastAmountExact_) {
                    // last element is result of modulo operation so length of array is fullAmountsLength_ +1
                    amounts_[fullAmountsLength_] = stETHAmount_ % maxStETHWithdrawalAmount_;

                    if (amounts_[fullAmountsLength_] < minStETHWithdrawalAmount_) {
                        // make sure remainder amount for last element in array is at least MIN_STETH_WITHDRAWAL_AMOUNT.
                        // if smaller, deduct MIN_STETH_WITHDRAWAL_AMOUNT from the second last element and it to the last.
                        unchecked {
                            amounts_[fullAmountsLength_ - 1] -= minStETHWithdrawalAmount_;
                            amounts_[fullAmountsLength_] += minStETHWithdrawalAmount_;
                        }
                    }
                }
            } else {
                amounts_ = new uint256[](1);
                amounts_[0] = stETHAmount_;
            }
        }

        // request withdrawal at Lido, receiving the withdrawal NFT to this contract as owner
        uint256[] memory requestIds_ = LIDO_WITHDRAWAL_QUEUE.requestWithdrawals(amounts_, address(this));

        requestIdFrom_ = requestIds_[0];

        // 4. borrow amount of ETH from Liquidity and send it to msg.sender.
        // sender can use this to e.g. pay back a flashloan used to deleverage at a borrowing protocol.
        (, uint256 borrowExchangePrice_) = LIQUIDITY.operate(
            NATIVE_TOKEN_ADDRESS,
            0,
            int256(ethBorrowAmount_),
            address(0),
            borrowTo_,
            new bytes(0)
        );

        uint256 borrowAmountRaw_ = (ethBorrowAmount_ * EXCHANGE_PRICES_PRECISION) / borrowExchangePrice_;
        if (borrowAmountRaw_ == 0) {
            revert StETHQueueError(ErrorTypes.StETH__BorrowAmountRawRoundingZero);
        }

        // 5. write linked claim data in storage
        claims[claimTo_][requestIdFrom_] = Claim({
            // storing borrow amount in raw to account for borrow interest that must be paid back at `claim()` time.
            borrowAmountRaw: uint128(borrowAmountRaw_),
            checkpoint: uint48(LIDO_WITHDRAWAL_QUEUE.getLastCheckpointIndex()),
            requestIdTo: uint40(requestIds_[requestIds_.length - 1])
        });

        // 6. emit event
        emit LogQueue(claimTo_, requestIdFrom_, ethBorrowAmount_, stETHAmount_, borrowTo_);
    }

    /// @notice claims all open requests at LidoWithdrawalQueue for `claimTo_`, repays the borrowed ETH amount at Liquidity
    /// and sends the rest of funds to `claimTo_`.
    /// @param claimTo_ claimTo receiver to process the claim for
    /// @param requestIdFrom_ Lido requestId from (start), as emitted at time of queuing (`queue()`) via `LogQueue`
    /// @return claimedAmount_ total amount of claimed stETH
    /// @return repayAmount_ total repaid ETH amount at Liquidity
    function claim(
        address claimTo_,
        uint256 requestIdFrom_
    ) public nonReentrant returns (uint256 claimedAmount_, uint256 repayAmount_) {
        Claim memory claim_ = claims[claimTo_][requestIdFrom_];

        if (claim_.checkpoint == 0) {
            // this implicitly confirms input params claimTo_ and requestIdFrom_ are valid, as a claim was found.
            revert StETHQueueError(ErrorTypes.StETH__NoClaimQueued);
        }

        // store snapshot of balance before claiming
        claimedAmount_ = address(this).balance;

        // 1. claim all requests at Lido. This will burn the NFTs.
        uint256 requestsLength_ = claim_.requestIdTo - requestIdFrom_ + 1;
        if (requestsLength_ == 1) {
            // only one request id
            LIDO_WITHDRAWAL_QUEUE.claimWithdrawal(claim_.requestIdTo);
        } else {
            uint256 curRequest_ = requestIdFrom_;

            // build requestIds array from `requestIdFrom` to `requestIdTo`
            uint256[] memory requestIds_ = new uint256[](requestsLength_);
            for (uint256 i; i < requestsLength_; ) {
                requestIds_[i] = curRequest_;

                unchecked {
                    ++i;
                    ++curRequest_;
                }
            }
            // claim withdrawals at Lido queue
            LIDO_WITHDRAWAL_QUEUE.claimWithdrawals(
                requestIds_,
                LIDO_WITHDRAWAL_QUEUE.findCheckpointHints(
                    requestIds_,
                    claim_.checkpoint,
                    LIDO_WITHDRAWAL_QUEUE.getLastCheckpointIndex()
                )
            );
        }

        claimedAmount_ = address(this).balance - claimedAmount_;

        // 2. calculate borrowed amount to repay after interest with updated exchange price from Liquidity
        // round up for safe rounding
        repayAmount_ = ((claim_.borrowAmountRaw * _getLiquidityExchangePrice()) / EXCHANGE_PRICES_PRECISION) + 1;

        // 3. repay borrow amount at Liquidity. reverts if claimed amount does not cover borrowed amount.
        LIQUIDITY.operate{ value: repayAmount_ }(
            NATIVE_TOKEN_ADDRESS,
            0,
            -int256(repayAmount_),
            address(0),
            address(0),
            new bytes(0) // not needed for native token
        );

        // 4. pay out rest of balance to owner
        Address.sendValue(payable(claimTo_), claimedAmount_ - repayAmount_);

        // 5. delete mapping
        delete claims[claimTo_][requestIdFrom_];

        // 6. emit event
        emit LogClaim(claimTo_, requestIdFrom_, claimedAmount_, repayAmount_);
    }

    /// @notice accept ERC721 token transfers ONLY from LIDO_WITHDRAWAL_QUEUE
    function onERC721Received(
        address /** operator_ */,
        address /** from_ */,
        uint256 /** tokenId_ */,
        bytes memory /** data_ */
    ) public view returns (bytes4) {
        if (msg.sender == address(LIDO_WITHDRAWAL_QUEUE)) {
            return this.onERC721Received.selector;
        }

        revert StETHQueueError(ErrorTypes.StETH__InvalidERC721Transfer);
    }

    /// @notice liquidityCallback as used by Liquidity -> But unsupported in this contract as it only ever uses native
    /// token as borrowed asset, which is repaid directly via `msg.value`. Always reverts.
    function liquidityCallback(
        address /** token_ */,
        uint256 /** amount_ */,
        bytes calldata /** data_ */
    ) external pure {
        revert StETHQueueError(ErrorTypes.StETH__UnexpectedLiquidityCallback);
    }
}
