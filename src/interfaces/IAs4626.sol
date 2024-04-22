// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./IAsManageable.sol";
import "./IAsRescuable.sol";
import "../abstract/AsTypes.sol";

interface IAs4626 is IERC20Metadata, IAsRescuable, IAsManageable {
  // Events
  event Deposit(
    address indexed sender, address indexed owner, uint256 assets, uint256 shares
  );
  event Withdraw(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );
  event DepositRequest(
    address indexed receiver,
    address indexed owner,
    uint256 indexed requestId,
    address sender,
    uint256 assets
  );
  event RedeemRequest(
    address indexed receiver,
    address indexed owner,
    uint256 indexed requestId,
    address sender,
    uint256 shares
  );
  event RedeemRequestCanceled(address indexed owner, uint256 assets);
  event FeeCollection(
    address indexed collector,
    uint256 totalAssets,
    uint256 sharePrice,
    uint256 profit,
    uint256 totalFees,
    uint256 sharesMinted
  );

  // Initialization and settings
  function seedLiquidity(uint256 _seedDeposit, uint256 _maxTotalAssets) external;
  function setFeeCollector(address _feeCollector) external;
  function setMaxSlippageBps(uint16 _bps) external;
  function setMaxTotalAssets(uint256 _maxTotalAssets) external;
  function setFees(Fees calldata _fees) external;
  function setMinLiquidity(uint256 _amount) external;
  function setProfitCooldown(uint256 _cooldown) external;
  function setRedemptionRequestLocktime(uint256 _locktime) external;

  // ERC-4626
  function mint(uint256 _shares, address _receiver) external returns (uint256);
  function deposit(uint256 _amount, address _receiver) external returns (uint256 shares);
  function safeMint(
    uint256 _shares,
    uint256 _maxAmount,
    address _receiver
  ) external returns (uint256);
  function safeDeposit(
    uint256 _amount,
    uint256 _minShareAmount,
    address _receiver
  ) external returns (uint256);
  function withdraw(
    uint256 _amount,
    address _receiver,
    address _owner
  ) external returns (uint256);
  function redeem(
    uint256 _shares,
    address _receiver,
    address _owner
  ) external returns (uint256);
  function safeWithdraw(
    uint256 _amount,
    uint256 _minAmount,
    address _receiver,
    address _owner
  ) external returns (uint256);
  function safeRedeem(
    uint256 _shares,
    uint256 _minAmountOut,
    address _receiver,
    address _owner
  ) external returns (uint256);

  function previewMint(uint256, address) external view returns (uint256);
  function previewMint(uint256) external view returns (uint256);
  function previewDeposit(uint256, address) external view returns (uint256);
  function previewDeposit(uint256) external view returns (uint256);
  function previewWithdraw(uint256, address) external view returns (uint256);
  function previewWithdraw(uint256) external view returns (uint256);
  function previewRedeem(uint256, address) external view returns (uint256);
  function previewRedeem(uint256) external view returns (uint256);
  function maxDeposit(address) external view returns (uint256);
  function maxMint(address) external view returns (uint256);
  function maxWithdraw(address) external view returns (uint256);
  function maxRedeem(address) external view returns (uint256);
  function totalAssets() external view returns (uint256);
  function totalAccountedAssets() external view returns (uint256);
  function totalAccountedSupply() external view returns (uint256);
  function sharePrice() external view returns (uint256);
  function assetsOf(address) external view returns (uint256);
  function convertToShares(uint256, bool) external view returns (uint256);
  function convertToShares(uint256) external view returns (uint256);
  function convertToAssets(uint256, bool) external view returns (uint256);
  function convertToAssets(uint256) external view returns (uint256);

  // accounting and fees
  function maxTotalAssets() external view returns (uint256);
  function minLiquidity() external view returns (uint256);
  function asset() external view returns (IERC20Metadata);
  function last() external view returns (Epoch memory);
  function fees() external view returns (Fees memory);
  function feeCollector() external view returns (address);
  function claimableTransactionFees() external view returns (uint256);

  // ERC-7540
  function requestDeposit(
    uint256 _amount,
    address _operator,
    address _receiver,
    bytes calldata _data
  ) external returns (uint256);
  function requestRedeem(
    uint256 _shares,
    address _operator,
    address _owner,
    bytes calldata _data
  ) external returns (uint256);
  function requestWithdraw(
    uint256 _amount,
    address _operator,
    address _owner,
    bytes calldata _data
  ) external returns (uint256);
  function cancelRedeemRequest(address _operator, address _owner) external;

  function exemptionList(address) external view returns (bool);
  function availableClaimable() external view returns (uint256);
  function totalRedemptionRequest() external view returns (uint256);
  function totalClaimableRedemption() external view returns (uint256);
  function pendingRedeemRequest(address) external view returns (uint256);
  function pendingWithdrawRequest(address) external view returns (uint256);
  function isRequestClaimable(uint256) external view returns (bool);
  function maxClaimableAsset() external view returns (uint256);
  function claimableRedeemRequest(address) external view returns (uint256);
  function totalPendingRedemptionRequest() external view returns (uint256);
  function totalpendingWithdrawRequest() external view returns (uint256);

  // Fees logic
  function collectFees() external returns (uint256);
}
