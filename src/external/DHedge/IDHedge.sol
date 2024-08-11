// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Uniswap/v2/IUniswapV2Router.sol";

library EasySwapperStructs {
  struct WithdrawProps {
    IUniswapV2Router swapRouter;
    SynthetixProps synthetixProps;
    address weth;
    address nativeAssetWrapper;
  }

  struct SynthetixProps {
    address snxProxy;
    address swapSUSDToAsset; // usdc or dai
    address sUSDProxy;
  }
}

interface IDhedgeEasySwapper {
  event Deposit(
    address pool,
    address depositor,
    address depositAsset,
    uint256 amount,
    address poolDepositAsset,
    uint256 liquidityMinted
  );

  function feeSink() external view returns (address payable);

  function feeNumerator() external view returns (uint256);

  function feeDenominator() external view returns (uint256);

  function allowedPools(address) external view returns (bool);

  function managerFeeBypass(address) external view returns (bool);

  function withdrawProps()
    external
    view
    returns (EasySwapperStructs.WithdrawProps memory);

  function initialize(
    address payable _feeSink,
    uint256 _feeNumerator,
    uint256 _feeDenominator
  ) external;

  function setWithdrawProps(EasySwapperStructs.WithdrawProps calldata _withdrawProps)
    external;

  function setSwapRouter(IUniswapV2Router _swapRouter) external;

  function setPoolAllowed(address pool, bool allowed) external;

  function setFee(uint256 numerator, uint256 denominator) external;

  function setFeeSink(address payable sink) external;

  function setManagerFeeBypass(address manager, bool bypass) external;

  function deposit(
    address pool,
    address depositAsset,
    uint256 amount,
    address poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external returns (uint256 liquidityMinted);

  function depositWithCustomCooldown(
    address pool,
    address depositAsset,
    uint256 amount,
    address poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external returns (uint256 liquidityMinted);

  function depositNative(
    address pool,
    address poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external payable returns (uint256 liquidityMinted);

  function depositNativeWithCustomCooldown(
    address pool,
    address poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external payable returns (uint256 liquidityMinted);

  function setDepositFeeBypass(address pool, bool bypass) external;

  function getFee(address pool, uint256 amount) external view returns (uint256 fee);

  function depositQuote(
    address pool,
    address depositAsset,
    uint256 amount,
    address poolDepositAsset,
    bool customCooldown
  ) external view returns (uint256 expectedLiquidityMinted);

  function withdraw(
    address pool,
    uint256 fundTokenAmount,
    address withdrawalAsset,
    uint256 expectedAmountOut
  ) external;

  function withdrawSUSD(
    address pool,
    uint256 fundTokenAmount,
    address intermediateAsset,
    uint256 expectedAmountSUSD
  ) external;

  function withdrawIntermediate(
    address pool,
    uint256 fundTokenAmount,
    address intermediateAsset,
    address finalAsset,
    uint256 expectedAmountFinalAsset
  ) external;
}

interface IDHedgePool {
  function symbol() external view returns (string memory);

  function decimals() external view returns (uint256);

  function transfer(address dst, uint256 amount) external returns (bool);

  function transferFrom(address src, address dst, uint256 amount) external returns (bool);

  function approve(address spender, uint256 amount) external returns (bool);

  function allowance(address owner, address spender) external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);

  function balanceOfUnderlying(address owner) external returns (uint256);

  function factory() external view returns (address);

  function poolManagerLogic() external view returns (address);

  function setPoolManagerLogic(address _poolManagerLogic) external returns (bool);

  function availableManagerFee() external view returns (uint256 fee);

  function tokenPrice() external view returns (uint256 price);

  function tokenPriceWithoutManagerFee() external view returns (uint256 price);

  function mintManagerFee() external;

  function deposit(
    address _asset,
    uint256 _amount
  ) external returns (uint256 liquidityMinted);

  function depositFor(
    address _recipient,
    address _asset,
    uint256 _amount
  ) external returns (uint256 liquidityMinted);

  function depositForWithCustomCooldown(
    address _recipient,
    address _asset,
    uint256 _amount,
    uint256 _cooldown
  ) external returns (uint256 liquidityMinted);

  function withdraw(uint256 _fundTokenAmount) external;

  function getExitRemainingCooldown(address sender)
    external
    view
    returns (uint256 remaining);
}
