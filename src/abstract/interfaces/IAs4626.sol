// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../AsTypes.sol";

interface IAs4626 {

    // Errors
    error LiquidityTooLow(uint256 assets);
    error SelfMintNotAllowed();
    error FeeError();
    error Unauthorized();
    error TransactionExpired();
    error AmountTooHigh(uint256 amount);
    error AmountTooLow(uint256 amount);
    error InsufficientFunds(uint256 amount);
    error WrongToken();
    error AddressZero();
    error WrongRequest(address owner, uint256 amount);

    // Events
    // ERC4626
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // ERC7540
    event DepositRequest(
        address indexed sender,
        address indexed operator,
        uint256 assets
    );
    event RedeemRequest(
        address indexed sender,
        address indexed operator,
        address indexed owner,
        uint256 assets
    );
    event DepositRequestCanceled(
        address indexed owner,
        uint256 assets
    );
    event RedeemRequestCanceled(
        address indexed owner,
        uint256 assets
    );
    // custom
    event SharePriceUpdated(uint256 shareprice, uint256 timestamp);
    event FeesCollected(
        uint256 profit,
        uint256 totalAssets,
        uint256 perfFeesAmount,
        uint256 mgmtFeesAmount,
        uint256 sharesToMint,
        address indexed receiver
    );
    event FeeCollectorUpdated(address indexed feeCollector);
    event FeesUpdated(uint256 perf, uint256 mgmt, uint256 entry, uint256 exit);
    event MaxTotalAssetsSet(uint256 maxTotalAssets);

    function underlying() external view returns (address);
    function shareDecimals() external view returns (uint8);
    function weiPerShare() external view returns (uint256);
    function MAX_FEES() external view returns (Fees memory);

    // State variable views
    function exemptionList(address _account) external view returns (bool);
    function requestByOperator(address _operator) external view returns (Erc7540Request memory);
    function requests(uint256 _index) external view returns (Erc7540Request memory);
    function totalClaimableRedemption() external view returns (uint256);
    function totalRedemptionRequest() external view returns (uint256);
    function totalDepositRequest() external view returns (uint256);
    function minLiquidity() external view returns (uint256);
    function profitCooldown() external view returns (uint256);
    function claimableUnderlyingFees() external view returns (uint256);
    function maxTotalAssets() external view returns (uint256);
    function feeCollector() external view returns (address);
    function fees() external view returns (Fees memory);
    function expectedProfits() external view returns (uint256);
    function last() external view returns (Checkpoint memory);
    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function available() external view returns (uint256);
    function invested() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function sharePrice() external view returns (uint256);
    function assetsOf(address _owner) external view returns (uint256);
    function setExemption(address _account, bool _isExempt) external;
    function init(Fees memory _fees, address _underlying, address _feeCollector) external;
    function mint(uint256 _shares, address _receiver) external returns (uint256 assets);
    function previewDeposit(uint256 _amount) external view returns (uint256 shares);
    function deposit(uint256 _amount, address _receiver) external returns (uint256 shares);
    function safeDeposit(uint256 _amount, address _receiver, uint256 _minShareAmount) external returns (uint256 shares);
    function withdraw(uint256 _amount, address _receiver, address _owner) external returns (uint256 shares);
    function safeWithdraw(uint256 _amount, uint256 _minAmount, address _receiver, address _owner) external returns (uint256 shares);
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256 assets);
    function safeRedeem(uint256 _shares, uint256 _minAmountOut, address _receiver, address _owner) external returns (uint256 assets);
    function collectFees() external;
    function pause() external;
    function unpause() external;
    function setFeeCollector(address _feeCollector) external;
    function setMaxTotalAssets(uint256 _maxTotalAssets) external;
    function seedLiquidity(uint256 _seedDeposit, uint256 _maxTotalAssets) external;
    function setFees(Fees memory _fees) external;
    function setMinLiquidity(uint256 _minLiquidity) external;
    function setProfitCooldown(uint256 _profitCooldown) external;
    function convertToShares(uint256 _assets) external view returns (uint256);
    function convertToAssets(uint256 _shares) external view returns (uint256);
    function previewMint(uint256 _shares) external view returns (uint256);
    function previewWithdraw(uint256 _assets) external view returns (uint256);
    function previewRedeem(uint256 _shares) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(address _owner) external view returns (uint256);
    function maxRedeem(address _owner) external view returns (uint256);
    function requestDeposit(uint256 assets, address operator) external;
    function requestRedeem(uint256 shares, address operator, address owner) external;
    function cancelDepositRequest(address operator, address owner) external;
    function cancelRedeemRequest(address operator, address owner) external;
    function pendingDepositRequest(address operator) external view returns (uint256);
    function pendingRedeemRequest(address operator) external view returns (uint256);
}
