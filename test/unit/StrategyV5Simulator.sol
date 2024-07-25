// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/abstract/StrategyV5.sol";
import "../../src/abstract/StrategyV5Composite.sol";
import "../../src/abstract/Simulator.sol";
import "forge-std/Test.sol";

contract StrategyV5Simulator is StrategyV5, Simulator {
  using SafeERC20 for IERC20Metadata;

  Vm internal vm;
  address internal immutable dummyVault;

  constructor(address _accessController, Vm _vm) StrategyV5(_accessController) {
    vm = _vm;
    dummyVault = vm.addr(5); // == alice
  }

  /**
   * @dev Simulates a delegate call to a target contract in the context of self
   * Internally reverts execution to avoid side effects (making it static)
   * Catches revert and returns encoded result as bytes
   * @param _data Calldata that should be sent to the target contract (encoded method name and arguments)
   */
  function simulate(
    bytes calldata _data
  ) external returns (bytes memory response) {
    return Simulator.simulate(address(this), _data);
  }

  function _setParams(bytes memory _params) internal override {}

  function _stake(uint256 _index, uint256 _amount) internal override {
    inputs[_index].safeTransferFrom(address(this), dummyVault, _amount);
  }

  function _unstake(uint256 _index, uint256 _amount) internal override {
    vm.prank(dummyVault);
    inputs[_index].safeTransferFrom(dummyVault, address(this), _amount);
  }

  function _investedInput(
    uint256 _index
  ) internal view override returns (uint256) {
    return
      _stakeToInput(
        IERC20Metadata(inputs[_index]).balanceOf(address(this)) +
          IERC20Metadata(inputs[_index]).balanceOf(dummyVault),
        _index
      );
  }
}

contract StrategyV5CompositeSimulator is StrategyV5Composite, Simulator {
  Vm internal vm;

  constructor(
    address _accessController,
    Vm _vm
  ) StrategyV5Composite(_accessController) {
    vm = _vm;
  }

  function simulate(
    bytes calldata _data
  ) external returns (bytes memory response) {
    return Simulator.simulate(address(this), _data);
  }
}
