// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import {
  StrategyParams,
  Fees,
  CoreAddresses,
  Erc20Metadata,
  Errors,
  Roles
} from "../../src/abstract/AsTypes.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AccessController} from "../../src/abstract/AccessController.sol";
import {ChainlinkProvider} from "../../src/abstract/ChainlinkProvider.sol";
import {PythProvider} from "../../src/abstract/PythProvider.sol";
import {ERC20} from "../../src/abstract/ERC20.sol";

contract PriceProviderTest is Test {
  using AsArrays for address;
  using AsArrays for uint16;
  using AsArrays for uint256;
  using AsArrays for uint256[8];

  address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // asset/input[0]
  address USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // input[1]
  address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // wgas
  address WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // wgas

  address CHAINLINK_ETH_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
  address CHAINLINK_BTC_FEED = 0x6ce185860a4963106506C203335A2910413708e9;
  address CHAINLINK_USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
  address CHAINLINK_USDCe_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

  address PYTH = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
  bytes32 PYTH_ETH_FEED = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
  bytes32 PYTH_USDC_FEED = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
  bytes32 PYTH_BTC_FEED = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

  AccessController accessController;
  ChainlinkProvider chainlink;
  PythProvider pyth;
  ERC20 weth = ERC20(WETH);

  address admin = vm.addr(1);

  constructor() Test() {
    // create arbitrum fork and deal test tokens
    vm.createSelectFork(vm.rpcUrl(vm.envString("arbitrum_private_rpc")));
    vm.deal(admin, 1e4 ether);
    deploy();
  }

  function setUp() public {}

  function deploy() public {
    uint256 validity = 1 days;
    // deploy strategy and agent back-end
    accessController = new AccessController(admin);
    chainlink = new ChainlinkProvider(address(accessController));
    pyth = new PythProvider(address(accessController));

    vm.prank(admin);
    chainlink.update(
      abi.encode(
        ChainlinkProvider.Params({
          assets: AsArrays.toArray(USDC, WETH, WBTC),
          feeds: AsArrays.toBytes32Array(CHAINLINK_USDC_FEED, CHAINLINK_ETH_FEED, CHAINLINK_BTC_FEED),
          validities: AsArrays.toArray(validity, validity, validity) // Chainlink default validity
        })
      )
    );

    vm.prank(admin);
    pyth.update(
      abi.encode(
        PythProvider.Params({
          pyth: PYTH,
          assets: AsArrays.toArray(USDC, WETH, WBTC),
          feeds: AsArrays.toArray(PYTH_USDC_FEED, PYTH_ETH_FEED, PYTH_BTC_FEED),
          validities: AsArrays.toArray(validity, validity, validity)
        })
      )
    );
  }

  function getPrices() public {
    // vm.warp(block.timestamp - 5 minutes);
    console.log("USDC/USD (e18) %e vs %e", chainlink.toUsd(USDC), pyth.toUsd(USDC)); // usd 1e18 wei per usdc
    console.log("WETH/USD (e18) %e vs %e", chainlink.toUsd(WETH), pyth.toUsd(WETH)); // usd 1e18 wei per weth
    console.log("WBTC/USD (e18) %e vs %e", chainlink.toUsd(WBTC), pyth.toUsd(WBTC)); // usd 1e18 wei per wbtc

    console.log("1000 USDC in USD (e18) %e vs %e", chainlink.toUsd(USDC, 1000e18), pyth.toUsd(USDC, 1000e18));
    console.log("100 WETH in USD (e18) %e vs %e", chainlink.toUsd(WETH, 100e18), pyth.toUsd(WETH, 100e18));
    console.log("10 WBTC in USD (e18) %e vs %e", chainlink.toUsd(WBTC, 10e18), pyth.toUsd(WBTC, 10e18));

    console.log("USD/USDC (e6) %e vs %e", chainlink.fromUsd(USDC), pyth.fromUsd(USDC)); // weth wei per usd
    console.log("USD/WETH (e18) %e vs %e", chainlink.fromUsd(WETH), pyth.fromUsd(WETH)); // weth wei per usd
    console.log("USD/WBTC (e8) %e vs %e", chainlink.fromUsd(WBTC), pyth.fromUsd(WBTC)); // wbtc wei per usd

    console.log("1000 USD in USDC (e6) %e vs %e", chainlink.fromUsd(USDC, 1000e18), pyth.fromUsd(USDC, 1000e18)); // weth wei per usd
    console.log("3800 USD in WETH (e18) %e vs %e", chainlink.fromUsd(WETH, 3800e18), pyth.fromUsd(WETH, 3800e18)); // weth wei per usd
    console.log("68000 USD in WBTC (e8) %e vs %e", chainlink.fromUsd(WBTC, 68000e18), pyth.fromUsd(WBTC, 68000e18)); // wbtc wei per usd

    console.log("WBTC/WETH (1 BTC in ETH, e18) %e vs %e", chainlink.exchangeRate(WBTC, WETH), pyth.exchangeRate(WBTC, WETH)); // weth wei per wbtc
    console.log("WETH/WBTC (1 ETH in BTC, e10) %e vs %e", chainlink.exchangeRate(WETH, WBTC), pyth.exchangeRate(WETH, WBTC)); // wbtc wei per weth
  }

  function testAll() public {
    getPrices();
  }
}
