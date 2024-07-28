// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {StrategyParams, Fees, CoreAddresses, Erc20Metadata, Errors, Roles} from "../../src/abstract/AsTypes.sol";
import {StrategyV5Simulator, StrategyV5CompositeSimulator} from "./StrategyV5Simulator.sol";
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
  bytes[] emptyBytesArray = new bytes[](8); // assembly { mstore(emptyBytesArray, 0) } // Stores 32 bytes of zeros at the start of emptyBytesArray

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

  // fund admin + manager + keeper + bob + alice + charlie
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

  function _setUp() internal virtual {}

  // refuel accounts before each test
  function setUp() public {
    if (refuel) {
      fundAll(1e4 ether);
    }
    _setUp();
  }

  function previewCollectFees() public returns (uint256 feesCollected) {
    vm.prank(manager);
    bytes memory result = strat.simulate{gas: 10_000_000}(
      abi.encodeWithSignature("collectFees()")
    );
    (bool success, bytes memory data) = abi.decode(result, (bool, bytes));
    feesCollected = abi.decode(data, (uint256));
  }

  function logState(IStrategyV5 _strat, string memory _msg) public {
    string memory s = "state";
    vm.serializeUint(s, "sharePrice", _strat.sharePrice());
    vm.serializeUint(s, "totalSupply", _strat.totalSupply());
    vm.serializeUint(s, "totalAccountedSupply", _strat.totalAccountedSupply());
    vm.serializeUint(s, "totalAccountedAssets", _strat.totalAccountedAssets());
    vm.serializeUint(s, "invested", _strat.invested());
    vm.serializeUint(s, "available", _strat.available());
    vm.serializeUint(s, "balanceOf(admin)", _strat.balanceOf(admin));
    vm.serializeUint(s, "balanceOf(manager)", _strat.balanceOf(manager));
    vm.serializeUint(s, "balanceOf(user[0])", _strat.balanceOf(bob));
    vm.serializeUint(
      s,
      "asset.balanceOf(strat)",
      _strat.asset().balanceOf(address(_strat))
    );
    vm.serializeUint(
      s,
      "claimableTransactionFees",
      _strat.claimableTransactionFees()
    );
    vm.prank(keeper);
    uint256[] memory previewLiquidate = _strat.preview(0, false).dynamic();
    vm.serializeUint(s, "previewLiquidate", previewLiquidate);
    vm.prank(keeper);
    uint256[] memory previewInvest = _strat.preview(0, true).dynamic();
    s = vm.serializeUint(s, "previewInvest", previewInvest);
    console.log(_msg, s);
  }

  function logState(string memory _msg) public {
    logState(strat, _msg);
  }

  function initOracle() public virtual;

  function deployDependencies() public virtual {
    accessController = new AccessController(admin);
    grantRoles();
    oracle = new ChainlinkProvider(address(accessController));
    initOracle();
    agent = address(new StrategyV5Agent(address(accessController)));
  }

  function init(IStrategyV5 _strat, Fees memory _fees) public virtual;

  function deployStrat(Fees memory _fees, uint256 _minLiquidit) public returns (IStrategyV5) {
    return deployStrat(_fees, _minLiquidit, false);
  }

  function deployStrat(
    Fees memory _fees,
    uint256 _minLiquidity,
    bool _isComposite
  ) public returns (IStrategyV5) {
    console.log("deployStrat, agent:", address(agent), "accessController:", address(accessController));
    if (address(agent) == address(0) || address(accessController) == address(0)) {
      console.log("deploying dependencies");
      deployDependencies();
    }
    IStrategyV5 s = IStrategyV5(
      _isComposite
        ? address(new StrategyV5CompositeSimulator(address(accessController), vm))
        : address(new StrategyV5Simulator(address(accessController), vm))
    );
    init(s, _fees); // overriden in TestArbEnv, TestBaseEnv...
    vm.prank(admin);
    s.setExemption(admin, true); // exempt admin from fees
    vm.prank(admin);
    s.setExemption(manager, true); // exempt manager from fees
    require(s.exemptionList(admin), "Admin should be exempt from fees");
    require(s.exemptionList(manager), "Manager should be exempt from fees");

    seedLiquidity(s, _minLiquidity);
    logState(s, "Deployed new dummy strat");
    return s;
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
    uint256 initialTime = block.timestamp;
    vm.warp(initialTime + accessController.ROLE_ACCEPTANCE_TIMELOCK()); // fast forward time to acceptance window
    vm.prank(manager);
    accessController.acceptRole(Roles.MANAGER); // accept role
    require(
      accessController.hasRole(Roles.MANAGER, manager),
      "Manager should have MANAGER role"
    );
    vm.warp(initialTime); // reset time
  }

  function seedLiquidity(IStrategyV5 _strat, uint256 _minLiquidity) public {
    vm.startPrank(admin);
    _strat.setMinLiquidity(_minLiquidity);
    _strat.asset().approve(address(_strat), type(uint256).max);
    _strat.seedLiquidity(_minLiquidity, type(uint256).max); // seed liquidity, set maxTvl, unpause
    vm.stopPrank();
    vm.prank(manager);
    require(
      _strat.collectFees() == 0,
      "Collected fees should be 0 since the admin seeded and is exempt from fees"
    );
  }
}
