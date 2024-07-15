// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IERC3156FlashBorrower - Ex AAVE FlashLoanReceiver
 * @author Astrolab DAO
 * @notice Defines the basic interface of a flashloan-receiver contract
 * @dev Implement this interface to develop a flashloan-compatible flashLoanReceiver contract
 */
interface IERC3156FlashBorrower {
  // /**
  //  * @notice Deprecated flash loan (AAVE compatible)
  //  * @dev Executes an operation after receiving the borrowed assets
  //  * @dev Ensure that the contract can return the debt + premium, e.g., has
  //  *      enough funds to repay and has approved the Pool to pull the total amount
  //  * @param asset Address of the borrowed asset (typically the lending vault's underlying asset)
  //  * @param amount Amount of the borrowed asset
  //  * @param fee Fee charged for the flash loan
  //  * @param initiator Account initiating the flash loan
  //  * @param params Parameters for the function call
  //  * @return Boolean indicating the success of the operation
  //  */
  // function executeOperation(
  //   address asset,
  //   uint256 amount,
  //   uint256 fee,
  //   address initiator,
  //   bytes calldata params
  // ) external returns (bool);

  /**
   * @notice ERC-3156 compliant flash loan
   * @dev Executes an operation after receiving the borrowed assets
   * @param initiator Account initiating the flash loan
   * @param token Address of the borrowed asset (typically the lending vault's underlying asset)
   * @param amount Amount of tokens being borrowed
   * @param fee Fee charged for the flash loan
   * @param params Parameters for the function call
   * @return The operation signature (keccak256("ERC3156FlashBorrower.onFlashLoan"))
   */
  function onFlashLoan(
    address initiator,
    address token,
    uint256 amount,
    uint256 fee,
    bytes calldata params
  ) external returns (bytes32);
}
