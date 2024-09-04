// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../external/Uniswap/v3/IUniswapV3Pool.sol";
import "./PriceProvider.sol";
import "./../libs/AsCast.sol";
import "./../libs/TickMaths.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title UniswapV3Provider - Uniswap V3 adapter to retrieve TWAPs
 * @author Astrolab DAO
 * @notice Retrieves, validates and converts any of Uniswap V3 pool prices (https://uniswap.org)
 */
contract UniswapV3Provider is PriceProvider {
  using AsMaths for uint256;
  using AsCast for bytes32;

  /*═══════════════════════════════════════════════════════════════╗
  ║                              TYPES                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct Params {
    address wgas;
    address weth;
    address usdc;
    uint32 twapPeriod;
    address[] assets;
    bytes32[] feeds;
    uint256[] validities;
  }

  struct PoolDesc {
    IUniswapV3Pool pool;
    address base;
    address quote;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STORAGE                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  mapping(bytes32 => PoolDesc) public descByPoolId;
  address public weth;
  address public wgas;
  address public usdc;
  uint32 public twapPeriod;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZATION                         ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor(address _accessController) PriceProvider(_accessController) {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Returns the pool ID for the given pair (quick hash)
   * @param _base Base token
   * @param _quote Quote token
   * @return Pool ID
   */
  function poolId(address _base, address _quote) public pure returns (bytes32) {
    return AsCast.hashFast(_base, _quote); // keccak256(abi.encodePacked(_base, _quote));
  }

  /**
   * @notice Returns the pool ID for the given pair (token0 / token1 can be inverted) if any
   * @param _base Base token
   * @param _quote Quote token
   * @return Pool ID
   */
  function resolvePoolId(
    address _base,
    address _quote
  ) public view returns (bytes32, bool) {
    bytes32 pid = poolId(_base, _quote);
    if (address(descByPoolId[pid].pool) != address(0)) {
      return (pid, false);
    }
    pid = poolId(_quote, _base);
    return
      (address(descByPoolId[pid].pool) != address(0))
        ? (pid, true)
        : (bytes32(0), false);
  }

  /**
   * @notice Returns the pool IDs for the given asset known pools (vs eth, usdc, gas)
   * @param _asset Asset
   * @return Pool IDs
   */
  function poolIds(
    address _asset
  ) public view returns (bytes32, bytes32, bytes32) {
    return (poolId(weth, _asset), poolId(usdc, _asset), poolId(wgas, _asset));
  }

  function hasFeed(address _asset) public view override returns (bool) {
    // make sure that we either know asset->eth or asset->usdc or asset->gas
    (bytes32 _ethPoolId, bytes32 _usdcPoolId, bytes32 _gasPoolId) = poolIds(
      _asset
    );
    return
      address(descByPoolId[_ethPoolId].pool) != address(0) ||
      address(descByPoolId[_usdcPoolId].pool) != address(0) ||
      address(descByPoolId[_gasPoolId].pool) != address(0);
  }

  /**
   * @notice Returns the squared root price of a pool token0 (base) to token1 (quote)
   * @param _pool UniswapV3 pool
   * @param _period lookback period in seconds
   * @return sqrtPriceX96 Squared root price of token0 (base) to token1 (quote)
   */
  function _poolSqrtTwapX96(
    IUniswapV3Pool _pool,
    uint32 _period // lookback period in seconds
  ) public view returns (uint160 sqrtPriceX96) {
    if (_period == 0) {
      (sqrtPriceX96, , , , , , ) = _pool.slot0();
    } else {
      uint32[] memory lookback = new uint32[](2);
      lookback[0] = _period; // start
      lookback[1] = 0; // end (now)

      (int56[] memory tickCumulatives, ) = _pool.observe(lookback);

      sqrtPriceX96 = TickMaths.getSqrtRatioAtTick(
        int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(_period)))
      );
    }
  }

  /**
   * @notice Returns the pool price of `_base` in `_quote` wei
   * @param _pool UniswapV3 pool containing `_base` and `_quote`
   * @param _base Base token
   * @return price rebased Price of `_base` in `_quote` wei
   */
  function _poolPrice(
    IUniswapV3Pool _pool,
    address _base
  ) public view returns (uint256 price) {
    uint256 sqrtTwapX96 = uint256(_poolSqrtTwapX96(_pool, twapPeriod));
    unchecked {
      price =
        _base == _pool.token0() // is the pool base same as ours or inverted
          ? ((sqrtTwapX96 / 1e6) ** 2 / (2 ** 192 / uint256(10 ** (_decimals(_base) + 12)))) // 1e6 downscaler to avoid overflow
          : (2 ** 192 * 10 ** (_decimals(_base) - 6) / ((sqrtTwapX96 / 1e3) ** 2)); // same here
    }
  }

  function _toUsdBp(address, bool) internal view override returns (uint256) {
    return 0; // should not be called since USD is unknown
  }

  /**
   * @notice Converts `amount` of `_base` to `_quote` wei via `_proxy`
   * @param _base Base token
   * @param _amount Amount of `_base` to convert
   * @param _proxy Proxy address
   * @param _quote Quote token
   * @return Amount of `_quote` equivalent to `_amount` of `_base`
   */
  function convertTriangular(
    address _base,
    uint256 _amount,
    address _proxy,
    address _quote
  ) public view returns (uint256) {
    (bytes32 pid, ) = resolvePoolId(_base, _proxy);
    if (pid != bytes32(0)) {
      (bytes32 quotePid, ) = resolvePoolId(_proxy, _quote);
      if (quotePid != bytes32(0)) {
        uint256 baseToProxyPrice = _poolPrice(
          descByPoolId[pid].pool,
          _base // base->proxy pair
        );
        uint256 proxyToQuotePrice = _poolPrice(
          descByPoolId[quotePid].pool,
          _proxy // proxy->quote pair
        );
        return
          (_amount *
            baseToProxyPrice /
              10 ** _decimals(_base)) * // denominated in proxy, downscale first to avoid overflow
            proxyToQuotePrice /
          10 ** _decimals(_proxy); // rebase to quote
      }
    }
    return 0;
  }

  /**
   * @notice Converts `_amount` of `_base` tokens to `_quote` wei
   * @param _base Base token
   * @param _quote Quote token
   * @param _amount Amount of tokens to convert
   * @return Amount of `_quote` wei equivalent to `_amount` of `_base` tokens
   */
  function convert(
    address _base,
    uint256 _amount,
    address _quote
  ) public view override returns (uint256) {
    if (_quote == _base) return _amount;

    unchecked {
      (bytes32 pid, ) = resolvePoolId(_base, _quote);
      if (pid != bytes32(0)) {
        return
          (_amount * _poolPrice(descByPoolId[pid].pool, _base)) /
          10 ** _decimals(_base);
      }

      address[3] memory proxies = [weth, usdc, wgas];
      for (uint8 i; i < proxies.length; i++) {
        uint256 price = convertTriangular(_base, _amount, proxies[i], _quote);
        if (price != 0) {
          return price;
        }
      }
    }
    return address(alt) != address(0) ? alt.convert(_base, _amount, _quote) : 0;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             LOGIC                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Sets the twap period
   * @param _twapPeriod New twap period in seconds
   */
  function _setTwapPeriod(uint32 _twapPeriod) internal {
    if (_twapPeriod <= 20 || _twapPeriod >= 1 days) {
      // 20 secs minimum, 1 day maximum
      revert Errors.InvalidData();
    }
    twapPeriod = _twapPeriod;
  }

  /**
   * @notice Sets the twap period
   * @param _twapPeriod New twap period in seconds
   */
  function setTwapPeriod(uint32 _twapPeriod) external onlyAdmin {
    _setTwapPeriod(_twapPeriod);
  }

  /**
   * @notice Updates the UniswapV3 feeds
   * @param _params Encoded UniswapV3 specific parameters
   */
  function _update(bytes calldata _params) internal override {
    Params memory params = abi.decode(_params, (Params));
    if (
      params.weth == address(0) ||
      params.wgas == address(0) ||
      params.usdc == address(0)
    ) {
      revert Errors.AddressZero();
    }
    weth = params.weth;
    wgas = params.wgas;
    usdc = params.usdc;
    _decimalsByAsset[weth] = IERC20Metadata(weth).decimals();
    _decimalsByAsset[wgas] = IERC20Metadata(wgas).decimals();
    _decimalsByAsset[usdc] = IERC20Metadata(usdc).decimals();
    _setTwapPeriod(params.twapPeriod);
    _setFeeds(params.assets, params.feeds, params.validities);
  }

  /**
   * @notice Registers the price feed for a given `_asset` asset
   * @param _asset Feed base token address
   * @param _feed Liquidity pool address
   * @param _validity Feed validity period in seconds
   */
  function _setFeed(
    address _asset,
    bytes32 _feed,
    uint256 _validity
  ) internal override {
    IUniswapV3Pool pool = IUniswapV3Pool(_feed.toAddress());
    (address base, address quote) = (pool.token0(), pool.token1());
    PoolDesc memory desc = PoolDesc({pool: pool, base: base, quote: quote});
    _decimalsByAsset[base] = IERC20Metadata(base).decimals();
    _decimalsByAsset[quote] = IERC20Metadata(quote).decimals();
    validityByAsset[_asset] = _validity;
    descByPoolId[poolId(base, quote)] = desc;
    // descByPoolId[poolId(quote, base)] = desc;
  }
}
