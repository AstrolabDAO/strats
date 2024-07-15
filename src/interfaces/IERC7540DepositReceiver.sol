// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IERC7540DepositReceiver
 * @dev ERC-7540 Deposit Receiver interface
 */
interface IERC7540DepositReceiver {

  /**
   * @notice Deposit request callback
   * @dev The ERC-7540 smart contract calls this function on the receiver after a deposit request has been submitted
   * @param _operator The address which called `requestDeposit` function
   * @param _owner The owner of the assets being deposited
   * @param _requestId The ID of the deposit request
   * @param _amount The amount of assets being deposited
   * @param _data Additional data with no specified format, sent in call to `requestDeposit`
   * @return its own signature - `bytes4(keccak256("onERC7540DepositReceived(address,address,uint256,bytes)"))`
   * unless throwing
   *
   */
  function onERC7540DepositReceived(
    address _operator,
    address _owner,
    uint256 _requestId,
    uint256 _amount,
    bytes calldata _data
  ) external returns (bytes4);
}
