// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// The Router contract has Multicall and SelfPermit enabled.
interface IRouter {
  struct TokenInput {
    address token;
    uint256 amount;
  }

  struct SwapStep {
    address pool; // The pool of the step
    bytes data; // The data to execute swap with the pool
    address callback;
    bytes callbackData;
  }

  struct SwapPath {
    SwapStep[] steps; // Steps of the path
    address tokenIn; // The input token of the path
    uint256 amountIn; // The input token amount of the path
  }

  struct SplitPermitParams {
    address token;
    uint256 approveAmount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  struct ArrayPermitParams {
    uint256 approveAmount;
    uint256 deadline;
    bytes signature;
  }

  // Returns the vault address
  function vault() external view returns (address);

  // Returns the wETH address
  function wETH() external view returns (address);

  // Adds some liquidity (supports unbalanced mint).
  // Alternatively, use `addLiquidity2` with the same params to register the position,
  // to make sure it can be indexed by the interface
  function addLiquidity(
    address pool,
    TokenInput[] calldata inputs,
    bytes calldata data,
    uint256 _minLiquidity,
    address callback,
    bytes calldata callbackData
  ) external payable returns (uint256 liquidity);

  // Adds some liquidity (supports unbalanced mint).
  // Alternatively, use `addLiquidity2` with the same params to register the position,
  // to make sure it can be indexed by the interface
  function addLiquidity2(
    address pool,
    TokenInput[] calldata inputs,
    bytes calldata data,
    uint256 _minLiquidity,
    address callback,
    bytes calldata callbackData
  ) external payable returns (uint256 liquidity);

  // Adds some liquidity with permit (supports unbalanced mint).
  // Alternatively, use `addLiquidityWithPermit` with the same params to register the position,
  // to make sure it can be indexed by the interface
  function addLiquidityWithPermit(
    address pool,
    TokenInput[] calldata inputs,
    bytes calldata data,
    uint256 _minLiquidity,
    address callback,
    bytes calldata callbackData,
    SplitPermitParams[] memory permits
  ) external payable returns (uint256 liquidity);

  // Burns some liquidity (balanced)
  function burnLiquidity(
    address pool,
    uint256 liquidity,
    bytes calldata data,
    uint256[] calldata minAmounts,
    address callback,
    bytes calldata callbackData
  ) external returns (IPool.TokenAmount[] memory amounts);

  // Burns some liquidity with permit (balanced)
  function burnLiquidityWithPermit(
    address pool,
    uint256 liquidity,
    bytes calldata data,
    uint256[] calldata minAmounts,
    address callback,
    bytes calldata callbackData,
    ArrayPermitParams memory permit
  ) external returns (IPool.TokenAmount[] memory amounts);

  // Burns some liquidity (single)
  function burnLiquiditySingle(
    address pool,
    uint256 liquidity,
    bytes memory data,
    uint256 minAmount,
    address callback,
    bytes memory callbackData
  ) external returns (uint256 amountOut);

  // Burns some liquidity with permit (single)
  function burnLiquiditySingleWithPermit(
    address pool,
    uint256 liquidity,
    bytes memory data,
    uint256 minAmount,
    address callback,
    bytes memory callbackData,
    ArrayPermitParams calldata permit
  ) external returns (uint256 amountOut);

  // Performs a swap
  function swap(
    SwapPath[] memory paths,
    uint256 amountOutMin,
    uint256 deadline
  ) external payable returns (IPool.TokenAmount memory amountOut);

  function swapWithPermit(
    SwapPath[] memory paths,
    uint256 amountOutMin,
    uint256 deadline,
    SplitPermitParams calldata permit
  ) external payable returns (IPool.TokenAmount memory amountOut);

  /// @notice Wrapper function to allow pool deployment to be batched
  function createPool(
    address factory,
    bytes calldata data
  ) external payable returns (address);
}

// The standard interface.
interface IPool {
  struct TokenAmount {
    address token;
    uint256 amount;
  }

  /// @dev Returns the address of pool master
  function master() external view returns (address);

  /// @dev Returns the vault
  function vault() external view returns (address);

  // [Deprecated] This is the interface before the dynamic fees update
  /// @dev Returns the pool type
  function poolType() external view returns (uint16);

