// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICurvePool {
  // Events
  event TokenExchange(
    address indexed buyer,
    uint256 sold_id,
    uint256 tokens_sold,
    uint256 bought_id,
    uint256 tokens_bought
  );
  event AddLiquidity(
    address indexed provider,
    uint256[3] token_amounts,
    uint256 fee,
    uint256 token_supply
  );
  event RemoveLiquidity(
    address indexed provider,
    uint256[3] token_amounts,
    uint256 token_supply
  );
  event RemoveLiquidityOne(
    address indexed provider,
    uint256 token_amount,
    uint256 coin_index,
    uint256 coin_amount
  );
  event CommitNewAdmin(uint256 indexed deadline, address indexed admin);
  event NewAdmin(address indexed admin);
  event CommitNewParameters(
    uint256 indexed deadline,
    uint256 admin_fee,
    uint256 mid_fee,
    uint256 out_fee,
    uint256 fee_gamma,
    uint256 allowed_extra_profit,
    uint256 adjustment_step,
    uint256 ma_half_time
  );
  event NewParameters(
    uint256 admin_fee,
    uint256 mid_fee,
    uint256 out_fee,
    uint256 fee_gamma,
    uint256 allowed_extra_profit,
    uint256 adjustment_step,
    uint256 ma_half_time
  );
  event RampAgamma(
    uint256 initial_A,
    uint256 future_A,
    uint256 initial_gamma,
    uint256 future_gamma,
    uint256 initial_time,
    uint256 future_time
  );
  event StopRampA(uint256 current_A, uint256 current_gamma, uint256 time);
  event ClaimAdminFee(address indexed admin, uint256 tokens);

  // View Functions
  function A() external view returns (uint256);

  function gamma() external view returns (uint256);

  function fee() external view returns (uint256);

  function get_virtual_price() external view returns (uint256);

  function calc_token_fee(
    uint256[3] calldata amounts,
    uint256[3] calldata xp
  ) external view returns (uint256);

  function calc_token_amount(
    uint256[3] calldata amounts,
    bool deposit
  ) external view returns (uint256);

  function calc_withdraw_one_coin(
    uint256 token_amount,
    uint256 i
  ) external view returns (uint256);

  function get_dy(
    uint256 i,
    uint256 j,
    uint256 dx
  ) external view returns (uint256);

  function coins(uint256 i) external view returns (address);

  function fee_calc(uint256[3] calldata xp) external view returns (uint256);

  // State-Changing Functions
  function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external;

  function add_liquidity(
    uint256[3] calldata amounts,
    uint256 min_mint_amount
  ) external;

  function remove_liquidity(
    uint256 _amount,
    uint256[3] calldata min_amounts
  ) external;

  function remove_liquidity_one_coin(
    uint256 token_amount,
    uint256 i,
    uint256 min_amount
  ) external;

  function claim_admin_fees() external;

  // Admin Functions
  function ramp_A_gamma(
    uint256 future_A,
    uint256 future_gamma,
    uint256 future_time
  ) external;

  function stop_ramp_A_gamma() external;

  function commit_new_parameters(
    uint256 _new_mid_fee,
    uint256 _new_out_fee,
    uint256 _new_admin_fee,
    uint256 _new_fee_gamma,
    uint256 _new_allowed_extra_profit,
    uint256 _new_adjustment_step,
    uint256 _new_ma_half_time
  ) external;

  function apply_new_parameters() external;

  function revert_new_parameters() external;

  function commit_transfer_ownership(address _owner) external;

  function apply_transfer_ownership() external;

  function revert_transfer_ownership() external;

  function kill_me() external;

  function unkill_me() external;

  function set_reward_receiver(address _reward_receiver) external;

  function set_admin_fee_receiver(address _admin_fee_receiver) external;

  // Additional View Functions
  function price_oracle(uint256 k) external view returns (uint256);

  function price_scale(uint256 k) external view returns (uint256);

  function last_prices(uint256 k) external view returns (uint256);

  function token() external view returns (address);

  function future_A_gamma_time() external view returns (uint256);

  function initial_A_gamma() external view returns (uint256);

  function future_A_gamma() external view returns (uint256);

  function initial_A_gamma_time() external view returns (uint256);

  function allowed_extra_profit() external view returns (uint256);

  function future_allowed_extra_profit() external view returns (uint256);

  function fee_gamma() external view returns (uint256);

  function future_fee_gamma() external view returns (uint256);

  function adjustment_step() external view returns (uint256);

  function future_adjustment_step() external view returns (uint256);

  function ma_half_time() external view returns (uint256);

  function future_ma_half_time() external view returns (uint256);

  function mid_fee() external view returns (uint256);

  function out_fee() external view returns (uint256);

  function admin_fee() external view returns (uint256);

  function future_mid_fee() external view returns (uint256);

  function future_out_fee() external view returns (uint256);

  function future_admin_fee() external view returns (uint256);

  function balances(uint256 i) external view returns (uint256);

  function D() external view returns (uint256);

  function owner() external view returns (address);

  function future_owner() external view returns (address);

  function xcp_profit() external view returns (uint256);

  function xcp_profit_a() external view returns (uint256);

  function virtual_price() external view returns (uint256);

  function is_killed() external view returns (bool);

  function kill_deadline() external view returns (uint256);

  function transfer_ownership_deadline() external view returns (uint256);

  function admin_actions_deadline() external view returns (uint256);

  function reward_receiver() external view returns (address);

  function admin_fee_receiver() external view returns (address);
}
