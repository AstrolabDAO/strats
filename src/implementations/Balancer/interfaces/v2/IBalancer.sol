// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

// cf. https://github.com/balancer/balancer-v2-monorepo/blob/main/pkg/interfaces/contracts/pool-stable/StablePoolUserData.sol#L19
library StablePoolUserData {
  enum JoinKind {
    INIT,
    EXACT_TOKENS_IN_FOR_BPT_OUT,
    TOKEN_IN_FOR_EXACT_BPT_OUT,
    ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
  }
  enum ExitKind {
    EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
    BPT_IN_FOR_EXACT_TOKENS_OUT,
    EXACT_BPT_IN_FOR_ALL_TOKENS_OUT
  }
}

// Applies to StablePool, USDPool, StablePool V2
library LegacyStablePoolUserData {
  enum JoinKind {
    INIT,
    EXACT_TOKENS_IN_FOR_BPT_OUT,
    TOKEN_IN_FOR_EXACT_BPT_OUT
  }
  enum ExitKind {
    EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
    EXACT_BPT_IN_FOR_TOKENS_OUT,
    BPT_IN_FOR_EXACT_TOKENS_OUT
  }
}

// Applies to the first deployment of ComposableStablePool (pre-Versioning)
library ComposableStablePoolUserData {
  enum JoinKind {
    INIT,
    EXACT_TOKENS_IN_FOR_BPT_OUT,
    TOKEN_IN_FOR_EXACT_BPT_OUT
  }
  enum ExitKind {
    EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
    BPT_IN_FOR_EXACT_TOKENS_OUT
  }
}

library WeightedPoolUserData {
  enum JoinKind {
    INIT,
    EXACT_TOKENS_IN_FOR_BPT_OUT,
    TOKEN_IN_FOR_EXACT_BPT_OUT,
    ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
  }
  enum ExitKind {
    EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
    EXACT_BPT_IN_FOR_TOKENS_OUT,
    BPT_IN_FOR_EXACT_TOKENS_OUT
  }
}

enum UserBalanceOpKind {
  DEPOSIT_INTERNAL,
  WITHDRAW_INTERNAL,
  TRANSFER_INTERNAL,
  TRANSFER_EXTERNAL
}

enum PoolBalanceChangeKind {
  JOIN,
  EXIT
}

enum SwapKind {
  GIVEN_IN,
  GIVEN_OUT
}

enum PoolBalanceOpKind {
  WITHDRAW,
  DEPOSIT,
  UPDATE
}

enum PoolSpecialization {
  GENERAL,
  MINIMAL_SWAP_INFO,
  TWO_TOKEN
}

struct SwapRequest {
  SwapKind kind;
  address tokenIn;
  address tokenOut;
  uint256 amount;
  // Misc data
  bytes32 poolId;
  uint256 lastChangeBlock;
  address from;
  address to;
  bytes userData;
}

struct UserBalanceOp {
  UserBalanceOpKind kind;
  address asset;
  uint256 amount;
  address sender;
  address payable recipient;
}

struct JoinPoolRequest {
  address[] assets;
  uint256[] maxAmountsIn;
  bytes userData;
  bool fromInternalBalance;
}

struct ExitPoolRequest {
  address[] assets;
  uint256[] minAmountsOut;
  bytes userData;
  bool toInternalBalance;
}

struct SingleSwap {
  bytes32 poolId;
  SwapKind kind;
  address assetIn;
  address assetOut;
  uint256 amount;
  bytes userData;
}

struct BatchSwapStep {
  bytes32 poolId;
  uint256 assetInIndex;
  uint256 assetOutIndex;
  uint256 amount;
  bytes userData;
}

struct FundManagement {
  address sender;
  bool fromInternalBalance;
  address payable recipient;
  bool toInternalBalance;
}

struct PoolBalanceOp {
  PoolBalanceOpKind kind;
  bytes32 poolId;
  address token;
  uint256 amount;
}

// IPoolBalances+IPoolRegistry+IPoolTokens+ISwap
interface IBalancerVault {
  function getAuthorizer() external view returns (address);

  function setAuthorizer(address newAuthorizer) external;

  event AuthorizerChanged(address indexed newAuthorizer);

  function hasApprovedRelayer(address user, address relayer) external view returns (bool);

  function setRelayerApproval(address sender, address relayer, bool approved) external;

  event RelayerApprovalChanged(
    address indexed relayer, address indexed sender, bool approved
  );

