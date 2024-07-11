// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {StrategyParams, Fees, CoreAddresses, Erc20Metadata, Errors, Roles} from "../../src/abstract/AsTypes.sol";
import {StrategyV5Simulator, StrategyV5CompositeSimulator} from "../../src/implementations/StrategyV5Simulator.sol";
import {AsArrays} from "../../src/libs/AsArrays.sol";
import {AsMaths} from "../../src/libs/AsMaths.sol";
import {AccessController} from "../../src/abstract/AccessController.sol";
import {ChainlinkProvider} from "../../src/abstract/ChainlinkProvider.sol";
import {StrategyV5} from "../../src/abstract/StrategyV5.sol";
import {StrategyV5Agent} from "../../src/abstract/StrategyV5Agent.sol";
import {IStrategyV5} from "../../src/interfaces/IStrategyV5.sol";
import {ERC20} from "../../src/abstract/ERC20.sol";

abstract contract TestEnv is Test {
  using AsArrays for address;
  using AsArrays for uint16;
  using AsArrays for uint256;
  using AsArrays for uint256[8];

  bool refuel;
  address admin = vm.addr(1);
  address manager = vm.addr(2);
  address keeper = vm.addr(3);
  address[] users = [vm.addr(4), vm.addr(5), vm.addr(6), vm.addr(7)];
  address bob = users[0];
  address alice = users[1];
  address charlie = users[2];
  Fees zeroFees = Fees({perf: 0, mgmt: 0, entry: 0, exit: 0, flash: 0});

  AccessController accessController;
  IStrategyV5 strat;
  ChainlinkProvider oracle;
  address agent;

  constructor(bool _refuel) {
    refuel = _refuel;
  }

  // fund gas/native
  function fund(address _to, uint256 _amount) public {
    vm.deal(_to, _amount);
  }

  // fund erc20
  function fund(address _to, address _token, uint256 _amount) public {
    deal(_token, _to, _amount);
  }

  // fund erc20 from sender
  function fund(
    address _from,
    address _to,
    address _token,
    uint256 _amount
  ) public {
    vm.prank(_from);
    ERC20(_token).transfer(_to, _amount);
  }

  function fundAll(int256 _amount) public {
    vm.deal(admin, uint256(_amount));
    vm.deal(manager, uint256(_amount));
    vm.deal(keeper, uint256(_amount));
    for (uint256 i = 0; i < users.length; i++) {
      vm.deal(users[i], uint256(_amount));
    }
  }

  function fundAll(address _token, int256 _amount) public {
    deal(_token, admin, uint256(_amount));
    deal(_token, manager, uint256(_amount));
    deal(_token, keeper, uint256(_amount));
    for (uint256 i = 0; i < users.length; i++) {
      deal(_token, users[i], uint256(_amount));
    }
  }

  function fundAll(address _from, address _token, int256 _amount) public {
    vm.startPrank(_from);
    ERC20(_token).transfer(admin, uint256(_amount));
    ERC20(_token).transfer(manager, uint256(_amount));
    ERC20(_token).transfer(keeper, uint256(_amount));
    for (uint256 i = 0; i < users.length; i++) {
      ERC20(_token).transfer(users[i], uint256(_amount));
    }
    vm.stopPrank();
  }

  // refuel accounts before each test
  function setUp() public {
    if (refuel) {
      fundAll(1e4 ether);
    }
  }

  function previewCollectFees() public returns (uint256 feesCollected) {
    vm.prank(manager);
    bytes memory result = strat.simulate{gas: 10_000_000}(
      abi.encodeWithSignature("collectFees()")
    );
    (bool success, bytes memory data) = abi.decode(result, (bool, bytes));
    feesCollected = abi.decode(data, (uint256));
  }

  function logState(string memory _msg) public {
    string memory s = "state";
    vm.serializeUint(s, "sharePrice", strat.sharePrice());
    vm.serializeUint(s, "totalSupply", strat.totalSupply());
    vm.serializeUint(s, "totalAccountedSupply", strat.totalAccountedSupply());
    vm.serializeUint(s, "totalAccountedAssets", strat.totalAccountedAssets());
    vm.serializeUint(s, "invested", strat.invested());
    vm.serializeUint(s, "available", strat.available());
    vm.serializeUint(s, "balanceOf(admin)", strat.balanceOf(admin));
    vm.serializeUint(s, "balanceOf(manager)", strat.balanceOf(manager));
    vm.serializeUint(s, "balanceOf(user[0])", strat.balanceOf(bob));
    vm.serializeUint(
      s,
      "asset.balanceOf(strat)",
      strat.asset().balanceOf(address(strat))
    );
    vm.serializeUint(
      s,
      "claimableTransactionFees",
      strat.claimableTransactionFees()
    );
    uint256[] memory previewLiquidate = strat.previewLiquidate(0).dynamic();
    vm.serializeUint(s, "previewLiquidate", previewLiquidate);
    uint256[] memory previewInvest = strat.previewInvest(0).dynamic();
    s = vm.serializeUint(s, "previewInvest", previewInvest);
    console.log(_msg, s);
  }

  function initOracle() public virtual;

  function deployDependencies() public virtual {
    accessController = new AccessController(admin);
    grantRoles();
    oracle = new ChainlinkProvider(address(accessController));
    initOracle();
    agent = address(new StrategyV5Agent(address(accessController)));
  }

  function init(Fees memory _fees) public virtual;

  function deployStrat(Fees memory _fees, uint256 _minLiquidit) public {
    deployStrat(_fees, _minLiquidit, false);
  }

  function deployStrat(
    Fees memory _fees,
    uint256 _minLiquidity,
    bool _isComposite
  ) public {
    strat = IStrategyV5(
        _isComposite
          ? address(new StrategyV5CompositeSimulator(address(accessController)))
          : address(new StrategyV5Simulator(address(accessController)))
      );
    init(_fees);
    vm.prank(admin);
    strat.setExemption(admin, true); // exempt admin from fees
    vm.prank(admin);
    strat.setExemption(manager, true); // exempt manager from fees
    require(strat.exemptionList(admin), "Admin should be exempt from fees");
    require(strat.exemptionList(manager), "Manager should be exempt from fees");

    seedLiquidity(_minLiquidity);
    logState("deployed new dummy strat");
  }

  function grantRoles() public {
    // grant roles
    vm.startPrank(admin);
    accessController.grantRole(Roles.KEEPER, keeper); // does not need acceptance
    require(
      accessController.hasRole(Roles.KEEPER, keeper),
      "Keeper should have KEEPER role"
    );
    accessController.grantRole(Roles.MANAGER, manager); // needs acceptance
    vm.stopPrank();
    vm.warp(block.timestamp + accessController.ROLE_ACCEPTANCE_TIMELOCK()); // fast forward time to acceptance window
    vm.prank(manager);
    accessController.acceptRole(Roles.MANAGER); // accept role
    require(
      accessController.hasRole(Roles.MANAGER, manager),
      "Manager should have MANAGER role"
    );
  }

  function seedLiquidity(uint256 _minLiquidity) public {
    vm.startPrank(admin);
    strat.setMinLiquidity(_minLiquidity);
    strat.asset().approve(address(strat), type(uint256).max);
    strat.seedLiquidity(_minLiquidity, type(uint256).max); // seed liquidity, set maxTvl, unpause
    vm.stopPrank();
    vm.prank(manager);
    require(
      strat.collectFees() == 0,
      "Collected fees should be 0 since the admin seeded and is exempt from fees"
    );
  }
}
