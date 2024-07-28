// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/abstract/StrategyV5.sol";
import "../../src/abstract/StrategyV5Composite.sol";
import "../../src/abstract/Simulator.sol";
import "../../src/libs/AsArrays.sol";
import "../../src/libs/AsMaths.sol";

contract Dummy {}

contract StrategyV5Simulator is StrategyV5, Simulator {
  using SafeERC20 for IERC20Metadata;
  using AsMaths for *;
  using AsArrays for *;

  Vm internal vm;
  address internal dummyVault = address(new Dummy());
  address internal dummyRewardDistributor = address(new Dummy());

  constructor(address _accessController, Vm _vm) StrategyV5(_accessController) {
    vm = _vm;
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
    // use 10% of the amount to fake rewards
    (uint256 fakeStake, uint256 fakeReward) = (_amount.subBp(1000), _amount.bp(1000));
    inputs[_index].forceApprove(dummyVault, fakeStake);
    inputs[_index].safeTransfer(dummyVault, fakeStake);
    inputs[_index].forceApprove(dummyRewardDistributor, fakeReward);
    inputs[_index].safeTransfer(dummyRewardDistributor, fakeReward);
  }

  function _unstake(uint256 _index, uint256 _amount) internal override {
    vm.prank(dummyVault);
    inputs[_index].forceApprove(address(this), _amount);
    vm.prank(dummyVault);
    inputs[_index].safeTransfer(address(this), _amount);
  }

  function _claimRewards() internal override returns (uint256[] memory) {
    // in this simplistic simulation, rewardTokens[0] == inputs[0]
    uint256 fakeReward = inputs[0].balanceOf(dummyRewardDistributor); // charlie's balance
    vm.prank(dummyRewardDistributor);
    inputs[0].forceApprove(address(this), fakeReward);
    vm.prank(dummyRewardDistributor);
    inputs[0].safeTransfer(address(this), fakeReward);
    return fakeReward.toArray();
  }

  function rewardsAvailable() public view override returns (uint256[] memory) {
    return inputs[0].balanceOf(dummyRewardDistributor).toArray(); // charlie's balance
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
