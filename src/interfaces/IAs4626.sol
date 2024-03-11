// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import "../abstract/AsTypes.sol";
import "./IAsManageable.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";


interface IAs4626 is IERC20Metadata, IAsManageable {
  // Custom types
  struct As4626StorageExt {
    uint16 maxSlippageBps;
  }

  // Errors
  error AmountTooHigh(uint256 amount);
  error AmountTooLow(uint256 amount);
  error AddressZero();
  error InvalidData();

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
    uint256 feesAmount,
    uint256 sharesMinted
  );

  // View functions
  function maxTotalAssets() external view returns (uint256);
  function minLiquidity() external view returns (uint256);
  function maxSlippageBps() external view returns (uint16);
  function asset() external view returns (address);
  function assetDecimals() external view returns (uint8);
  function weiPerAsset() external view returns (uint256);
  function profitCooldown() external view returns (uint256);
  function expectedProfits() external view returns (uint256);
  function fees() external view returns (Fees memory);
  function feeCollector() external view returns (address);
  function claimableAssetFees() external view returns (uint256);
  function exemptionList(address) external view returns (bool);
  function last() external view returns (Epoch memory);
  function totalLent() external view returns (uint256);
  function totalAssets() external view returns (uint256);
  function totalAccountedAssets() external view returns (uint256);
  function totalAccountedSupply() external view returns (uint256);
  function sharePrice() external view returns (uint256);
  function assetsOf(address _owner) external view returns (uint256);

  // Interface functions
  function init(
    Erc20Metadata calldata _erc20Metadata,
    CoreAddresses calldata _coreAddresses,
    Fees calldata _fees
  ) external;
  function seedLiquidity(uint256 _seedDeposit, uint256 _maxTotalAssets) external;
  function availableClaimable() external view returns (uint256);
  function totalRedemptionRequest() external view returns (uint256);
  function totalClaimableRedemption() external view returns (uint256);
  function pendingRedeemRequest(address _owner) external view returns (uint256);
  function pendingAssetRequest(address _owner) external view returns (uint256);
  function isRequestClaimable(uint256 requestTimestamp) external view returns (bool);
  function maxClaimableAsset() external view returns (uint256);
  function claimableRedeemRequest(address _owner) external view returns (uint256);
  function previewMint(
    uint256 _shares,
    address _receiver
  ) external view returns (uint256);
  function previewDeposit(
    uint256 _amount,
    address _receiver
  ) external view returns (uint256);
  function previewWithdraw(
    uint256 _amount,
    address _owner
  ) external view returns (uint256);
  function previewRedeem(uint256 _shares, address _owner) external view returns (uint256);
  function maxDeposit(address) external view returns (uint256);
  function maxMint(address) external view returns (uint256);
  function maxWithdraw(address _owner) external view returns (uint256);
  function maxRedeem(address _owner) external view returns (uint256);
  function convertToShares(uint256 _amount) external view returns (uint256);
  function convertToAssets(uint256 _shares) external view returns (uint256);
  function totalPendingRedemptionRequest() external view returns (uint256);
  function totalPendingAssetRequest() external view returns (uint256);
  function setFeeCollector(address _feeCollector) external;
  function setMaxSlippageBps(uint16 _bps) external;
  function setMaxTotalAssets(uint256 _maxTotalAssets) external;
  function setFees(Fees calldata _fees) external;
  function setMinLiquidity(uint256 _amount) external;
  function setProfitCooldown(uint256 _cooldown) external;
  function setRedemptionRequestLocktime(uint256 _locktime) external;
  function mint(uint256 _shares, address _receiver) external returns (uint256);
  function deposit(uint256 _amount, address _receiver) external returns (uint256 shares);
  function safeMint(
    uint256 _shares,
    uint256 _maxAmount,
    address _receiver
  ) external returns (uint256 deposited);
  function safeDeposit(
    uint256 _amount,
    uint256 _minShareAmount,
    address _receiver
  ) external returns (uint256 shares);
  function withdraw(
    uint256 _amount,
    address _receiver,
    address _owner
  ) external returns (uint256);
  function safeWithdraw(
    uint256 _amount,
    uint256 _minAmount,
    address _receiver,
    address _owner
  ) external returns (uint256 amount);
  function redeem(
    uint256 _shares,
    address _receiver,
    address _owner
  ) external returns (uint256);
  function safeRedeem(
    uint256 _shares,
    uint256 _minAmountOut,
    address _receiver,
    address _owner
  ) external returns (uint256 amount);
  function requestDeposit(
    uint256 _amount,
    address _operator,
    address _receiver,
    bytes memory _data
  ) external returns (uint256 requestId);
  function requestRedeem(
    uint256 _shares,
    address _operator,
    address _owner,
    bytes memory _data
  ) external returns (uint256 requestId);
  function requestWithdraw(
    uint256 _amount,
    address _operator,
    address _owner,
    bytes memory _data
  ) external returns (uint256 requestId);
  function cancelRedeemRequest(address _operator, address _owner) external;
  function collectFees() external returns (uint256);
}