  /// @dev Returns the assets of the pool
  function getAssets() external view returns (address[] memory assets);

  // [Deprecated] This is the interface before the dynamic fees update
  /// @dev Returns the swap fee of the pool
  // This function will forward calls to the pool master
  // function getSwapFee() external view returns (uint24 swapFee);

  // [Recommended] This is the latest interface
  /// @dev Returns the swap fee of the pool
  /// This function will forward calls to the pool master
  function getSwapFee(
    address sender,
    address tokenIn,
    address tokenOut,
    bytes calldata data
  ) external view returns (uint24 swapFee);

  /// @dev Returns the protocol fee of the pool
  function getProtocolFee() external view returns (uint24 protocolFee);

  // [Deprecated] The old interface for Era testnet
  /// @dev Mints liquidity
  // The data for Classic and Stable Pool is as follows
  // `address _to = abi.decode(_data, (address));`
  //function mint(bytes calldata data) external returns (uint liquidity);

  /// @dev Mints liquidity
  function mint(
    bytes calldata data,
    address sender,
    address callback,
    bytes calldata callbackData
  ) external returns (uint256 liquidity);

  // [Deprecated] The old interface for Era testnet
  /// @dev Burns liquidity
  // The data for Classic and Stable Pool is as follows
  // `(address _to, uint8 _withdrawMode) = abi.decode(_data, (address, uint8));`
  //function burn(bytes calldata data) external returns (TokenAmount[] memory amounts);

  /// @dev Burns liquidity
  function burn(
    bytes calldata data,
    address sender,
    address callback,
    bytes calldata callbackData
  ) external returns (TokenAmount[] memory tokenAmounts);

  // [Deprecated] The old interface for Era testnet
  /// @dev Burns liquidity with single output token
  // The data for Classic and Stable Pool is as follows
  // `(address _tokenOut, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));`
  //function burnSingle(bytes calldata data) external returns (uint amountOut);

  /// @dev Burns liquidity with single output token
  function burnSingle(
    bytes calldata data,
    address sender,
    address callback,
    bytes calldata callbackData
  ) external returns (TokenAmount memory tokenAmount);

  // [Deprecated] The old interface for Era testnet
  /// @dev Swaps between tokens
  // The data for Classic and Stable Pool is as follows
  // `(address _tokenIn, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));`
  //function swap(bytes calldata data) external returns (uint amountOut);

  /// @dev Swaps between tokens
  function swap(
    bytes calldata data,
    address sender,
    address callback,
    bytes calldata callbackData
  ) external returns (TokenAmount memory tokenAmount);
}

// The base interface, with two tokens and Liquidity Pool (LP) token.
interface IBasePool is IPool, IERC20 {
  function token0() external view returns (address);
  function token1() external view returns (address);

  function reserve0() external view returns (uint256);
  function reserve1() external view returns (uint256);
  function invariantLast() external view returns (uint256);

  function getReserves() external view returns (uint256, uint256);

  // [Deprecated] The old interface for Era testnet
  //function getAmountOut(address tokenIn, uint amountIn) external view returns (uint amountOut);
  //function getAmountIn(address tokenOut, uint amountOut) external view returns (uint amountIn);

  function getAmountOut(
    address tokenIn,
    uint256 amountIn,
    address sender
  ) external view returns (uint256 amountOut);
  function getAmountIn(
    address tokenOut,
    uint256 amountOut,
    address sender
  ) external view returns (uint256 amountIn);

  event Mint(
    address indexed sender,
    uint256 amount0,
    uint256 amount1,
    uint256 liquidity,
    address indexed to
  );

  event Burn(
    address indexed sender,
    uint256 amount0,
    uint256 amount1,
    uint256 liquidity,
    address indexed to
  );

  event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
  );

  event Sync(uint256 reserve0, uint256 reserve1);
}

// The Classic Pool.
interface IClassicPool is IBasePool {}

// The Stable Pool with the additional multiplier for pool tokens.
interface IStablePool is IBasePool {
  function token0PrecisionMultiplier() external view returns (uint256);
  function token1PrecisionMultiplier() external view returns (uint256);
}
