// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IAllowanceTransfer } from "../../../../contracts/protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";
import { ISignatureTransfer } from "../../../../contracts/protocols/lending/interfaces/permit2/ISignatureTransfer.sol";

interface IEIP712 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/// @dev helper contract for permit tests
/// based on https://book.getfoundry.sh/tutorials/testing-eip712, extended with logic for permit2 based on
/// https://github.com/dragonfly-xyz/useful-solidity-patterns/blob/main/test/Permit2Vault.t.sol#L216
contract SigUtils {
    bytes32 public immutable _PERMIT2_DOMAIN_SEPARATOR;
    bytes32 public immutable _PERMIT_DOMAIN_SEPARATOR;

    // permit2
    bytes32 internal constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 internal constant _PERMIT_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    // permit
    bytes32 internal constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    constructor(address permit2_, bytes32 vaultDomainSeparator_) {
        _PERMIT2_DOMAIN_SEPARATOR = IEIP712(permit2_).DOMAIN_SEPARATOR();
        _PERMIT_DOMAIN_SEPARATOR = vaultDomainSeparator_;
    }

    // // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function permit2TypedDataHash(
        ISignatureTransfer.PermitTransferFrom memory permit,
        address spender
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", _PERMIT2_DOMAIN_SEPARATOR, _hashPermitTransferFrom(permit, spender))
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function permitTypedDataHash(Permit memory _permit) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _PERMIT_DOMAIN_SEPARATOR, _hashPermit(_permit)));
    }

    // computes the hash of a permit
    function _hashPermit(Permit memory _permit) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _PERMIT_TYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }

    // // Compute the EIP712 hash of the permit object.
    // // Normally this would be implemented off-chain.
    // // spender = Permit2 contract
    function _hashPermitTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        address spender
    ) internal pure returns (bytes32) {
        bytes32 tokenPermissionsHash = _hashTokenPermissions(permit.permitted);
        return
            keccak256(
                abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissionsHash, spender, permit.nonce, permit.deadline)
            );
    }

    function _hashTokenPermissions(
        ISignatureTransfer.TokenPermissions memory permitted
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permitted));
    }
}
