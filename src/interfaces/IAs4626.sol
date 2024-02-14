// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "../abstract/AsTypes.sol";
import "./IERC20Permit.sol";
import "./IAsManageable.sol";
import "./IAsRescuable.sol";

/**
 * @title IFlashLoanReceiver
 * @author Astrolab DAO, based on AAVE's work (cf. https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol)
 * @notice Defines the basic interface of a flashloan-receiver contract.
 * @dev Implement this interface to develop a flashloan-compatible flashLoanReceiver contract
 */
interface IFlashLoanReceiver {
    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @dev Ensure that the contract can return the debt + premium, e.g., has
     *      enough funds to repay and has approved the Pool to pull the total amount
     * @param asset The address of the flash-borrowed asset
     * @param amount The amount of the flash-borrowed asset
     * @param premium The premium amount to be repaid along with the debt
     * @param initiator The address initiating the flash loan
     * @param params Additional parameters for the operation
     * @return A boolean indicating the success of the operation
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IAs4626Abstract is IERC20Permit, IAsManageable, IAsRescuable, IFlashLoanReceiver {
    function maxSlippageBps() external view returns (uint16);
    function profitCooldown() external view returns (uint256);
    function maxTotalAssets() external view returns (uint256);
    function minLiquidity() external view returns (uint256);
    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function weiPerShare() external view returns (uint256);
    function expectedProfits() external view returns (uint256);
    function maxFees() external view returns (Fees memory);
    function fees() external view returns (Fees memory);
    function feeCollector() external view returns (address);
    function last() external view returns (Epoch memory);
    function claimableAssetFees() external view returns (uint256);
    function isExemptFromFees(address account) external view returns (bool);
    function invested() external view returns (uint256);
    function available() external view returns (uint256);
    function availableClaimable() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function totalAccountedAssets() external view returns (uint256);
    function totalAccountedSupply() external view returns (uint256);
    function tvl() external view returns (uint256);
    function sharePrice() external view returns (uint256);
    function assetsOf(address _owner) external view returns (uint256);
    function convertToShares(uint256 _assets) external view returns (uint256);
    function convertToAssets(uint256 _shares) external view returns (uint256);
    function pendingRedeemRequest(address operator) external view returns (uint256);
    function pendingAssetRequest(address operator) external view returns (uint256);
    function isRequestClaimable(uint256 requestTimestamp) external view returns (bool);
    function maxClaimableAsset() external view returns (uint256);
    function claimableRedeemRequest(address _owner) external view returns (uint256);
}

interface IAs4626 is IAs4626Abstract {
    function init(
        Fees memory _fees,
        address _asset,
        address _feeCollector
    ) external;

    function mint(
        uint256 _shares,
        address _receiver
    ) external returns (uint256 assets);

    function previewDeposit(
        uint256 _amount
    ) external view returns (uint256 shares);

    function deposit(
        uint256 _amount,
        address _receiver
    ) external returns (uint256 shares);

    function safeDeposit(
        uint256 _amount,
        uint256 _minShareAmount,
        address _receiver
    ) external returns (uint256 shares);

    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) external returns (uint256 shares);

    function safeWithdraw(
        uint256 _amount,
        uint256 _minAmount,
        address _receiver,
        address _owner
    ) external returns (uint256 shares);

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) external returns (uint256 assets);

    function safeRedeem(
        uint256 _shares,
        uint256 _minAmountOut,
        address _receiver,
        address _owner
    ) external returns (uint256 assets);

    function collectFees() external;
    function pause() external;
    function unpause() external;
    function setFeeCollector(address _feeCollector) external;
    function setMaxTotalAssets(uint256 _maxTotalAssets) external;
    function seedLiquidity(
        uint256 _seedDeposit,
        uint256 _maxTotalAssets
    ) external;
    function setFees(Fees memory _fees) external;
    function setMinLiquidity(uint256 _minLiquidity) external;
    function setProfitCooldown(uint256 _profitCooldown) external;
    function setRedemptionRequestLocktime(
        uint256 _redemptionLocktime
    ) external;
    function previewMint(uint256 _shares) external view returns (uint256);
    function previewWithdraw(uint256 _assets) external view returns (uint256);
    function previewRedeem(uint256 _shares) external view returns (uint256);
    function previewRedeem(uint256 _shares, address _owner) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);

    function maxWithdraw(address _owner) external view returns (uint256);
    function maxRedeem(address _owner) external view returns (uint256);
    function requestDeposit(
        uint256 assets,
        address operator
    ) external;
    function requestRedeem(
        uint256 shares,
        address operator,
        address owner
    ) external;
    function requestWithdraw(
        uint256 _amount,
        address operator,
        address owner
    ) external;
    function cancelDepositRequest(
        address operator,
        address owner
    ) external;
    function cancelRedeemRequest(
        address operator,
        address owner
    ) external;
    function totalRedemptionRequest() external view returns (uint256);
    function totalClaimableRedemption() external view returns (uint256);
    function flashLoanSimple(IFlashLoanReceiver receiver, uint256 amount, bytes calldata params) external;
    function maxLoan(address _token) external view returns (uint256);
}
