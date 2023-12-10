
// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

interface IERC20Permit is IERC20Metadata {
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
    ) external;

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
    ) external;

    /**
     * @notice Returns the current nonce for a given owner
     * @param owner The owner address
     * @return The current nonce
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @notice Returns the domain separator for EIP-712
     * @return The domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Returns the deployment chain ID
     * @return The chain ID on which the contract was deployed
     */
    function getDeploymentChainId() external view returns (uint256);

    /**
     * @notice Returns the EIP712 type hash for permit function
     * @return The type hash for permit function
     */
    function getPermitTypeHash() external view returns (bytes32);

    /**
     * @notice Returns the version of the contract
     * @return The contract version
     */
    function getVersion() external view returns (string memory);
}
