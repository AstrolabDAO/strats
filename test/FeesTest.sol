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
import {CompoundV3MultiStake} from
  "../src/implementations/Compound/CompoundV3MultiStake.sol";
import {StrategyV5} from "../src/abstract/StrategyV5.sol";
import {IStrategyV5} from "../src/interfaces/IStrategyV5.sol";
import {StrategyV5Agent} from "../src/abstract/StrategyV5Agent.sol";
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
          validities: uint256(3600 * 24).toArray() // Chainlink quote validity
        })
      )
    );
    agent = address(new StrategyV5Agent(address(accessController)));
    strat = IStrategyV5(address(new CompoundV3MultiStake(address(accessController))));
    strat.setExemption(admin, true); // self exempt to avoid paying fees on deposit etc
    vm.stopPrank();
  }

  function init(Fees memory _mockFees) public {
    vm.startPrank(admin);

    // initialize the strategy
    // ERC20 metadata
    Erc20Metadata memory erc20Meta = Erc20Metadata({
      name: "Astrolab Primitive CompoundV3 USD",
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
    Fees memory mockFees = _mockFees;

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
    accessController.grantRole(Roles.KEEPER, keeper);
    accessController.grantRole(Roles.MANAGER, manager);
    vm.stopPrank();
    vm.startPrank(manager);
    // advance time
    vm.warp(block.timestamp + accessController.ROLE_ACCEPTANCE_TIMELOCK());
    accessController.acceptRole(Roles.MANAGER);
    vm.stopPrank();
  }

  function seedLiquidity() public {
    vm.startPrank(admin);
    // set vault minimum liquidity
    strat.setMinLiquidity(1000e6);
    console.log("max deposit before unpause", strat.maxDeposit(address(0)));
    strat.unpause();
    // seed liquidity/unpause
    usdc.approve(address(strat), type(uint256).max);
    strat.seedLiquidity(strat.minLiquidity(), type(uint256).max); // deposit 10 USDC (minLiquidity), set maxTVL to 1m USDC
    vm.stopPrank();
  }

  function entryFees(Fees memory _fees) public {
    console.log("--- entryFees test ---");
    // new strat on every fees test
    deploy();
    init(_fees);
    grantRoles();
    seedLiquidity();
    // resetStrat();
    vm.startPrank(user);
    // deposit
    uint256 feesBefore = strat.claimableAssetFees();
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(1000e6, user); // same as safeDeposit
    uint256 entryFeeFromDeposit = strat.claimableAssetFees() - feesBefore;
    console.log(entryFeeFromDeposit, "entry fee from deposit");
    // mint
    strat.mint(strat.convertToShares(1000e6), user); // same as safeMint
    uint256 entryFeeFromMint = strat.claimableAssetFees() - entryFeeFromDeposit - feesBefore;
    console.log(entryFeeFromMint, "entry fee from mint ");
    // assert
    if (entryFeeFromDeposit != entryFeeFromMint) {
      revert("Deposit and mint fees do not match");
    }
    vm.stopPrank();
  }

  // function resetStrat() public {
  //   vm.startPrank(user);
  //   console.log("--- reset ---");
  //   uint256 minLiquidity = strat.minLiquidity();

  //   console.log(usdc.balanceOf(address(strat)), "strat balance before reset");
  //   console.log(strat.totalSupply(), "total supply before reset");
  //   console.log(strat.totalAssets(), "total assets before reset");
  //   console.log(strat.sharePrice(), "sharePrice before reset");
  //   console.log(minLiquidity, "min liquidity before reset");

  //   // burn the user's shares
  //   uint256 userBalance = strat.balanceOf(user);
  //   if (userBalance > 0) {
  //     console.log(userBalance, "user shares before reset");
  //     strat.redeem(userBalance - 1, user, user); // burn all shares
  //   }
  //   console.log(strat.balanceOf(user), "user shares after reset");
  //   vm.stopPrank();

  //   vm.startPrank(address(strat));
  //   usdc.transfer(address(admin), usdc.balanceOf(address(strat)) - minLiquidity); // burn all assets but the minLiquidity
  //   // reset total supply
  //   assembly { sstore(_TOTAL_SUPPLY_SLOT, minLiquidity) } // reinitialize total supply
  //   // strat.last.totalAssets = minLiquidity; // reinitialize cached total assets
  //   // strat.last.sharePrice = 10 ** strat.decimals(); // reinitialize cached share price
  //   console.log(usdc.balanceOf(address(strat)), "strat balance after reset");
  //   console.log(strat.totalSupply(), "total supply after reset");
  //   console.log(strat.totalAssets(), "total assets after reset");
  //   console.log(strat.sharePrice(), "sharePrice after reset");
  //   vm.stopPrank();
  // }

  // function resetStratTo(address receiver, uint256 shares) public {
  //   resetStrat();
  //   vm.startPrank(admin);
  //   strat.mint(shares, admin); // mint shares without entry fee (depositing 1:1)
  //   strat.transfer(receiver, shares); // transfer shares to user
  //   console.log(usdc.balanceOf(address(strat)), "strat balance after reset+to");
  //   console.log(strat.totalSupply(), "total supply after reset+to");
  //   console.log(strat.totalAssets(), "total assets after reset+to");
  //   console.log(strat.sharePrice(), "sharePrice after reset+to");
  //   vm.stopPrank();
  // }

  function exitFees(Fees memory _fees) public returns (uint256) {
    console.log("--- exitFees test ---");
    // new strat on every fees test
    deploy();
    init(_fees);
    grantRoles();
    seedLiquidity();

    // resetStratTo(user, 2000e6);
    vm.startPrank(user);

    // deposit to be able to withdraw
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(3000e6, user); // same as safeDeposit
    // withdraw
    uint256 feesBefore = strat.claimableAssetFees();
    strat.withdraw(999e6, user, user); // same as safeWithdraw
    uint256 exitFeeFromWithdraw = strat.claimableAssetFees() - feesBefore;
    console.log(exitFeeFromWithdraw, "EXIT FEE from withdraw");
    // redeem
    strat.redeem(strat.convertToShares(999e6), user, user); // same as safeRedeem
    uint256 exitFeeFromRedeem = strat.claimableAssetFees() - exitFeeFromWithdraw - feesBefore;
    console.log(exitFeeFromRedeem, "EXIT FEE from redeem");
    // assert
    if (exitFeeFromWithdraw != exitFeeFromRedeem) {
      revert("Withdraw and redeem fees do not match");
    }
    vm.stopPrank();
    return exitFeeFromWithdraw;
  }

  // Test management fee after fast-forwarding time
  function managementFees(Fees memory _fees) public {
    console.log("--- mgmtFees test ---");
    // new strat on every fees test
    deploy();
    init(_fees);
    grantRoles();
    seedLiquidity();

    vm.startPrank(user);
    // deposit
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(1000e6, user);
    uint256 feeBefore = strat.claimableAssetFees(); // existing + entry fee
    // fast-forward time 1 year without changing the share price (no performance fees)
    vm.warp(block.timestamp + 365 days);
    // check management fee
    uint256 mgmtFees = strat.claimableAssetFees() - feeBefore; // only management fees, no perf as sharePrice is constant
    console.log(mgmtFees, ": 1 year MGMT FEE");

    uint256 theoreticalMgmtFees = strat.totalAssets().mulDiv(strat.fees().mgmt, AsMaths.BP_BASIS);
    // assert
    if (mgmtFees != theoreticalMgmtFees) {
      revert("Management fee does not match");
    }
    vm.stopPrank();
  }

  // Test performance fee by simulating strategy performance
  function performanceFees(Fees memory _fees) public {
    console.log("--- perfFees test ---");
    // new strat on every fees test
    deploy();
    init(_fees);
    grantRoles();
    seedLiquidity();

    // set profit cooldown to 1 second
    vm.startPrank(admin);
    strat.setProfitCooldown(1 seconds); // no share price linearization
    vm.stopPrank();

    vm.startPrank(user);
    // deposit
    usdc.approve(address(strat), type(uint256).max);
    strat.deposit(1000e6, user);
    uint256 feeBefore = strat.claimableAssetFees(); // pre-existing fee
    uint256 sharePriceBefore = strat.sharePrice();

    // pump share price through total assets
    usdc.transfer(address(strat), 2000e6); // 2x the assets in order to 2x the share price

    // fast-forward profit cooldown
    vm.warp(block.timestamp + 2 seconds); // no management fee as time is too short
    uint256 sharePriceAfter = strat.sharePrice();
    uint256 sharePriceDiffBps = (sharePriceAfter - sharePriceBefore).mulDiv(AsMaths.BP_BASIS, sharePriceAfter); // eg. 50% of current share price

    // check perf fee
    uint256 perfFees = strat.claimableAssetFees() - feeBefore; // only management fees, no perf as sharePrice is constant
    console.log(perfFees, "perf fees from share price 2x");

    uint256 theoreticalPerfFees = (sharePriceDiffBps * strat.totalAssets()).mulDiv(strat.fees().perf, AsMaths.BP_BASIS ** 2);
    // assert
    if (perfFees != theoreticalPerfFees) {
      revert("Performance fee does not match");
    }
    vm.stopPrank();
  }

  // Collect fees and check against theoretical amounts
  function collectFees(Fees memory _fees) public {
    console.log("--- collectFees test ---");
    // new strat on every fees test
    deploy();
    init(_fees);
    grantRoles();
    seedLiquidity();

    vm.startPrank(manager);
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
    entryFees(_fees);
    exitFees(_fees);
    // managementFees(_fees);
    // performanceFees(_fees); // NB: must be called last, as sharePrice is not reinitialized by resetStrat
    collectFees(_fees);
  }
  function testLowFeeConfiguration() public {
    Fees memory lowFees = Fees({perf: 10, mgmt: 10, entry: 1, exit: 1, flash: 1});
    flow(lowFees);
  }

  function testMidFeeConfiguration() public {
    Fees memory midFees = Fees({perf: 100, mgmt: 100, entry: 10, exit: 10, flash: 1});
    flow(midFees);
  }

  function testHighFeeConfiguration() public {
    Fees memory highFees =
      Fees({perf: 10_00, mgmt: 10_00, entry: 10_0, exit: 10_0, flash: 1});
    flow(highFees);
  }
}
