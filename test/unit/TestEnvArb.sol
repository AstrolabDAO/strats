// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {
  StrategyParams,
  Fees,
  CoreAddresses,
  Erc20Metadata,
  Errors,
  Roles
} from "../../src/abstract/AsTypes.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AsMaths} from "../../src/libs/AsMaths.sol";
import {ERC20} from "../../src/abstract/ERC20.sol";
import {ChainlinkProvider} from "../../src/abstract/ChainlinkProvider.sol";
import {TestEnv} from "./TestEnv.sol";

abstract contract TestEnvArb is TestEnv {
  using AsArrays for address;
  using AsArrays for uint16;
  using AsArrays for uint256;
  using AsArrays for uint256[8];

  uint256 internal constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;

  address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // asset/input[0]
  address USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // input[1]
  address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // wgas
  address WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

  address ETH_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
  address USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
  address USDCe_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
  address BTC_FEED = 0x6ce185860a4963106506C203335A2910413708e9;
  address WBTC_FEED = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;

  address swapper = 0x503301Eb7cfC64162b5ce95cc67B84Fbf6dF5255;
  address rich = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

  ERC20 usdc = ERC20(USDC);
  ERC20 weth = ERC20(WETH);
  ERC20 wbtc = ERC20(WBTC);

  constructor(bool _refuel, bool _fund) TestEnv(_refuel) {
    // create arbitrum fork and deal test tokens
    vm.createSelectFork(vm.rpcUrl(vm.envString("arbitrum_private_rpc")));
    if (_fund) {
      fundAll(rich, USDC, 100_000e6);
      fundAll(rich, USDCe, 100_000e6);
      fundAll(rich, WETH, 100e18);
      fundAll(rich, WBTC, 10e8);
    }
  }

  function initOracle() public override {
    vm.prank(admin);
    oracle.update(
      abi.encode(
        ChainlinkProvider.Params({
          assets: USDC.toArray(), // [USDC]
          feeds: USDC_FEED.toBytes32Array(), // Chainlink USDC
          validities: uint256(3600 * 24).toArray() // Chainlink quote validity
        })
      )
    );
  }

  function init(Fees memory _fees) public virtual override {
    // initialize the strategy
    // ERC20 metadata
    Erc20Metadata memory erc20Meta = Erc20Metadata({
      name: "Astrolab Primitive Dummy USD",
      symbol: "apDUMMY-USD",
      decimals: 12
    });
    // startegy core addresses
    CoreAddresses memory coreAddresses = CoreAddresses({
      wgas: WETH,
      asset: USDC,
      feeCollector: manager,
      swapper: swapper,
      agent: agent,
      oracle: address(oracle)
    });

    // aggregated strategy base parameters
    StrategyParams memory params = StrategyParams({
      erc20Metadata: erc20Meta,
      coreAddresses: coreAddresses,
      fees: _fees,
      inputs: USDC.toArray(), // [USDC]
      inputWeights: uint16(100_00).toArray16(), // 100% weight on USDC
      lpTokens: USDCe.toArray(),
      rewardTokens: USDCe.toArray(),
      extension: new bytes(0)
    });

    // initialize (admin only)
    vm.prank(admin);
    strat.init(params);
  }
}
