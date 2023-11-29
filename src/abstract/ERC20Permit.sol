// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./Nonces.sol";

interface IERC1271 {
    function isValidSignature(
        bytes32,
        bytes memory
    ) external view returns (bytes4);
}

library NonceLib {

    /**
     * @notice Validates the signature for a given signer, digest, and signature
     * @param signer The address of the signer
     * @param digest The digest of the message
     * @param signature The signature to be validated
     * @return A boolean indicating whether the signature is valid
     */
    function isValidSignature(
        address signer,
        bytes32 digest,
        bytes memory signature
    ) internal view returns (bool) {
        // Implementation of signature validation logic...
    }

    /**
     * @notice Calculates the domain separator for EIP-712
     * @param chainId The chain ID
     * @param name The name of the contract
     * @param version The version of the contract
     * @return The calculated domain separator
     */
    function calculateDomainSeparator(
        uint256 chainId,
        bytes memory name,
        bytes memory version
    ) internal view returns (bytes32) {
        // Implementation of domain separator calculation...
    }
}

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title ERC20Permit Abstract
 * @author Astrolab DAO
 * @notice Permittable ERC20 as defined by the ERC2612
 * @dev Compatible with Permit2
 */
abstract contract ERC20Permit is ERC20, EIP712, Nonces {

    // EIP712 domain separator
    bytes32 private immutable _DOMAIN_SEPARATOR;

    // EIP712 type hash for permit function
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Contract version
    string public VERSION;

    /**
     * @dev Emitted when a signature is expired during permit execution.
     * @param deadline The expiration timestamp of the permit.
     */
    error ERC2612ExpiredSignature(uint256 deadline);

    /**
     * @dev Emitted when the signer of the permit is different from the owner.
     * @param signer The signer address.
     * @param owner The owner address.
     */
    error ERC2612InvalidSigner(address signer, address owner);

    /**
     * @dev Constructor to initialize the ERC20Permit contract
     * @param _name The name of the ERC20 token
     * @param _symbol The symbol of the ERC20 token
     * @param _version The version of the contract
     */
    constructor(string memory _name, string memory _symbol, string memory _version)
        ERC20(_name, _symbol)
        EIP712(_name, _version)
    {
        VERSION = _version;
        _DOMAIN_SEPARATOR = NonceLib.calculateDomainSeparator(block.chainid, bytes(_name), bytes(VERSION));
    }

    /**
     * @notice Permit function to approve spending on behalf of the token owner with a signature
     * @param owner The owner of the tokens
     * @param spender The spender to be approved
     * @param value The amount of tokens to approve
     * @param deadline The deadline for the permit
     * @param signature The signature for the permit
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) public {
        // Permit function implementation...
    }

    /**
     * @notice Permit function to approve spending on behalf of the token owner with signature parameters
     * @param owner The owner of the tokens
     * @param spender The spender to be approved
     * @param value The amount of tokens to approve
     * @param deadline The deadline for the permit
     * @param v The recovery id of the signature
     * @param r The R component of the signature
     * @param s The S component of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Overloaded permit function implementation...
    }

    /**
     * @notice Returns the current nonce for a given owner
     * @param owner The owner address
     * @return The current nonce
     */
    function nonces(
        address owner
    ) public view virtual override(Nonces) returns (uint256) {
        // Nonces function implementation...
    }

    /**
     * @notice Returns the domain separator for EIP-712
     * @return The domain separator
     */
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }
}
