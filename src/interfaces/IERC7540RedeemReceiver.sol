// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/**
 * @title IERC7540RedeemReceiver
 * @dev ERC-7540 Redeem Receiver interface
 */
interface IERC7540RedeemReceiver {
    /**
     * @notice Handle the receipt of a redeem request.
     * @dev The ERC-7540 smart contract calls this function on the receiver after a redeem request has been submitted.
     * This function MAY throw to revert and reject the request.
     * Return of other than the magic value MUST result in the transaction being reverted.
     * Note: the contract address is always the message sender.
     * @param operator The address which called `requestRedeem` function.
     * @param owner The owner of the shares being redeemed.
     * @param requestId The ID of the redeem request.
     * @param data Additional data with no specified format, sent in call to `requestRedeem`.
     * @return `bytes4(keccak256("onERC7540RedeemReceived(address,address,uint256,bytes)"))`
     * unless throwing.
     **/
    function onERC7540RedeemReceived(
        address operator,
        address owner,
        uint256 requestId,
        bytes calldata data
    ) external returns (bytes4);
}