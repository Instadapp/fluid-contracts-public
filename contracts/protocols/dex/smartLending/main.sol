// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IFluidDexT1 } from "../interfaces/iDexT1.sol";
import { FluidDexFactory } from "../factory/main.sol";
import { FluidSmartLendingFactory } from "./factory/main.sol";
import { SafeTransfer } from "../../../libraries/safeTransfer.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";
import { DexSlotsLink } from "../../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../../libraries/dexCalcs.sol";

abstract contract Constants {
    /// @dev Ignoring leap years
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    FluidDexFactory public immutable DEX_FACTORY;

    FluidSmartLendingFactory public immutable SMART_LENDING_FACTORY;

    IFluidDexT1 public immutable DEX;

    address public immutable LIQUIDITY;

    address public immutable TOKEN0;

    address public immutable TOKEN1;

    bool public immutable IS_NATIVE_PAIR;
}

abstract contract Variables is ERC20, Constants {
    // ------------ storage variables from inherited contracts come before vars here --------
    // _________ ERC20 _______________
    // ----------------------- slot 0 ---------------------------
    // mapping(address => uint256) private _balances;

    // ----------------------- slot 1 ---------------------------
    // mapping(address => mapping(address => uint256)) private _allowances;

    // ----------------------- slot 2 ---------------------------
    // uint256 private _totalSupply;

    // ----------------------- slot 3 ---------------------------
    // string private _name;
    // ----------------------- slot 4 ---------------------------
    // string private _symbol;

    // ------------ storage variables ------------------------------------------------------

    // ----------------------- slot 5 ---------------------------
    uint40 public lastTimestamp;
    /// If positive then rewards, if negative then fee.
    /// 1e6 = 100%, 1e4 = 1%, minimum 0.0001% fee or reward.
    int32 public feeOrReward;
    // Starting from 1e18
    // If fees then reduce exchange price
    // If reward then increase exchange price
    uint184 public exchangePrice;

    // ----------------------- slot 6 ---------------------------
    address public rebalancer;

    // ----------------------- slot 7 ---------------------------
    address public dexFromAddress;

    /// @dev status for reentrancy guard
    uint8 internal _status;
}

abstract contract Events {
    /// @dev Emitted when the share to tokens ratio is rebalanced
    /// @param shares_ The number of shares rebalanced
    /// @param token0Amt_ The amount of token0 rebalanced
    /// @param token1Amt_ The amount of token1 rebalanced
    /// @param isWithdraw_ Whether the rebalance is a withdrawal or deposit
    event LogRebalance(uint256 shares_, uint256 token0Amt_, uint256 token1Amt_, bool isWithdraw_);

    /// @dev Emitted when the rebalancer is set
    /// @param rebalancer The new rebalancer
    event LogRebalancerSet(address rebalancer);

    /// @dev Emitted when the fee or reward is set
    /// @param feeOrReward The new fee or reward
    event LogFeeOrRewardSet(int256 feeOrReward);
}

/// @dev ReentrancyGuard based on OpenZeppelin implementation.
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.8/contracts/security/ReentrancyGuard.sol
abstract contract ReentrancyGuard is Variables, Error {
    uint8 internal constant REENTRANCY_NOT_ENTERED = 1;
    uint8 internal constant REENTRANCY_ENTERED = 2;

    constructor() {
        _status = REENTRANCY_NOT_ENTERED;
    }

    /// @dev Prevents a contract from calling itself, directly or indirectly.
    /// See OpenZeppelin implementation for more info
    modifier nonReentrant() {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status != REENTRANCY_NOT_ENTERED) {
            revert FluidSmartLendingError(ErrorTypes.SmartLending__Reentrancy);
        }

        // Any calls to nonReentrant after this point will fail
        _status = REENTRANCY_ENTERED;

        _;

        // storing original value triggers a refund (see https://eips.ethereum.org/EIPS/eip-2200)
        _status = REENTRANCY_NOT_ENTERED;
    }
}

