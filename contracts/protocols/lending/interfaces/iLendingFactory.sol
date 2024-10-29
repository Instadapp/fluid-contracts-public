//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";

interface IFluidLendingFactoryAdmin {
    /// @notice reads if a certain `auth_` address is an allowed auth or not. Owner is auth by default.
    function isAuth(address auth_) external view returns (bool);

    /// @notice              Sets an address as allowed auth or not. Only callable by owner.
    /// @param auth_         address to set auth value for
    /// @param allowed_      bool flag for whether address is allowed as auth or not
    function setAuth(address auth_, bool allowed_) external;

    /// @notice reads if a certain `deployer_` address is an allowed deployer or not. Owner is deployer by default.
    function isDeployer(address deployer_) external view returns (bool);

    /// @notice              Sets an address as allowed deployer or not. Only callable by owner.
    /// @param deployer_     address to set deployer value for
    /// @param allowed_      bool flag for whether address is allowed as deployer or not
    function setDeployer(address deployer_, bool allowed_) external;

    /// @notice              Sets the `creationCode_` bytecode for a certain `fTokenType_`. Only callable by auths.
    /// @param fTokenType_   the fToken Type used to refer the creation code
    /// @param creationCode_ contract creation code. can be set to bytes(0) to remove a previously available `fTokenType_`
    function setFTokenCreationCode(string memory fTokenType_, bytes calldata creationCode_) external;

    /// @notice creates token for `asset_` for a lending protocol with interest. Only callable by deployers.
    /// @param  asset_              address of the asset
    /// @param  fTokenType_         type of fToken:
    /// - if it's the native token, it should use `NativeUnderlying`
    /// - otherwise it should use `fToken`
    /// - could be more types available, check `fTokenTypes()`
    /// @param  isNativeUnderlying_ flag to signal fToken type that uses native underlying at Liquidity
    /// @return token_              address of the created token
    function createToken(
        address asset_,
        string calldata fTokenType_,
        bool isNativeUnderlying_
    ) external returns (address token_);
}

interface IFluidLendingFactory is IFluidLendingFactoryAdmin {
    /// @notice list of all created tokens
    function allTokens() external view returns (address[] memory);

    /// @notice list of all fToken types that can be deployed
    function fTokenTypes() external view returns (string[] memory);

    /// @notice returns the creation code for a certain `fTokenType_`
    function fTokenCreationCode(string memory fTokenType_) external view returns (bytes memory);

    /// @notice address of the Liquidity contract.
    function LIQUIDITY() external view returns (IFluidLiquidity);

    /// @notice computes deterministic token address for `asset_` for a lending protocol
    /// @param  asset_      address of the asset
    /// @param  fTokenType_         type of fToken:
    /// - if it's the native token, it should use `NativeUnderlying`
    /// - otherwise it should use `fToken`
    /// - could be more types available, check `fTokenTypes()`
    /// @return token_      detemrinistic address of the computed token
    function computeToken(address asset_, string calldata fTokenType_) external view returns (address token_);
}