  function getInternalBalance(
    address user,
    address[] memory tokens
  ) external view returns (uint256[] memory);

  function manageUserBalance(UserBalanceOp[] memory ops) external payable;

  event InternalBalanceChanged(address indexed user, address indexed token, int256 delta);
  event ExternalBalanceTransfer(
    address indexed token, address indexed sender, address recipient, uint256 amount
  );

  function registerPool(PoolSpecialization specialization) external returns (bytes32);

  event PoolRegistered(
    bytes32 indexed poolId, address indexed poolAddress, PoolSpecialization specialization
  );

  function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);

  function registerTokens(
    bytes32 poolId,
    address[] memory tokens,
    address[] memory assetManagers
  ) external;

  event TokensRegistered(
    bytes32 indexed poolId, address[] tokens, address[] assetManagers
  );

  function deregisterTokens(bytes32 poolId, address[] memory tokens) external;

  event TokensDeregistered(bytes32 indexed poolId, address[] tokens);

  function getPoolTokenInfo(
    bytes32 poolId,
    address token
  )
    external
    view
    returns (uint256 cash, uint256 managed, uint256 lastChangeBlock, address assetManager);

  function getPoolTokens(bytes32 poolId)
    external
    view
    returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

  function joinPool(
    bytes32 poolId,
    address sender,
    address recipient,
    JoinPoolRequest memory request
  ) external payable;

  function exitPool(
    bytes32 poolId,
    address sender,
    address payable recipient,
    ExitPoolRequest memory request
  ) external;

  event PoolBalanceChanged(
    bytes32 indexed poolId,
    address indexed liquidityProvider,
    address[] tokens,
    int256[] deltas,
    uint256[] protocolFeeAmounts
  );

  function swap(
    SingleSwap memory singleSwap,
    FundManagement memory funds,
    uint256 limit,
    uint256 deadline
  ) external payable returns (uint256);

  function batchSwap(
    SwapKind kind,
    BatchSwapStep[] memory swaps,
    address[] memory assets,
    FundManagement memory funds,
    int256[] memory limits,
    uint256 deadline
  ) external payable returns (int256[] memory);

  event Swap(
    bytes32 indexed poolId,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );

  function queryBatchSwap(
    SwapKind kind,
    BatchSwapStep[] memory swaps,
    address[] memory assets,
    FundManagement memory funds
  ) external returns (int256[] memory assetDeltas);

  function flashLoan(
    address recipient,
    address[] memory tokens,
    uint256[] memory amounts,
    bytes memory userData
  ) external;

  event FlashLoan(
    address indexed recipient, address indexed token, uint256 amount, uint256 feeAmount
  );

  function managePoolBalance(PoolBalanceOp[] memory ops) external;

  event PoolBalanceManaged(
    bytes32 indexed poolId,
    address indexed assetManager,
    address indexed token,
    int256 cashDelta,
    int256 managedDelta
  );

  function getProtocolFeesCollector() external view returns (address);

  function setPaused(bool paused) external;

  function WETH() external view returns (address);
}

interface IBasePool {
  function onJoinPool(
    bytes32 poolId,
    address sender,
    address recipient,
    uint256[] memory balances,
    uint256 lastChangeBlock,
    uint256 protocolSwapFeePercentage,
    bytes memory userData
  ) external returns (uint256[] memory amountsIn, uint256[] memory dueProtocolFeeAmounts);

  function onExitPool(
    bytes32 poolId,
    address sender,
    address recipient,
    uint256[] memory balances,
    uint256 lastChangeBlock,
    uint256 protocolSwapFeePercentage,
    bytes memory userData
  )
    external
    returns (uint256[] memory amountsOut, uint256[] memory dueProtocolFeeAmounts);

  function getPoolId() external view returns (bytes32);

  function getSwapFeePercentage() external view returns (uint256);

  function getScalingFactors() external view returns (uint256[] memory);

  function queryJoin(
    bytes32 poolId,
    address sender,
    address recipient,
    uint256[] memory balances,
    uint256 lastChangeBlock,
    uint256 protocolSwapFeePercentage,
    bytes memory userData
  ) external returns (uint256 bptOut, uint256[] memory amountsIn);

  function queryExit(
    bytes32 poolId,
    address sender,
    address recipient,
    uint256[] memory balances,
    uint256 lastChangeBlock,
    uint256 protocolSwapFeePercentage,
    bytes memory userData
  ) external returns (uint256 bptIn, uint256[] memory amountsOut);
}