contract FluidSmartLending is ERC20, Variables, Error, ReentrancyGuard, Events {
    /// @dev prefix for token name. constructor appends dex id, e.g. "Fluid Smart Lending 12"
    string private constant TOKEN_NAME_PREFIX = "Fluid Smart Lending ";
    /// @dev prefix for token symbol. constructor appends dex id, e.g. "fSL12"
    string private constant TOKEN_SYMBOL_PREFIX = "fSL";

    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidSmartLendingError(ErrorTypes.SmartLending__ZeroAddress);
        }
        _;
    }

    constructor(
        uint256 dexId_,
        address liquidity_,
        address dexFactory_,
        address smartLendingFactory_
    )
        ERC20(
            string(abi.encodePacked(TOKEN_NAME_PREFIX, _toString(dexId_))),
            string(abi.encodePacked(TOKEN_SYMBOL_PREFIX, _toString(dexId_)))
        )
        validAddress(liquidity_)
        validAddress(dexFactory_)
        validAddress(smartLendingFactory_)
    {
        LIQUIDITY = liquidity_;
        DEX_FACTORY = FluidDexFactory(dexFactory_);
        SMART_LENDING_FACTORY = FluidSmartLendingFactory(smartLendingFactory_);
        DEX = IFluidDexT1(DEX_FACTORY.getDexAddress(dexId_));
        IFluidDexT1.ConstantViews memory constants_ = DEX.constantsView();
        TOKEN0 = constants_.token0;
        TOKEN1 = constants_.token1;
        IS_NATIVE_PAIR = (TOKEN0 == ETH_ADDRESS) || (TOKEN1 == ETH_ADDRESS);

        exchangePrice = uint184(1e18);
        feeOrReward = int32(0);
        lastTimestamp = uint40(block.timestamp);

        dexFromAddress = DEAD_ADDRESS;
    }

    modifier setDexFrom() {
        dexFromAddress = msg.sender;
        _;
        dexFromAddress = DEAD_ADDRESS;
    }

    modifier onlyAuth() {
        if (!SMART_LENDING_FACTORY.isSmartLendingAuth(address(this), msg.sender)) {
            revert FluidSmartLendingError(ErrorTypes.SmartLending__Unauthorized);
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != SMART_LENDING_FACTORY.owner()) {
            revert FluidSmartLendingError(ErrorTypes.SmartLending__Unauthorized);
        }
        _;
    }

    modifier _updateExchangePrice() {
        bool rewardsOrFeeActive_;
        (exchangePrice, rewardsOrFeeActive_) = getUpdateExchangePrice();
        if (rewardsOrFeeActive_) {
            lastTimestamp = uint40(block.timestamp); // only write to storage if fee or reward is active.
        }
        _;
    }

    /// @notice gets updated exchange price
    function getUpdateExchangePrice() public view returns (uint184 exchangePrice_, bool rewardsOrFeeActive_) {
        int256 feeOrReward_ = feeOrReward;
        exchangePrice_ = exchangePrice;
        if (feeOrReward_ > 0) {
            exchangePrice_ =
                exchangePrice_ +
                uint184(
                    (exchangePrice_ * uint256(feeOrReward_) * (block.timestamp - uint256(lastTimestamp))) /
                        (1e6 * SECONDS_PER_YEAR)
                );
            rewardsOrFeeActive_ = true;
        } else if (feeOrReward_ < 0) {
            exchangePrice_ =
                exchangePrice_ -
                uint184(
                    (exchangePrice_ * uint256(-feeOrReward_) * (block.timestamp - uint256(lastTimestamp))) /
                        (1e6 * SECONDS_PER_YEAR)
                );
            rewardsOrFeeActive_ = true;
        }
    }

    /// @notice triggers updateExchangePrice
    function updateExchangePrice() public _updateExchangePrice {}

    /// @dev Set the fee or reward. Only callable by auths.
    /// @param feeOrReward_ The new fee or reward (1e6 = 100%, 1e4 = 1%, minimum 0.0001% fee or reward). 0 means no fee or reward
    function setFeeOrReward(int256 feeOrReward_) external onlyAuth _updateExchangePrice {
        if (feeOrReward_ > 1e6 || feeOrReward_ < -1e6) {
            revert FluidSmartLendingError(ErrorTypes.SmartLending__OutOfRange);
        }
        lastTimestamp = uint40(block.timestamp); // current fee or reward setting is applied until exactly now even if previously 0
        feeOrReward = int32(feeOrReward_);

        emit LogFeeOrRewardSet(feeOrReward_);
    }

    /// @dev Set the rebalancer. Only callable by auths.
    /// @param rebalancer_ The new rebalancer
    function setRebalancer(address rebalancer_) external onlyAuth validAddress(rebalancer_) {
        rebalancer = rebalancer_;

        emit LogRebalancerSet(rebalancer_);
    }

    /// @notice                         Spell allows auths (governance) to do any arbitrary call
    /// @param target_                  Address to which the call needs to be delegated
    /// @param data_                    Data to execute at the delegated address
    function spell(address target_, bytes memory data_) external onlyOwner returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    /// @dev Deposit tokens in equal proportion to the current pool ratio
    /// @param shares_ The number of shares to mint
    /// @param maxToken0Deposit_ Maximum amount of token0 to deposit
    /// @param maxToken1Deposit_ Maximum amount of token1 to deposit
    /// @param to_ Recipient of minted tokens. If to_ == address(0) then out tokens will be sent to msg.sender.
    /// @return amount_ Amount of tokens minted
    /// @return token0Amt_ Amount of token0 deposited
    /// @return token1Amt_ Amount of token1 deposited
    function depositPerfect(
        uint256 shares_,
        uint256 maxToken0Deposit_,
        uint256 maxToken1Deposit_,
        address to_
    )
        external
        payable
        setDexFrom
        _updateExchangePrice
        nonReentrant
        returns (uint256 amount_, uint256 token0Amt_, uint256 token1Amt_)
    {
        if (!IS_NATIVE_PAIR) {
            if (msg.value > 0) {
                revert FluidSmartLendingError(ErrorTypes.SmartLending__InvalidMsgValue);
            }

            (token0Amt_, token1Amt_) = DEX.depositPerfect(
                shares_ + 1, // + 1 rounding up but only minting shares
                maxToken0Deposit_,
                maxToken1Deposit_,
                false
            );
        } else {
            uint256 value_ = TOKEN0 == ETH_ADDRESS ? maxToken0Deposit_ : maxToken1Deposit_;
            if (value_ > msg.value) {
                revert FluidSmartLendingError(ErrorTypes.SmartLending__InvalidMsgValue);
            }

            uint256 initialEthAmount_ = address(this).balance - msg.value;

            (token0Amt_, token1Amt_) = DEX.depositPerfect{ value: value_ }(
                shares_ + 1, // + 1 rounding up but only minting shares
                maxToken0Deposit_,
                maxToken1Deposit_,
                false
            );

            uint finalEth_ = payable(address(this)).balance;
            if (finalEth_ > initialEthAmount_) {
                unchecked {
                    SafeTransfer.safeTransferNative(msg.sender, finalEth_ - initialEthAmount_); // sending back excess ETH
                }
            }
        }

        to_ = to_ == address(0) ? msg.sender : to_;

        amount_ = (shares_ * 1e18) / exchangePrice;

        _mint(to_, amount_);
    }

    /// @dev This function allows users to deposit tokens in any proportion into the col pool
    /// @param token0Amt_ The amount of token0 to deposit
    /// @param token1Amt_ The amount of token1 to deposit
    /// @param minSharesAmt_ The minimum amount of shares the user expects to receive
    /// @param to_ Recipient of minted tokens. If to_ == address(0) then out tokens will be sent to msg.sender.
    /// @return amount_ The amount of tokens minted for the deposit
    /// @return shares_ The number of dex pool shares deposited
    function deposit(
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 minSharesAmt_,
        address to_
    ) external payable setDexFrom _updateExchangePrice nonReentrant returns (uint256 amount_, uint256 shares_) {
        uint256 value_ = !IS_NATIVE_PAIR
            ? 0
            : (TOKEN0 == ETH_ADDRESS)
                ? token0Amt_
                : token1Amt_;

        if (value_ != msg.value) {
            revert FluidSmartLendingError(ErrorTypes.SmartLending__InvalidMsgValue);
        }

        to_ = to_ == address(0) ? msg.sender : to_;

        shares_ = DEX.deposit{ value: value_ }(token0Amt_, token1Amt_, minSharesAmt_, false);

        amount_ = (shares_ * 1e18) / exchangePrice - 1;

        _mint(to_, amount_);
    }

    /// @dev This function allows users to withdraw a perfect amount of collateral liquidity
    /// @param shares_ The number of shares to withdraw. set to type(uint).max to withdraw maximum balance.
    /// @param minToken0Withdraw_ The minimum amount of token0 the user is willing to accept
    /// @param minToken1Withdraw_ The minimum amount of token1 the user is willing to accept
    /// @param to_ Recipient of withdrawn tokens. If to_ == address(0) then out tokens will be sent to msg.sender.
    /// @return amount_ amount_ of shares actually burnt
    /// @return token0Amt_ The amount of token0 withdrawn
    /// @return token1Amt_ The amount of token1 withdrawn
    function withdrawPerfect(
        uint256 shares_,
        uint256 minToken0Withdraw_,
        uint256 minToken1Withdraw_,
        address to_
    ) external _updateExchangePrice nonReentrant returns (uint256 amount_, uint256 token0Amt_, uint256 token1Amt_) {
        if (shares_ == type(uint).max) {
            amount_ = balanceOf(msg.sender);
            shares_ = (amount_ * exchangePrice) / 1e18 - 1;
        } else {
            amount_ = (shares_ * 1e18) / exchangePrice + 1;
        }

        _burn(msg.sender, amount_);

        to_ = to_ == address(0) ? msg.sender : to_;

        if (minToken0Withdraw_ > 0 && minToken1Withdraw_ > 0) {
            (token0Amt_, token1Amt_) = DEX.withdrawPerfect(shares_, minToken0Withdraw_, minToken1Withdraw_, to_);
        } else if (minToken0Withdraw_ > 0 && minToken1Withdraw_ == 0) {
            // withdraw only in token0, token1Amt_ remains 0
            (token0Amt_) = DEX.withdrawPerfectInOneToken(shares_, minToken0Withdraw_, minToken1Withdraw_, to_);
        } else if (minToken0Withdraw_ == 0 && minToken1Withdraw_ > 0) {
            // withdraw only in token1, token0Amt_ remains 0
            (token1Amt_) = DEX.withdrawPerfectInOneToken(shares_, minToken0Withdraw_, minToken1Withdraw_, to_);
        } else {
            // meaning user sent both amounts as == 0
            revert FluidSmartLendingError(ErrorTypes.SmartLending__InvalidAmounts);
        }
    }

    /// @dev This function allows users to withdraw tokens in any proportion from the col pool
    /// @param token0Amt_ The amount of token0 to withdraw
    /// @param token1Amt_ The amount of token1 to withdraw
    /// @param maxSharesAmt_ The maximum number of shares the user is willing to burn
    /// @param to_ Recipient of withdrawn tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with shares_
    /// @return amount_ The number of tokens burned for the withdrawal
    /// @return shares_ The number of dex pool shares withdrawn
    function withdraw(
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 maxSharesAmt_,
        address to_
    ) external _updateExchangePrice nonReentrant returns (uint256 amount_, uint256 shares_) {
        to_ = to_ == address(0) ? msg.sender : to_;

        shares_ = DEX.withdraw(token0Amt_, token1Amt_, maxSharesAmt_, to_);

        amount_ = (shares_ * 1e18) / exchangePrice + 1;

        _burn(msg.sender, amount_);
    }

    /// @dev Rebalances the share to tokens ratio to balance out rewards and fees
    function rebalance(
        uint256 minOrMaxToken0_,
        uint256 minOrMaxToken1_
    )
        public
        payable
        _updateExchangePrice
        nonReentrant
        returns (uint256 shares_, uint256 token0Amt_, uint256 token1Amt_, bool isWithdraw_)
    {
        if (rebalancer != msg.sender) revert FluidSmartLendingError(ErrorTypes.SmartLending__InvalidRebalancer);

        int256 rebalanceDiff_ = rebalanceDiff();

        if (rebalanceDiff_ > 0) {
            // fees (withdraw)
            isWithdraw_ = true;
            if (msg.value > 0) {
                revert FluidSmartLendingError(ErrorTypes.SmartLending__InvalidMsgValue);
            }
            shares_ = uint256(rebalanceDiff_);
            (token0Amt_, token1Amt_) = DEX.withdrawPerfect(shares_, minOrMaxToken0_, minOrMaxToken1_, msg.sender);
        } else if (rebalanceDiff_ < 0) {
            // rewards (deposit)
            isWithdraw_ = false;

            uint256 initialEthAmount_ = address(this).balance - msg.value;

            uint256 value_ = !IS_NATIVE_PAIR
                ? 0
                : (TOKEN0 == ETH_ADDRESS)
                    ? minOrMaxToken0_
                    : minOrMaxToken1_;

            if (value_ > msg.value) {
                revert FluidSmartLendingError(ErrorTypes.SmartLending__InvalidMsgValue);
            }

            shares_ = uint256(-rebalanceDiff_);

            dexFromAddress = msg.sender;
            (token0Amt_, token1Amt_) = DEX.depositPerfect{ value: value_ }(
                shares_,
                minOrMaxToken0_,
                minOrMaxToken1_,
                false
            );
            dexFromAddress = DEAD_ADDRESS;

            uint finalEth_ = payable(address(this)).balance;
            if (finalEth_ > initialEthAmount_) {
                unchecked {
                    SafeTransfer.safeTransferNative(msg.sender, finalEth_ - initialEthAmount_); // sending back excess ETH
                }
            }
        }

        emit LogRebalance(shares_, token0Amt_, token1Amt_, isWithdraw_);
    }

    /// @dev Returns the difference between the total smart lending shares on the DEX and the total smart lending shares calculated.
    /// A positive value indicates fees to collect, while a negative value indicates rewards to be rebalanced.
    function rebalanceDiff() public view returns (int256) {
        uint256 totalSmartLendingSharesOnDex_ = DEX.readFromStorage(
            DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, address(this))
        );
        totalSmartLendingSharesOnDex_ =
            (totalSmartLendingSharesOnDex_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) &
            DexCalcs.X64;
        totalSmartLendingSharesOnDex_ =
            (totalSmartLendingSharesOnDex_ >> DexCalcs.DEFAULT_EXPONENT_SIZE) <<
            (totalSmartLendingSharesOnDex_ & DexCalcs.DEFAULT_EXPONENT_MASK);

        uint256 totalSmartLendingShares_ = (totalSupply() * exchangePrice) / 1e18;

        return int256(totalSmartLendingSharesOnDex_) - int256(totalSmartLendingShares_);
    }

    /// @notice   dex liquidity callback
    /// @param    token_ The token being transferred
    /// @param    amount_ The amount being transferred
    function dexCallback(address token_, uint256 amount_) external {
        if (msg.sender != address(DEX)) {
            revert FluidSmartLendingError(ErrorTypes.SmartLending__Unauthorized);
        }
        SafeTransfer.safeTransferFrom(token_, dexFromAddress, LIQUIDITY, amount_);
    }

    /// @dev for excess eth being sent back from dex to here
    receive() external payable {
        if (msg.sender != address(DEX)) {
            revert FluidSmartLendingError(ErrorTypes.SmartLending__Unauthorized);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     * taken from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol
     */
    function _log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     * taken from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol
     */
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    function _toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = _log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            assembly ("memory-safe") {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                assembly ("memory-safe") {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }
}
