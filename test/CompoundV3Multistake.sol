// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {
  StrategyBaseParams,
  Fees,
  CoreAddresses,
  Erc20Metadata
} from "../src/abstract/AsTypes.sol";
import {AsArrays} from "../src/libs/AsArrays.sol";
import {IStrategyV5} from "../src/interfaces/IStrategyV5.sol";
import {CompoundV3MultiStake} from
  "../src/implementations/Compound/CompoundV3MultiStake.sol";
import {StrategyV5Chainlink} from "../src/abstract/StrategyV5Chainlink.sol";
import {StrategyV5Agent} from "../src/abstract/StrategyV5Agent.sol";
import {ERC20} from "../src/abstract/ERC20.sol";

contract CompoundV3MultistakeTest is Test {
  using AsArrays for address;
  using AsArrays for uint256;

  bytes32 public constant ADMIN_ROLE = 0x00;
  bytes32 public constant KEEPER_ROLE = keccak256("KEEPER");
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER");

  address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // asset/input[0]
  address constant USDCe = 0xb9F33349db1d0711d95c1198AcbA9511B8269626; // input[1]
  address constant COMP = 0x354A6dA3fcde098F8389cad84b0182725c6C91dE; // reward[0]
  address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // wgas

  address constant ETH_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
  address constant USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
  address constant USDCe_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

  address constant cUSDC = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
  address constant cometRewards = 0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;
  address constant swapper = 0x503301Eb7cfC64162b5ce95cc67B84Fbf6dF5255;
  IStrategyV5 strat;
  address agent;
  ERC20 usdc = ERC20(USDC);
  ERC20 weth = ERC20(WETH);

  address admin = vm.addr(1);
  address manager = vm.addr(2);
  address keeper = vm.addr(3);
  address user = vm.addr(4);

  function setUp() public {

    // create arbitrum fork and deal test tokens
    vm.createSelectFork(vm.rpcUrl("https://rpc.ankr.com/arbitrum"));
    vm.deal(USDC, admin, 100e6);
    vm.deal(USDC, manager, 100e6);
    vm.deal(USDC, user, 100e6);

    // explicitely use the admin role
    vm.startPrank(admin);

    // deploy strategy and agent back-end
    agent = new StrategyV5Agent();
    strat = new CompoundV3MultiStake();

    // initialize the strategy
    // ERC20 metadata
    Erc20Metadata memory erc20Meta =
      Erc20Metadata({name: "Astrolab Primitive Compound USD", symbol: "apCOMP-USD", decimals: 12});
    // startegy core addresses
    CoreAddresses memory coreAddresses = CoreAddresses({
      wgas: WETH,
      asset: USDC,
      feeCollector: manager,
      swapper: swapper,
      agent: agent
    });
    // fees
    Fees memory mockFees = Fees({perf: 10_00, mgmt: 0, entry: 2, exit: 2, flash: 2}); // 10% perf, 0% mgmt, .02% entry, .02% exit, .02% flash
    // aggregated strategy base parameters
    StrategyBaseParams memory baseParams = StrategyBaseParams({
      erc20Metadata: erc20Meta,
      coreAddresses: coreAddresses,
      fees: mockFees,
      inputs: USDC.toArray(), // [USDC]
      inputWeights: 100_00.toArray(), // 100% weight on USDC
      rewardTokens: COMP.toArray() // [COMP]
    });
    // oracle specific (chainlink) params
    StrategyV5Chainlink.ChainlinkParams memory chainlinkParams = StrategyV5Chainlink
      .ChainlinkParams({
        assetPriceFeed: USDC_FEED.toArray(), // Chainlink USDC
        inputPriceFeeds: USDC_FEED.toArray() // Chainlink USDC
      });
    // yield protocol specific (compound) params
    CompoundV3MultiStake.Params memory compoundParams = CompoundV3MultiStake.Params({
      cTokens: cUSDC.toArray(),
      cometRewards: cometRewards
    });

    // initialize (admin only)
    strat.init(baseParams, chainlinkParams, compoundParams);

    // grant roles
    strat.grantRole(MANAGER_ROLE, manager);
    strat.grantRole(KEEPER_ROLE, keeper);

    // set vault minimum liquidity
    strat.setMinLiquidity(10e6);

    // seed liquidity/unpause
    vm.startPrank(manager);
    usdc.approve(address(strat), 10e6);
    strat.seedLiquidity(10e6, 1e12); // deposit 10 USDC (minLiquidity), set maxTVL to 1m USDC
  }

  function testStrategy() public {
    Erc20Metadata memory meta = Erc20Metadata("Ether", "ETH", 18);
  }
}
