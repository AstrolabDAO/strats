// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {StrategyV5} from "../abstract/StrategyV5.sol";
import {Simulator} from "../abstract/Simulator.sol";

contract StrategyV5Simulator is StrategyV5, Simulator {
  constructor(address _accessController) StrategyV5(_accessController) {}

  /**
   * @dev Simulates a delegate call to a target contract in the context of self
   * Internally reverts execution to avoid side effects (making it static)
   * Catches revert and returns encoded result as bytes
   * @param _data Calldata that should be sent to the target contract (encoded method name and arguments)
   */
  function simulate(bytes calldata _data) external returns (bytes memory response) {
    return Simulator.simulate(address(this), _data);
  }
}
