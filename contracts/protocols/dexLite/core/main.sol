// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./coreInternals.sol";

/// @title FluidDexLite
contract FluidDexLite is CoreInternals {
    constructor(address auth_, address liquidity_, address deployerContract_) {
        _isAuth[auth_] = 1;
        LIQUIDITY = IFluidLiquidity(liquidity_);
        DEPLOYER_CONTRACT = deployerContract_;
    }

    /// @notice Swap through a single dex pool
    /// @dev Uses _swapIn for positive amountSpecified_ (user provides input), _swapOut for negative (user receives output).
    /// @param dexKey_ The dex pool to swap through.
    /// @param swap0To1_ Whether to swap from token0 to token1 or vice versa.
    /// @param amountSpecified_ The amount to swap (positive for exact input, negative for exact output).
    /// @param amountLimit_ The minimum/maximum amount for the unspecified side.
    /// @param to_ The recipient address.
    function swapSingle(
        DexKey calldata dexKey_, 
        bool swap0To1_, 
        int256 amountSpecified_,
        uint256 amountLimit_,
        address to_,
        bool isCallback_,
        bytes calldata callbackData_,
        bytes calldata extraData_
    ) external payable _reentrancyLock returns (uint256 amountUnspecified_) {
        if (amountSpecified_ > 0) {
            amountUnspecified_ = _swapIn(dexKey_, swap0To1_, uint256(amountSpecified_));

            if (amountUnspecified_ < amountLimit_) {
                revert AmountLimitNotMet(amountUnspecified_, amountLimit_);
            }

            if (extraData_.length == 0) {
                if (swap0To1_) {
                    _transferTokens(dexKey_.token0, uint256(amountSpecified_), dexKey_.token1, amountUnspecified_, to_, isCallback_, callbackData_);
                } else {
                    _transferTokens(dexKey_.token1, uint256(amountSpecified_), dexKey_.token0, amountUnspecified_, to_, isCallback_, callbackData_);
                }
            } else if (bytes32(extraData_) == ESTIMATE_SWAP) {
                revert EstimateSwap(amountUnspecified_);
            } else {
                _callExtraDataSlot(
                    abi.encode(
                        SWAP_SINGLE, 
                        abi.encode(dexKey_, swap0To1_, amountSpecified_, amountUnspecified_, extraData_)
                    )
                );
            }
        } else {
            amountUnspecified_ = _swapOut(dexKey_, swap0To1_, uint256(-amountSpecified_));

            if (amountUnspecified_ > amountLimit_) {
                revert AmountLimitExceeded(amountUnspecified_, amountLimit_);
            }

            if (extraData_.length == 0) {
                if (swap0To1_) {
                    _transferTokens(dexKey_.token0, amountUnspecified_, dexKey_.token1, uint256(-amountSpecified_), to_, isCallback_, callbackData_);
                } else {
                    _transferTokens(dexKey_.token1, amountUnspecified_, dexKey_.token0, uint256(-amountSpecified_), to_, isCallback_, callbackData_);
                }
            } else if (bytes32(extraData_) == ESTIMATE_SWAP) {
                revert EstimateSwap(amountUnspecified_);
            } else {
                _callExtraDataSlot(
                    abi.encode(
                        SWAP_SINGLE, 
                        abi.encode(dexKey_, swap0To1_, amountSpecified_, amountUnspecified_, extraData_)
                    )
                );
            }
        }
    }

    /// @notice Swap through a path of dex pools
    /// @dev Uses _swapIn for positive amountSpecified_ (user provides input), _swapOut for negative (user receives output).
    /// @param path_ The path of the swap.
    /// @param dexKeys_ The dex pools to swap through.
    /// @param amountSpecified_ The amount to swap (positive for exact input, negative for exact output).
    /// @param amountLimits_ The minimum/maximum amount for the unspecified side for all swaps.
    /// @param transferParams_ The parameters for the transfer.
    /// @return amountUnspecified_ The amount of the unspecified token.
    function swapHop(
        address[] calldata path_,
        DexKey[] calldata dexKeys_,
        int256 amountSpecified_,
        uint256[] calldata amountLimits_,
        TransferParams calldata transferParams_
    ) external payable _reentrancyLock returns (uint256 amountUnspecified_) {
        if (dexKeys_.length == 0) {
            revert EmptyDexKeysArray();
        }
        if (path_.length - 1 != dexKeys_.length) {
            revert InvalidPathLength(path_.length, dexKeys_.length);
        }
        if (amountLimits_.length != dexKeys_.length) {
            revert InvalidAmountLimitsLength(amountLimits_.length, dexKeys_.length);
        }

        if (amountSpecified_ > 0) {
            // Swap In (Exact input amount provided by the user)
            amountUnspecified_ = uint256(amountSpecified_);

            for (uint256 i = 0; i < dexKeys_.length; ) {
                bool swap0To1_;
                unchecked {
                    if (path_[i] == dexKeys_[i].token0 && path_[i + 1] == dexKeys_[i].token1) {
                        swap0To1_ = true;
                    } else if (path_[i] == dexKeys_[i].token1 && path_[i + 1] == dexKeys_[i].token0) {
                        swap0To1_ = false;
                    } else {
                        revert InvalidPathTokenOrder();
                    }
                }

                amountUnspecified_ = _swapIn(dexKeys_[i], swap0To1_, amountUnspecified_);
                if (amountUnspecified_ < amountLimits_[i]) {
                    revert AmountLimitNotMet(amountUnspecified_, amountLimits_[i]);
                }

                unchecked { ++i; }
            }

            if (transferParams_.extraData.length == 0) {
                _transferTokens(
                    path_[0], 
                    uint256(amountSpecified_), 
                    path_[dexKeys_.length], 
                    amountUnspecified_, 
                    transferParams_.to, 
                    transferParams_.isCallback, 
                    transferParams_.callbackData
                );
            } else if (bytes32(transferParams_.extraData) == ESTIMATE_SWAP) {
                revert EstimateSwap(amountUnspecified_);
            } else {
                _callExtraDataSlot(
                    abi.encode(
                        SWAP_HOP, 
                        abi.encode(path_, dexKeys_, amountSpecified_, amountUnspecified_, transferParams_.extraData)
                    )
                );
            }
                
        } else {
            // Swap Out (Exact output amount received by the user)
            amountUnspecified_ = uint256(-amountSpecified_);

            for (uint256 i = dexKeys_.length; i > 0; ) {
                bool swap0To1_;
                unchecked {
                    if (path_[i - 1] == dexKeys_[i - 1].token0 && path_[i] == dexKeys_[i - 1].token1) {
                        swap0To1_ = true;
                    } else if (path_[i - 1] == dexKeys_[i - 1].token1 && path_[i] == dexKeys_[i - 1].token0) {
                        swap0To1_ = false;
                    } else {
                        revert InvalidPathTokenOrder();
                    }
                }

                amountUnspecified_ = _swapOut(dexKeys_[i - 1], swap0To1_, amountUnspecified_);
                if (amountUnspecified_ > amountLimits_[i - 1]) {
                    revert AmountLimitExceeded(amountUnspecified_, amountLimits_[i - 1]);
                }

                unchecked { --i; }
            }

            if (transferParams_.extraData.length == 0) {
                _transferTokens(
                    path_[0], 
                    amountUnspecified_, 
                    path_[dexKeys_.length], 
                    uint256(-amountSpecified_), 
                    transferParams_.to, 
                    transferParams_.isCallback, 
                    transferParams_.callbackData
                );
            } else if (bytes32(transferParams_.extraData) == ESTIMATE_SWAP) {
                revert EstimateSwap(amountUnspecified_);
            } else {
                _callExtraDataSlot(
                    abi.encode(
                        SWAP_HOP, 
                        abi.encode(path_, dexKeys_, amountSpecified_, amountUnspecified_, transferParams_.extraData)
                    )
                );
            }
        }
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256 result_) {
        assembly {
            result_ := sload(slot_)
        }
    }

    fallback(bytes calldata data_) external payable _reentrancyLock returns (bytes memory) {
        if (_isAuth[msg.sender] != 1 && _getGovernanceAddr() != msg.sender) {
            revert UnauthorizedCaller(msg.sender);
        }

        (address target_, bytes memory spellData_) = abi.decode(data_, (address, bytes));
        return _spell(target_, spellData_);
    }

    receive() external payable {}
}
