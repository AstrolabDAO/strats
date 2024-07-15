// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

/**
 * @title IERC7540RedeemReceiver
 * @dev ERC-7540 Redeem Receiver interface
 */
interface IERC7540RedeemReceiver {

  /**
   * @notice Redeem request callback
   * @dev The ERC-7540 smart contract calls this function on the receiver after a redeem request has been submitted
   * @param _operator The address which called `requestRedeem` function
   * @param _owner The owner of the shares being redeemed
   * @param _requestId The ID of the redeem request
   * @param _shares The amount of shares being redeemed
   * @param _data Additional data with no specified format, sent in call to `requestRedeem`
   * @return its own signature - `bytes4(keccak256("onERC7540RedeemReceived(address,address,uint256,bytes)"))`
   * unless throwing
   *
   */
  function onERC7540RedeemReceived(
    address _operator,
    address _owner,
    uint256 _requestId,
    uint256 _shares,
    bytes calldata _data
  ) external returns (bytes4);
}
