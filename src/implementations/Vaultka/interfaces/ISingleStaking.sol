// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface ISingleStaking {
    // Structs
    struct PoolInfo {
        IERC20Upgradeable lpToken;
        uint256 allocPoint;
        uint256 lastRewardTimestamp;
        uint256 accesVKAPerShare;
        uint256 totalBoostedShare;
        IRewardPerSec rewarder;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 boostMultiplier;
    }

    // Events
    event Add(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20Upgradeable indexed lpToken,
        IRewardPerSec indexed rewarder
    );
    event Set(
        uint256 indexed pid,
        uint256 allocPoint,
        IRewardPerSec indexed rewarder,
        bool overwrite
    );
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(
        uint256 indexed pid,
        uint256 lastRewardTimestamp,
        uint256 lpSupply,
        uint256 accesVKAPerShare
    );
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event UpdateEmissionRate(address indexed user, uint256 _esVKAPerSec);
    event UpdateBoostMultiplier(
        address indexed user,
        uint256 indexed pid,
        uint256 oldMultiplier,
        uint256 newMultiplier
    );
    event MissingTokenRecovered(address indexed user, uint256 amount);
    event SetTreasuryAddress(address indexed newAddress);

    // Functions
    function initialize(
        IERC20Upgradeable _esVKAToken,
        IBoosting _boosting,
        uint256 _esVKAPerSec,
        uint256 _startTimestamp
    ) external;

    function setLeverageVault(address _vault, bool _isLeverageVault) external;

    function recoverMissingToken() external;

    function add(
        uint256 _allocPoint,
        IERC20Upgradeable _lpToken,
        IRewardPerSec _rewarder
    ) external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewardPerSec _rewarder,
        bool overwrite
    ) external;

    function resetAccEs(uint256 _pid1, uint256 _pid2) external;

    function resetUserDebt(
        uint256 _pid,
        address[] calldata _users,
        uint256[] calldata _pendings
    ) external;

    function claimAll() external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function updateEmissionRate(uint256 _esVKAPerSec) external;

    function updateBoostMultiplier(
        address _user,
        uint256 _pid
    ) external returns (uint256 _newMultiplier);

    function getPoolTokenBalance(uint256 _pid) external view returns (uint256);

    function poolLength() external view returns (uint256);

    function getPoolTokenAddress(uint256 _pid) external view returns (address);

    function pendingTokens(
        uint256 _pid,
        address _user
    )
        external
        view
        returns (
            uint256 pendingesVKA,
            address bonusTokenAddress,
            uint256 pendingBonusToken
        );

    function massUpdatePools() external;

    function updatePool(uint256 _pid) external returns (PoolInfo memory pool);

    function unstakeAndLiquidate(
        uint256 _pid,
        address _user,
        uint256 _amount
    ) external;

    function getUserAmount(
        uint256 _pid,
        address _user
    ) external view returns (uint256);

    function rewarderBonusTokenInfo(
        uint256 _pid
    ) external view returns (address bonusTokenAddress);

    function getBoostMultiplier(
        address _user,
        uint256 _pid
    ) external view returns (uint256);

    function withdrawAllESVKA() external;
}

interface IBoosting {
    function getBoostMultiplier(
        address _user,
        uint256 _pid
    ) external view returns (uint256 BoostMultiplier);

    function getBoostMultiplierWithDeposit(
        address _user,
        uint256 _pid,
        uint256 _amount
    ) external view returns (uint256 BoostMultiplier);

    function getBoostMultiplierWithWithdrawal(
        address _user,
        uint256 _pid,
        uint256 _amount
    ) external view returns (uint256 BoostMultiplier);
}

interface IRewardPerSec {
    function onesVKAReward(address user, uint256 newLpAmount) external;

    function pendingTokens(
        address user
    ) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}
