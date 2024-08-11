// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IUniswapV2Router {
  function getAmountsOut(
    uint256 amountIn,
    address[] memory path
  ) external view returns (uint256[] memory amounts);

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);
  // ...
}
