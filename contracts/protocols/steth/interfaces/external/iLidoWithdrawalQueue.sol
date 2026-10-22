//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ILidoWithdrawalQueue {
    function balanceOf(address) external view returns (uint);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    // code below based on Lido WithdrawalQueueBase.sol
    // see https://github.com/lidofinance/lido-dao/blob/v2.0.0/contracts/0.8.9/WithdrawalQueueBase.sol

    /// @notice output format struct for `_getWithdrawalStatus()` method
    struct WithdrawalRequestStatus {
        /// @notice stETH token amount that was locked on withdrawal queue for this request
        uint256 amountOfStETH;
        /// @notice amount of stETH shares locked on withdrawal queue for this request
        uint256 amountOfShares;
        /// @notice address that can claim or transfer this request
        address owner;
        /// @notice timestamp of when the request was created, in seconds
        uint256 timestamp;
        /// @notice true, if request is finalized
        bool isFinalized;
        /// @notice true, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    /// @notice length of the checkpoint array. Last possible value for the hint.
    ///  NB! checkpoints are indexed from 1, so it returns 0 if there is no checkpoints
    function getLastCheckpointIndex() external view returns (uint256);

    // code below based on Lido WithdrawalQueue.sol
    // see https://github.com/lidofinance/lido-dao/blob/v2.0.0/contracts/0.8.9/WithdrawalQueue.sol

    /// @notice Request the batch of stETH for withdrawal. Approvals for the passed amounts should be done before.
    /// @param _amounts an array of stETH amount values.
    ///  The standalone withdrawal request will be created for each item in the passed list.
    /// @param _owner address that will be able to manage the created requests.
    ///  If `address(0)` is passed, `msg.sender` will be used as owner.
    /// @return requestIds an array of the created withdrawal request ids
    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);

    /// @notice Claim one`_requestId` request once finalized sending locked ether to the owner
    /// @param _requestId request id to claim
    /// @dev use unbounded loop to find a hint, which can lead to OOG
    /// @dev
    ///  Reverts if requestId or hint are not valid
    ///  Reverts if request is not finalized or already claimed
    ///  Reverts if msg sender is not an owner of request
    function claimWithdrawal(uint256 _requestId) external;

    /// @notice Claim a batch of withdrawal requests if they are finalized sending locked ether to the owner
    /// @param _requestIds array of request ids to claim
    /// @param _hints checkpoint hint for each id. Can be obtained with `findCheckpointHints()`
    /// @dev
    ///  Reverts if requestIds and hints arrays length differs
    ///  Reverts if any requestId or hint in arguments are not valid
    ///  Reverts if any request is not finalized or already claimed
    ///  Reverts if msg sender is not an owner of the requests
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;

    //// @notice Returns all withdrawal requests that belongs to the `_owner` address
    ///
    /// WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
    /// to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
    /// this function has an unbounded cost, and using it as part of a state-changing function may render the function
    /// uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
    function getWithdrawalRequests(address _owner) external view returns (uint256[] memory requestsIds);

    /// @notice Finds the list of hints for the given `_requestIds` searching among the checkpoints with indices
    ///  in the range  `[_firstIndex, _lastIndex]`.
    ///  NB! Array of request ids should be sorted
    ///  NB! `_firstIndex` should be greater than 0, because checkpoint list is 1-based array
    ///  Usage: findCheckpointHints(_requestIds, 1, getLastCheckpointIndex())
    /// @param _requestIds ids of the requests sorted in the ascending order to get hints for
    /// @param _firstIndex left boundary of the search range. Should be greater than 0
    /// @param _lastIndex right boundary of the search range. Should be less than or equal to getLastCheckpointIndex()
    /// @return hintIds array of hints used to find required checkpoint for the request
    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256 _firstIndex,
        uint256 _lastIndex
    ) external view returns (uint256[] memory hintIds);

    /// @notice Returns status for requests with provided ids
    /// @param _requestIds array of withdrawal request ids
    function getWithdrawalStatus(
        uint256[] calldata _requestIds
    ) external view returns (WithdrawalRequestStatus[] memory statuses);

    /// @notice maximum amount of stETH that is possible to withdraw by a single request
    /// Prevents accumulating too much funds per single request fulfillment in the future.
    /// @dev To withdraw larger amounts, it's recommended to split it to several requests
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    /// @notice minimum amount of stETH that is possible to withdraw by a single request
    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    // code below based on Lido WithdrawalQueueERC721.sol
    // see https://github.com/lidofinance/lido-dao/blob/v2.0.0/contracts/0.8.9/WithdrawalQueueERC721.sol

    /// @notice Finalize requests from last finalized one up to `_lastRequestIdToBeFinalized`
    /// @dev ether to finalize all the requests should be calculated using `prefinalize()` and sent along
    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;
}
