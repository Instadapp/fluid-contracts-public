// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

contract ConstantVariables {
    /// @dev Storage slot with the admin of the contract. Logic from "proxy.sol".
    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is validated in the constructor.
    bytes32 internal constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    /// @dev address that is mapped to the chain native token
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @dev decimals for native token
    // !! Double check compatibility with all code if this ever changes for a deployment !!
    uint8 internal constant NATIVE_TOKEN_DECIMALS = 18;

    /// @dev Minimum token decimals for any token that can be listed at Liquidity (inclusive)
    uint8 internal constant MIN_TOKEN_DECIMALS = 6;
    /// @dev Maximum token decimals for any token that can be listed at Liquidity (inclusive)
    uint8 internal constant MAX_TOKEN_DECIMALS = 18;

    /// @dev Ignoring leap years
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /// @dev limit any total amount to be half of type(uint128).max (~3.4e38) at type(int128).max (~1.7e38) as safety
    /// measure for any potential overflows / unexpected outcomes. This is checked for total borrow / supply.
    uint256 internal constant MAX_TOKEN_AMOUNT_CAP = uint256(uint128(type(int128).max));

    /// @dev limit for triggering a revert if sent along excess input amount diff is bigger than this percentage (in 1e2)
    uint256 internal constant MAX_INPUT_AMOUNT_EXCESS = 100; // 1%

    /// @dev if this bytes32 is set in the calldata, then token transfers are skipped as long as Liquidity layer is on the winning side.
    bytes32 internal constant SKIP_TRANSFERS = keccak256(bytes("SKIP_TRANSFERS"));

    /// @dev time after which a write to storage of exchangePricesAndConfig will happen always.
    uint256 internal constant FORCE_STORAGE_WRITE_AFTER_TIME = 1 days;

    /// @dev constants used for BigMath conversion from and to storage
    uint256 internal constant SMALL_COEFFICIENT_SIZE = 10;
    uint256 internal constant DEFAULT_COEFFICIENT_SIZE = 56;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    /// @dev constants to increase readability for using bit masks
    uint256 internal constant FOUR_DECIMALS = 1e4;
    uint256 internal constant TWELVE_DECIMALS = 1e12;
    uint256 internal constant X8 = 0xff;
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X15 = 0x7fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant X64 = 0xffffffffffffffff;
}

