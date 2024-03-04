// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/**
 * @title IERC7540DepositReceiver
 * @dev ERC-7540 Deposit Receiver interface
 */
interface IERC7540DepositReceiver {
    /**
     * @notice Deposit request callback
     * @dev The ERC-7540 smart contract calls this function on the receiver after a deposit request has been submitted
     * @param operator The address which called `requestDeposit` function
     * @param owner The owner of the assets being deposited
     * @param requestId The ID of the deposit request
     * @param data Additional data with no specified format, sent in call to `requestDeposit`
     * @return its own signature - `bytes4(keccak256("onERC7540DepositReceived(address,address,uint256,bytes)"))`
     * unless throwing
     **/
    function onERC7540DepositReceived(
        address operator,
        address owner,
        uint256 requestId,
        bytes calldata data
    ) external returns (bytes4);
}