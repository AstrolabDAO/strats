// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/interfaces/ISwapper.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IWETH9.sol";
import "./As4626Abstract.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title As4626Abstract - inherited by all strategies
 * @author Astrolab DAO
 * @notice All As4626 calls are delegated to the agent (StrategyV5Agent)
 * @dev Make sure all As4626 state variables here to match proxy/implementation slots
 */
abstract contract StrategyV5Abstract is As4626Abstract {

    // Events
    event Invest(uint256 amount, uint256 timestamp);
    event Harvest(uint256 amount, uint256 timestamp);
    event Liquidate(
        uint256 amount,
        uint256 liquidityAvailable,
        uint256 timestamp
    );

    // Errors
    error InvalidOrStaleValue(uint256 updateTime, int256 value);

    // State variables (As4626 extension)
    IWETH9 public wgas; // gas/native wrapper contract
    ISwapper public swapper; // interface for swapping assets
    address public agent; // address of the agent
    address internal stratProxy; // address of the strategy proxy

    IERC20Metadata[8] public inputs; // array of ERC20 tokens used as inputs
    uint8[8] internal inputDecimals; // strategy inputs decimals
    uint16[8] public inputWeights; // array of input weights weights in basis points (100% = 100_00)
    address[8] public rewardTokens; // array of reward tokens harvested at compound and liquidate times
    mapping(address => uint256) internal rewardTokenIndexes; // reward token index by address
    uint8 internal inputLength; // used length of inputs[] (index of last non-zero element)
    uint8 internal rewardLength; // used length of rewardTokens[] (index of last non-zero element)

    constructor() As4626Abstract() {}

    /**
     * @notice Calculates the total pending redemption requests in shares
     * @dev Returns the difference between _req.totalRedemption and _req.totalClaimableRedemption
     * @return The total amount of pending redemption requests
     */
    function totalPendingRedemptionRequest() public view returns (uint256) {
        return _req.totalRedemption - _req.totalClaimableRedemption;
    }

    /**
     * @notice Calculates the total pending asset requests based on redemption requests
     * @dev Converts the total pending redemption requests to their asset asset value for precision
     * @return The total amount of asset assets requested pending redemption
     */
    function totalPendingAssetRequest() public view returns (uint256) {
        return convertToAssets(totalPendingRedemptionRequest(), false);
    }
}