interface IGeneralPool is IBasePool {
  function onSwap(
    SwapRequest memory swapRequest,
    uint256[] memory balances,
    uint256 indexIn,
    uint256 indexOut
  ) external returns (uint256 amount);
}

interface ILinearPool is IBasePool {
  function getMainToken() external view returns (address);
  function getWrappedToken() external view returns (address);
  function getBptIndex() external view returns (uint256);
  function getMainIndex() external view returns (uint256);
  function getWrappedIndex() external view returns (uint256);
  function getTargets() external view returns (uint256 lowerTarget, uint256 upperTarget);
  function setTargets(uint256 newLowerTarget, uint256 newUpperTarget) external;
  function setSwapFeePercentage(uint256 swapFeePercentage) external;
}

interface IBalancerManagedPool is IBasePool {
  event GradualSwapFeeUpdateScheduled(
    uint256 startTime,
    uint256 endTime,
    uint256 startSwapFeePercentage,
    uint256 endSwapFeePercentage
  );
  event GradualWeightUpdateScheduled(
    uint256 startTime, uint256 endTime, uint256[] startWeights, uint256[] endWeights
  );
  event SwapEnabledSet(bool swapEnabled);
  event JoinExitEnabledSet(bool joinExitEnabled);
  event MustAllowlistLPsSet(bool mustAllowlistLPs);
  event AllowlistAddressAdded(address indexed member);
  event AllowlistAddressRemoved(address indexed member);
  event ManagementAumFeePercentageChanged(uint256 managementAumFeePercentage);
  event ManagementAumFeeCollected(uint256 bptAmount);
  event CircuitBreakerSet(
    address indexed token,
    uint256 bptPrice,
    uint256 lowerBoundPercentage,
    uint256 upperBoundPercentage
  );
  event TokenAdded(address indexed token, uint256 normalizedWeight);
  event TokenRemoved(address indexed token);

  function getActualSupply() external view returns (uint256);
  function updateSwapFeeGradually(
    uint256 startTime,
    uint256 endTime,
    uint256 startSwapFeePercentage,
    uint256 endSwapFeePercentage
  ) external;

  function getGradualSwapFeeUpdateParams()
    external
    view
    returns (
      uint256 startTime,
      uint256 endTime,
      uint256 startSwapFeePercentage,
      uint256 endSwapFeePercentage
    );

  function updateWeightsGradually(
    uint256 startTime,
    uint256 endTime,
    address[] memory tokens,
    uint256[] memory endWeights
  ) external;

  function getNormalizedWeights() external view returns (uint256[] memory);

  function getGradualWeightUpdateParams()
    external
    view
    returns (
      uint256 startTime,
      uint256 endTime,
      uint256[] memory startWeights,
      uint256[] memory endWeights
    );
  function setJoinExitEnabled(bool joinExitEnabled) external;
  function getJoinExitEnabled() external view returns (bool);
  function setSwapEnabled(bool swapEnabled) external;
  function getSwapEnabled() external view returns (bool);
  function setMustAllowlistLPs(bool mustAllowlistLPs) external;
  function addAllowedAddress(address member) external;
  function removeAllowedAddress(address member) external;
  function getMustAllowlistLPs() external view returns (bool);
  function isAddressOnAllowlist(address member) external view returns (bool);
  function collectAumManagementFees() external returns (uint256);
  function setManagementAumFeePercentage(uint256 managementAumFeePercentage)
    external
    returns (uint256);
  function getManagementAumFeeParams()
    external
    view
    returns (uint256 aumFeePercentage, uint256 lastCollectionTimestamp);
  function setCircuitBreakers(
    address[] memory tokens,
    uint256[] memory bptPrices,
    uint256[] memory lowerBoundPercentages,
    uint256[] memory upperBoundPercentages
  ) external;
  function getCircuitBreakerState(address token)
    external
    view
    returns (
      uint256 bptPrice,
      uint256 referenceWeight,
      uint256 lowerBound,
      uint256 upperBound,
      uint256 lowerBptPriceBound,
      uint256 upperBptPriceBound
    );
  function addToken(
    address tokenToAdd,
    address assetManager,
    uint256 tokenToAddNormalizedWeight,
    uint256 mintAmount,
    address recipient
  ) external;
  function removeToken(
    address tokenToRemove,
    uint256 burnAmount,
    address sender
  ) external;
}
