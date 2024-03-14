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
import {IStrategyV5} from "../src/interfaces/IStrategyV5.sol";
import {AccessController} from "../src/abstract/AccessController.sol";
import {ChainlinkProvider} from "../src/abstract/ChainlinkProvider.sol";
import {CompoundV3MultiStake} from
  "../src/implementations/Compound/CompoundV3MultiStake.sol";
import {StrategyV5} from "../src/abstract/StrategyV5.sol";
import {StrategyV5Agent} from "../src/abstract/StrategyV5Agent.sol";
import {ERC20} from "../src/abstract/ERC20.sol";

contract CompoundV3MultiStakeTest is Test {
  using AsArrays for address;
  using AsArrays for uint16;
  using AsArrays for uint256;
  using AsArrays for uint256[8];

  address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // asset/input[0]
  address USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // input[1]
  address COMP = 0x354A6dA3fcde098F8389cad84b0182725c6C91dE; // reward[0]
  address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // wgas

  address ETH_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
  address USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
  address USDCe_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

  address cUSDC = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
  address cometRewards = 0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;
  address swapper = 0x503301Eb7cfC64162b5ce95cc67B84Fbf6dF5255;
  address rich = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

  AccessController accessController;
  IStrategyV5 strat;
  ChainlinkProvider oracle;
  address agent;
  ERC20 usdc = ERC20(USDC);
  ERC20 weth = ERC20(WETH);

  address admin = vm.addr(1);
  address manager = vm.addr(2);
  address keeper = vm.addr(3);
  address user = vm.addr(4);

  constructor() Test() {
    // create arbitrum fork and deal test tokens
    vm.createSelectFork(vm.rpcUrl(vm.envString("arbitrum-private-rpc")));
    vm.startPrank(rich);
    // deal(USDC, admin, 100e6);
    // deal(USDC, manager, 100e6);
    // deal(USDC, user, 100e6);
    usdc.transfer(admin, 100e6);
    usdc.transfer(manager, 100e6);
    usdc.transfer(user, 10000e6);
    vm.stopPrank();
  }

  function setUp() public {
    vm.deal(admin, 1e4 ether);
    vm.deal(manager, 1e4 ether);
    vm.deal(user, 1e4 ether);
  }

  function logState(string memory _msg) public {
    string memory s = "state";
    vm.serializeUint(s, "sharePrice", strat.sharePrice());
    vm.serializeUint(s, "totalSupply", strat.totalSupply());
    vm.serializeUint(s, "totalAccountedSupply", strat.totalAccountedSupply());
    vm.serializeUint(s, "totalAccountedAssets", strat.totalAccountedAssets());
    vm.serializeUint(s, "invested", strat.invested());
    vm.serializeUint(s, "available", strat.available());
    vm.serializeUint(s, "userBalance", strat.balanceOf(user));
    vm.serializeUint(s, "strategyAssetBalance", usdc.balanceOf(address(strat)));
    vm.serializeUint(s, "claimableAssetFees", strat.claimableAssetFees());
    uint256[] memory previewLiquidate = strat.previewLiquidate(0).dynamic();
    vm.serializeUint(s, "previewLiquidate", previewLiquidate);
    uint256[] memory previewInvest = strat.previewInvest(0).dynamic();
    s = vm.serializeUint(s, "previewInvest", previewInvest);
    console.log(_msg, s);
  }

  function deploy() public {
    vm.startPrank(admin);

    // deploy strategy and agent back-end
    accessController = new AccessController();
    console.log("is admin: ", accessController.hasRole(Roles.ADMIN, admin));

    oracle = new ChainlinkProvider(address(accessController));
    oracle.update(
      abi.encode(
        ChainlinkProvider.Params({
          assets: USDC.toArray(), // [USDC]
          feeds: USDC_FEED.toBytes32Array(), // Chainlink USDC
          validities: uint256(3600).toArray() // Chainlink default validity
        })
      )
    );
    agent = address(new StrategyV5Agent(address(accessController)));
    strat = IStrategyV5(address(new CompoundV3MultiStake(address(accessController))));
    vm.stopPrank();
  }

  function init() public {
    vm.startPrank(admin);

    // initialize the strategy
    // ERC20 metadata
    Erc20Metadata memory erc20Meta = Erc20Metadata({
      name: "Astrolab Primitive Compound USD",
      symbol: "apCOMP-USD",
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
    // fees
    Fees memory mockFees = Fees({perf: 10_00, mgmt: 0, entry: 2, exit: 2, flash: 2}); // 10% perf, 0% mgmt, .02% entry, .02% exit, .02% flash
    // aggregated strategy base parameters
    StrategyParams memory params = StrategyParams({
      erc20Metadata: erc20Meta,
      coreAddresses: coreAddresses,
      fees: mockFees,
      inputs: USDC.toArray(), // [USDC]
      inputWeights: uint16(100_00).toArray16(), // 100% weight on USDC
      lpTokens: cUSDC.toArray(),
      rewardTokens: COMP.toArray(), // [COMP]
      extension: abi.encode(cometRewards) // compound specific init params
    });

    // initialize (admin only)
    strat.init(params);
    vm.stopPrank();
  }

  function grantRoles() public {
    vm.startPrank(admin);

    // grant roles
    accessController.grantRole(Roles.MANAGER, manager);
    accessController.grantRole(Roles.KEEPER, keeper);
    vm.stopPrank();
  }

  function seedLiquidity() public {
    vm.startPrank(admin);
    logState("before seed liquidity");
    // set vault minimum liquidity
    strat.setMinLiquidity(10e6);
    console.log("max deposit before unpause", strat.maxDeposit(address(0)));
    strat.unpause();
    // seed liquidity/unpause
    usdc.approve(address(strat), 10e6);
    strat.seedLiquidity(10e6, 1e12); // deposit 10 USDC (minLiquidity), set maxTVL to 1m USDC
    logState("after seed liquidity");
    vm.stopPrank();
  }

  function deposit() public {
    vm.startPrank(user);
    logState("before deposit");
    usdc.approve(address(strat), 10000e6);
    strat.deposit(10000e6, user);
    logState("after deposit");
    vm.stopPrank();
  }

  function withdraw() public {
    vm.startPrank(user);
    logState("before withdraw");
    strat.withdraw(1e6, user, user);
    logState("after withdraw");
    vm.stopPrank();
  }

  function testAll() public {
    deploy();
    init();
    grantRoles();
    seedLiquidity();
    deposit();
    withdraw();
    // TODO: implement invest/liquidate/compound using https://github.com/memester-xyz/surl and a local Swapper API
  }
}
