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
} from "../src/abstract/AsTypes.sol";
import {AsArrays} from "../src/libs/AsArrays.sol";
import {AsMaths} from "../src/libs/AsMaths.sol";
import {AccessController} from "../src/abstract/AccessController.sol";
import {ChainlinkProvider} from "../src/abstract/ChainlinkProvider.sol";
import {StrategyV5} from "../src/abstract/StrategyV5.sol";
import {StrategyV5Agent} from "../src/abstract/StrategyV5Agent.sol";
import {IAs4626} from "../src/interfaces/IAs4626.sol";
import {IStrategyV5} from "../src/interfaces/IStrategyV5.sol";
import {ERC20} from "../src/abstract/ERC20.sol";

contract FeesTest is Test {
  using AsMaths for uint256;
  using AsArrays for address;
  using AsArrays for uint16;
  using AsArrays for uint256;
  using AsArrays for uint256[8];

  uint256 private constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;

  address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // asset/input[0]
  address USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // input[1]
  address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // wgas

  address ETH_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
  address USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
  address USDCe_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

  address swapper = 0x503301Eb7cfC64162b5ce95cc67B84Fbf6dF5255;
  address rich = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

  AccessController accessController;
  IStrategyV5 strat;
  ChainlinkProvider oracle;
  address agent;
  ERC20 usdc = ERC20(USDC);
  ERC20 weth = ERC20(WETH);

  // Addresses for testing
  address admin = vm.addr(1);
  address manager = vm.addr(2);
  address keeper = vm.addr(3);
  address user = vm.addr(4);

  constructor() Test() {
    // create arbitrum fork and deal test tokens
    vm.createSelectFork(vm.rpcUrl(vm.envString("arbitrum_private_rpc")));
    vm.startPrank(rich);
    usdc.transfer(admin, 1_000_000e6);
    usdc.transfer(manager, 1_000_000e6);
    usdc.transfer(user, 1_000_000e6);
    vm.stopPrank();
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

  function deployDependencies() public {
    accessController = new AccessController(admin);
    grantRoles();
    oracle = new ChainlinkProvider(address(accessController));
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
    agent = address(new StrategyV5Agent(address(accessController)));
  }

  function deployStrat(Fees memory _fees) public {
    strat = IStrategyV5(address(new StrategyV5(address(accessController))));
    vm.prank(admin);
    strat.setExemption(admin, true); // self exempt to avoid paying fees on deposit etc
    init(_fees);
    seedLiquidity(1000e6);
    logState("deployed new dummy strat");
  }

  function init(Fees memory _fees) public {
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

  function grantRoles() public {
    // grant roles
    vm.startPrank(admin);
    accessController.grantRole(Roles.KEEPER, keeper);
    accessController.grantRole(Roles.MANAGER, manager);
    vm.stopPrank();
    // advance time
    vm.warp(block.timestamp + accessController.ROLE_ACCEPTANCE_TIMELOCK());
    vm.prank(manager);
    accessController.acceptRole(Roles.MANAGER);
  }

  function seedLiquidity(uint256 _minLiquidity) public {
    vm.startPrank(admin);
    // set vault minimum liquidity
    strat.setMinLiquidity(_minLiquidity);
    // seed liquidity/unpause
    usdc.approve(address(strat), type(uint256).max);
    strat.seedLiquidity(_minLiquidity, type(uint256).max); // deposit 10 USDC (minLiquidity), set maxTVL to 1m USDC
    vm.stopPrank();
  }

  function entryFees(Fees memory _fees) public {
    console.log("--- entryFees test ---");
    // new strat on every fees test
    deployStrat(_fees);
    // deposit
    uint256 feesBefore = strat.claimableAssetFees();
    vm.startPrank(user);
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(1000e6, user); // same as safeDeposit
    uint256 entryFeeFromDeposit = strat.claimableAssetFees() - feesBefore;
    console.log(entryFeeFromDeposit, "entry fee from deposit");
    // mint
    strat.mint(strat.convertToShares(1000e6, true), user); // same as safeMint
    vm.stopPrank();
    uint256 entryFeeFromMint = strat.claimableAssetFees() - entryFeeFromDeposit - feesBefore;
    console.log(entryFeeFromMint, "entry fee from mint ");
    // assert
    if (entryFeeFromDeposit != entryFeeFromMint) {
      revert("Deposit and mint fees do not match");
    }
  }

  function exitFees(Fees memory _fees) public returns (uint256) {
    console.log("--- exitFees test ---");
    deployStrat(_fees);

    // resetStratTo(user, 2000e6);
    vm.startPrank(user);

    // deposit to be able to withdraw
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(3000e6, user); // same as safeDeposit
    // withdraw
    uint256 feesBefore = strat.claimableAssetFees();
    strat.withdraw(1000e6, user, user); // same as safeWithdraw
    uint256 exitFeeFromWithdraw = strat.claimableAssetFees() - feesBefore;
    console.log(exitFeeFromWithdraw, "exit fee from withdraw");
    // redeem
    strat.redeem(strat.convertToShares(1000e6), user, user); // same as safeRedeem
    vm.stopPrank();
    uint256 exitFeeFromRedeem = strat.claimableAssetFees() - exitFeeFromWithdraw - feesBefore;
    console.log(exitFeeFromRedeem, "exit fee from redeem");
    // assert
    if (exitFeeFromWithdraw != exitFeeFromRedeem) {
      revert("Withdraw and redeem fees do not match");
    }
    return exitFeeFromWithdraw;
  }

  function previewCollectFees() public returns (uint256) {
    vm.prank(manager);
    (bool success, bytes memory data) = address(strat).staticcall(abi.encodeWithSelector(IAs4626.collectFees.selector));
    if (!success) {
      revert("collectFees static call failed");
    }
    return abi.decode(data, (uint256));
  }

  // Test management fee after fast-forwarding time
  function managementFees(Fees memory _fees) public {
    console.log("--- mgmtFees test ---");
    deployStrat(_fees);
    vm.startPrank(user);
    // deposit
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(1000e6, user);
    vm.stopPrank();
    uint256 feeBefore = previewCollectFees(); // existing + entry fee
    // fast-forward time 1 year without changing the share price (no performance fees)
    vm.warp(block.timestamp + 365 days);
    // check management fee
    uint256 mgmtFees = previewCollectFees() - feeBefore; // only management fees, no perf as sharePrice is constant
    console.log(mgmtFees, ": 1 year MGMT FEE");

    uint256 theoreticalMgmtFees = strat.totalAssets().mulDiv(strat.fees().mgmt, AsMaths.BP_BASIS);
    // assert
    if (mgmtFees != theoreticalMgmtFees) {
      revert("Management fee does not match");
    }
  }

  // Test performance fee by simulating strategy performance
  function performanceFees(Fees memory _fees) public {
    console.log("--- perfFees test ---");
    deployStrat(_fees);

    // set profit cooldown to 1 second
    vm.prank(admin);
    strat.setProfitCooldown(1 seconds); // no share price linearization
    vm.startPrank(user);
    // deposit
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(1000e6, user);

    uint256 feeBefore = previewCollectFees(); // pre-existing fee
    uint256 sharePriceBefore = strat.sharePrice();

    // pump share price through total assets
    usdc.transfer(address(strat), 2000e6); // 2x the assets in order to 2x the share price

    // fast-forward profit cooldown
    vm.warp(block.timestamp + 2 seconds); // no management fee as time is too short
    uint256 sharePriceAfter = strat.sharePrice();
    uint256 sharePriceDiffBps = (sharePriceAfter - sharePriceBefore).mulDiv(AsMaths.BP_BASIS, sharePriceAfter); // eg. 50% of current share price

    // check perf fee
    uint256 perfFees = previewCollectFees() - feeBefore; // only management fees, no perf as sharePrice is constant
    console.log(perfFees, "perf fees from share price 2x");

    uint256 theoreticalPerfFees = (sharePriceDiffBps * strat.totalAssets()).mulDiv(strat.fees().perf, AsMaths.BP_BASIS ** 2);
    // assert
    if (perfFees != theoreticalPerfFees) {
      revert("Performance fee does not match");
    }
  }

  // Collect fees and check against theoretical amounts
  function collectFees(Fees memory _fees) public {
    console.log("--- collectFees test ---");
    deployStrat(_fees);
    vm.startPrank(manager);
     // inflate performance
    usdc.transfer(address(strat), 1000e6);
    // fast-forward time
    vm.warp(block.timestamp + 365 days);
    // collect fees
    uint256 feeBefore = strat.claimableAssetFees();
    console.log(feeBefore, "claimableAssetFees before collect fees");
    strat.collectFees();
    uint256 feeAfter = strat.claimableAssetFees();
    console.log(feeAfter, "claimableAssetFees after collect fees");
    // assert
    vm.stopPrank();
  }

  function flow(Fees memory _fees) public {
    deployDependencies();
    entryFees(Fees({perf: 0, mgmt: 0, entry: _fees.entry, exit: 0, flash: 0}));
    exitFees(Fees({perf: 0, mgmt: 0, entry: 0, exit: _fees.exit, flash: 0}));
    managementFees(Fees({perf: 0, mgmt: _fees.mgmt, entry: 0, exit: 0, flash: 0}));
    performanceFees(Fees({perf: _fees.perf, mgmt: 0, entry: 0, exit: 0, flash: 0}));
    // flashFees(Fees({perf: 0, mgmt: 0, entry: 0, exit: 0, flash: _fees.flash}));
    collectFees(_fees);
  }

  function testAll() public {
    flow(Fees({perf: 10_00, mgmt: 10_00, entry: 1_00, exit: 1_00, flash: 1_00}));
  }
}
