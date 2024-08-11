// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapV3Router {
  struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }

  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  struct ExactOutputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountOut;
    uint256 amountInMaximum;
  }

  struct ExactOutputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 deadline;
    uint256 amountOut;
    uint256 amountInMaximum;
    uint160 sqrtPriceLimitX96;
  }

  function WETH9() external view returns (address);

  function exactInput(
    ExactInputParams calldata params
  ) external payable returns (uint256 amountOut);

  function exactInputSingle(
    ExactInputSingleParams calldata params
  ) external payable returns (uint256 amountOut);

  function exactOutput(
    ExactOutputParams calldata params
  ) external payable returns (uint256 amountIn);

  function exactOutputSingle(
    ExactOutputSingleParams calldata params
  ) external payable returns (uint256 amountIn);

  function factory() external view returns (address);

  function multicall(
    bytes[] calldata data
  ) external payable returns (bytes[] memory results);

  function refundETH() external payable;

  function selfPermit(
    address token,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external payable;

  function selfPermitAllowed(
    address token,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external payable;

  function selfPermitAllowedIfNecessary(
    address token,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external payable;

  function selfPermitIfNecessary(
    address token,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external payable;

  function sweepToken(
    address token,
    uint256 amountMinimum,
    address recipient
  ) external payable;

  function sweepTokenWithFee(
    address token,
    uint256 amountMinimum,
    address recipient,
    uint256 feeBips,
    address feeRecipient
  ) external payable;

  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata _data
  ) external;

  function unwrapWETH9(
    uint256 amountMinimum,
    address recipient
  ) external payable;

  function unwrapWETH9WithFee(
    uint256 amountMinimum,
    address recipient,
    uint256 feeBips,
    address feeRecipient
  ) external payable;

  receive() external payable;
}
