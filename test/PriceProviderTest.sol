// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {
  StrategyParams,
  Fees,
  CoreAddresses,
  Erc20Metadata,
  Errors,
  Roles
} from "../src/abstract/AsTypes.sol";
import {AsArrays} from "../src/libs/AsArrays.sol";
import {AccessController} from "../src/abstract/AccessController.sol";
import {ChainlinkProvider} from "../src/abstract/ChainlinkProvider.sol";
import {ERC20} from "../src/abstract/ERC20.sol";

contract PriceProviderTest is Test {
  using AsArrays for address;
  using AsArrays for uint16;
  using AsArrays for uint256;
  using AsArrays for uint256[8];

  address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // asset/input[0]
  address USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // input[1]
  address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // wgas
  address WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // wgas

  address ETH_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
  address BTC_FEED = 0x6ce185860a4963106506C203335A2910413708e9;
  address USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
  address USDCe_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

  AccessController accessController;
  ChainlinkProvider oracle;
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
    vm.startPrank(admin);
    uint256 validity = 1 days;
    // deploy strategy and agent back-end
    accessController = new AccessController();
    oracle = new ChainlinkProvider(address(accessController));
    oracle.update(
      abi.encode(
        ChainlinkProvider.Params({
          assets: AsArrays.toArray(USDC, WETH, WBTC), // [USDC]
          feeds: AsArrays.toBytes32Array(USDC_FEED, ETH_FEED, BTC_FEED),
          validities: AsArrays.toArray(validity, validity, validity) // Chainlink default validity
        })
      )
    );
    vm.stopPrank();
  }

  function getPrices() public {
    console.log("USDC/USD (bps) %e", oracle.toUsd(USDC));
    console.log("WETH/USD (bps) %e", oracle.toUsd(WETH));
    console.log("WBTC/USD (bps) %e", oracle.toUsd(WBTC));

    console.log("USD/USDC (bps) %e", oracle.fromUsd(USDC, 1));
    console.log("USD/WETH (bps) %e", oracle.fromUsd(WETH, 3800));
    console.log("USD/WBTC (bps) %e", oracle.fromUsd(WBTC, 68000));

    console.log("WBTC/WETH (bps) %e", oracle.exchangeRate(WBTC, WETH));
    console.log("WETH/WBTC (bps) %e", oracle.exchangeRate(WETH, WBTC));
  }

  function testAll() public {
    getPrices();
  }
}