contract Variables is ConstantVariables {
    /// @dev address of contract that gets sent the revenue. Configurable by governance
    address internal _revenueCollector;

    // 12 bytes empty

    // ----- storage slot 1 ------

    /// @dev paused status: status = 1 -> normal. status = 2 -> paused.
    /// not tightly packed with revenueCollector address to allow for potential changes later that improve gas more
    /// (revenueCollector is only rarely used by admin methods, where optimization is not as important).
    /// to be replaced with transient storage once EIP-1153 Transient storage becomes available with dencun upgrade.
    uint256 internal _status;

    // ----- storage slot 2 ------

    /// @dev Auths can set most config values. E.g. contracts that automate certain flows like e.g. adding a new fToken.
    /// Governance can add/remove auths.
    /// Governance is auth by default
    mapping(address => uint256) internal _isAuth;

    // ----- storage slot 3 ------

    /// @dev Guardians can pause lower class users
    /// Governance can add/remove guardians
    /// Governance is guardian by default
    mapping(address => uint256) internal _isGuardian;

    // ----- storage slot 4 ------

    /// @dev class defines which protocols can be paused by guardians
    /// Currently there are 2 classes: 0 can be paused by guardians. 1 cannot be paused by guardians.
    /// New protocols are added as class 0 and will be upgraded to 1 over time.
    mapping(address => uint256) internal _userClass;

    // ----- storage slot 5 ------

    /// @dev exchange prices and token config per token: token -> exchange prices & config
    /// First 16 bits =>   0- 15 => borrow rate (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next  14 bits =>  16- 29 => fee on interest from borrowers to lenders (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
    /// Next  14 bits =>  30- 43 => last stored utilization (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    /// Next  14 bits =>  44- 57 => update on storage threshold (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
    /// Next  33 bits =>  58- 90 => last update timestamp (enough until 16 March 2242 -> max value 8589934591)
    /// Next  64 bits =>  91-154 => supply exchange price (1e12 -> max value 18_446_744,073709551615)
    /// Next  64 bits => 155-218 => borrow exchange price (1e12 -> max value 18_446_744,073709551615)
    /// Next   1 bit  => 219-219 => if 0 then ratio is supplyInterestFree / supplyWithInterest else ratio is supplyWithInterest / supplyInterestFree
    /// Next  14 bits => 220-233 => supplyRatio: supplyInterestFree / supplyWithInterest (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    /// Next   1 bit  => 234-234 => if 0 then ratio is borrowInterestFree / borrowWithInterest else ratio is borrowWithInterest / borrowInterestFree
    /// Next  14 bits => 235-248 => borrowRatio: borrowInterestFree / borrowWithInterest (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    /// Next   1 bit  => 249-249 => flag for token uses config storage slot 2. (signals SLOAD for additional config slot is needed during execution)
    /// Last   6 bits => 250-255 => empty for future use
    ///                             if more free bits are needed in the future, update on storage threshold bits could be reduced to 7 bits
    ///                             (can plan to add `MAX_TOKEN_CONFIG_UPDATE_THRESHOLD` but need to adjust more bits)
    ///                             if more bits absolutely needed then we can convert fee, utilization, update on storage threshold,
    ///                             supplyRatio & borrowRatio from 14 bits to 10bits (1023 max number) where 1000 = 100% & 1 = 0.1%
    mapping(address => uint256) internal _exchangePricesAndConfig;

    // ----- storage slot 6 ------

    /// @dev Rate related data per token: token -> rate data
    /// READ (SLOAD): all actions; WRITE (SSTORE): only on set config admin actions
    /// token => rate related data
    /// First 4 bits  =>     0-3 => rate version
    /// rest of the bits are rate dependent:

    /// For rate v1 (one kink) ------------------------------------------------------
    /// Next 16  bits =>  4 - 19 => Rate at utilization 0% (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next 16  bits =>  20- 35 => Utilization at kink1 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next 16  bits =>  36- 51 => Rate at utilization kink1 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next 16  bits =>  52- 67 => Rate at utilization 100% (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Last 188 bits =>  68-255 => empty for future use

    /// For rate v2 (two kinks) -----------------------------------------------------
    /// Next 16  bits =>  4 - 19 => Rate at utilization 0% (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next 16  bits =>  20- 35 => Utilization at kink1 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next 16  bits =>  36- 51 => Rate at utilization kink1 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next 16  bits =>  52- 67 => Utilization at kink2 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next 16  bits =>  68- 83 => Rate at utilization kink2 (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next 16  bits =>  84- 99 => Rate at utilization 100% (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Last 156 bits => 100-255 => empty for future use
    mapping(address => uint256) internal _rateData;

    // ----- storage slot 7 ------

    /// @dev total supply / borrow amounts for with / without interest per token: token -> amounts
    /// First  64 bits =>   0- 63 => total supply with interest in raw (totalSupply = totalSupplyRaw * supplyExchangePrice); BigMath: 56 | 8
    /// Next   64 bits =>  64-127 => total interest free supply in normal token amount (totalSupply = totalSupply); BigMath: 56 | 8
    /// Next   64 bits => 128-191 => total borrow with interest in raw (totalBorrow = totalBorrowRaw * borrowExchangePrice); BigMath: 56 | 8
    /// Next   64 bits => 192-255 => total interest free borrow in normal token amount (totalBorrow = totalBorrow); BigMath: 56 | 8
    mapping(address => uint256) internal _totalAmounts;

    // ----- storage slot 8 ------

    /// @dev user supply data per token: user -> token -> data
    /// First  1 bit  =>       0 => mode: user supply with or without interest
    ///                             0 = without, amounts are in normal (i.e. no need to multiply with exchange price)
    ///                             1 = with interest, amounts are in raw (i.e. must multiply with exchange price to get actual token amounts)
    /// Next  64 bits =>   1- 64 => user supply amount (normal or raw depends on 1st bit); BigMath: 56 | 8
    /// Next  64 bits =>  65-128 => previous user withdrawal limit (normal or raw depends on 1st bit); BigMath: 56 | 8
    /// Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
    /// Next  14 bits => 162-175 => expand withdrawal limit percentage (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383).
    ///                             @dev shrinking is instant
    /// Next  24 bits => 176-199 => withdrawal limit expand duration in seconds.(Max value 16_777_215; ~4_660 hours, ~194 days)
    /// Next  18 bits => 200-217 => base withdrawal limit: below this, 100% withdrawals can be done (normal or raw depends on 1st bit); BigMath: 10 | 8
    /// Next  37 bits => 218-254 => empty for future use
    /// Last     bit  => 255-255 => is user paused (1 = paused, 0 = not paused)
    mapping(address => mapping(address => uint256)) internal _userSupplyData;

    // ----- storage slot 9 ------

    /// @dev user borrow data per token: user -> token -> data
    /// First  1 bit  =>       0 => mode: user borrow with or without interest
    ///                             0 = without, amounts are in normal (i.e. no need to multiply with exchange price)
    ///                             1 = with interest, amounts are in raw (i.e. must multiply with exchange price to get actual token amounts)
    /// Next  64 bits =>   1- 64 => user borrow amount (normal or raw depends on 1st bit); BigMath: 56 | 8
    /// Next  64 bits =>  65-128 => previous user debt ceiling (normal or raw depends on 1st bit); BigMath: 56 | 8
    /// Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
    /// Next  14 bits => 162-175 => expand debt ceiling percentage (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    ///                             @dev shrinking is instant
    /// Next  24 bits => 176-199 => debt ceiling expand duration in seconds (Max value 16_777_215; ~4_660 hours, ~194 days)
    /// Next  18 bits => 200-217 => base debt ceiling: below this, there's no debt ceiling limits (normal or raw depends on 1st bit); BigMath: 10 | 8
    /// Next  18 bits => 218-235 => max debt ceiling: absolute maximum debt ceiling can expand to (normal or raw depends on 1st bit); BigMath: 10 | 8
    /// Next  19 bits => 236-254 => empty for future use
    /// Last     bit  => 255-255 => is user paused (1 = paused, 0 = not paused)
    mapping(address => mapping(address => uint256)) internal _userBorrowData;

    // ----- storage slot 10 ------

    /// @dev list of allowed tokens at Liquidity. tokens that are once configured can never be completely removed. so this
    ///      array is append-only.
    address[] internal _listedTokens;

    // ----- storage slot 11 ------

    /// @dev expanded token configs per token: token -> config data slot 2.
    ///      Use of this is signaled by `_exchangePricesAndConfig` bit 249.
    /// First 14 bits =>   0- 13 => max allowed utilization (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
    /// Last 242 bits =>  14-255 => empty for future use
    mapping(address => uint256) internal _configs2;
}
