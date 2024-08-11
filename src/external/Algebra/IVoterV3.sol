// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IVoterV3 {
  // Events
  event Abstained(uint256 tokenId, uint256 weight);
  event Attach(address indexed owner, address indexed gauge, uint256 tokenId);
  event Blacklisted(address indexed blacklister, address indexed token);
  event Detach(address indexed owner, address indexed gauge, uint256 tokenId);
  event DistributeReward(
    address indexed sender,
    address indexed gauge,
    uint256 amount
  );
  event GaugeCreated(
    address indexed gauge,
    address creator,
    address internal_bribe,
    address indexed external_bribe,
    address indexed pool
  );
  event GaugeKilled(address indexed gauge);
  event GaugeRevived(address indexed gauge);
  event Initialized(uint8 version);
  event NotifyReward(
    address indexed sender,
    address indexed reward,
    uint256 amount
  );
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );
  event Voted(address indexed voter, uint256 tokenId, uint256 weight);
  event Whitelisted(address indexed whitelister, address indexed token);

  // Constants (From the ABI)
  function MAX_VOTE_DELAY() external view returns (uint256);

  function VOTE_DELAY() external view returns (uint256);

  // View Functions
  function _epochTimestamp() external view returns (uint256);

  function _factories() external view returns (address[] memory);

  function _gaugeFactories() external view returns (address[] memory);

  function _ve() external view returns (address);

  function bribfactory() external view returns (address);

  function claimable(address) external view returns (uint256);

  function external_bribes(address) external view returns (address);

  function factories(uint256) external view returns (address);

  function factory() external view returns (address);

  function factoryLength() external view returns (uint256);

  function gaugeFactories(uint256) external view returns (address);

  function gaugeFactoriesLength() external view returns (uint256);

  function gaugefactory() external view returns (address);

  function gauges(address) external view returns (address);

  function gaugesDistributionTimestmap(address) external view returns (uint256);

  function internal_bribes(address) external view returns (address);

  function isAlive(address) external view returns (bool);

  function isFactory(address) external view returns (bool);

  function isGauge(address) external view returns (bool);

  function isGaugeFactory(address) external view returns (bool);

  function isWhitelisted(address) external view returns (bool);

  function lastVoted(uint256) external view returns (uint256);

  function length() external view returns (uint256);

  function minter() external view returns (address);

  function owner() external view returns (address);

  function permissionRegistry() external view returns (address);

  function poolForGauge(address) external view returns (address);

  function poolVote(uint256, uint256) external view returns (address);

  function poolVoteLength(uint256 tokenId) external view returns (uint256);

  function pools(uint256) external view returns (address);

  function totalWeight() external view returns (uint256);

  function totalWeightAt(uint256 _time) external view returns (uint256);

  function usedWeights(uint256) external view returns (uint256);

  function votes(uint256, address) external view returns (uint256);

  function weights(address _pool) external view returns (uint256);

  function weightsAt(
    address _pool,
    uint256 _time
  ) external view returns (uint256);

  // State-Changing Functions
  function _init(
    address[] memory _tokens,
    address _permissionsRegistry,
    address _minter
  ) external;

  function addFactory(address _pairFactory, address _gaugeFactory) external;

  function attachTokenToGauge(uint256 tokenId, address account) external;

  function blacklist(address[] memory _token) external;

  function claimBribes(
    address[] memory _bribes,
    address[][] memory _tokens,
    uint256 _tokenId
  ) external;

  function claimBribes(
    address[] memory _bribes,
    address[][] memory _tokens
  ) external;

  function claimFees(
    address[] memory _fees,
    address[][] memory _tokens,
    uint256 _tokenId
  ) external;

  function claimFees(
    address[] memory _bribes,
    address[][] memory _tokens
  ) external;

  function claimRewards(address[] memory _gauges) external;

  function createGauge(
    address _pool,
    uint256 _gaugeType
  )
    external
    returns (address _gauge, address _internal_bribe, address _external_bribe);

  function createGauges(
    address[] memory _pool,
    uint256[] memory _gaugeTypes
  ) external returns (address[] memory, address[] memory, address[] memory);

  function detachTokenFromGauge(uint256 tokenId, address account) external;

  function distribute(address[] memory _gauges) external;

  function distribute(uint256 start, uint256 finish) external;

  function distributeAll() external;

  function distributeFees(address[] memory _gauges) external;

  function forceResetTo(uint256 _tokenId) external;

  function increaseGaugeApprovals(address _gauge) external;

  function initialize(
    address __ve,
    address _factory,
    address _gauges,
    address _bribes
  ) external;

  function killGauge(address _gauge) external;

  function killGaugeTotally(address _gauge) external;

  function notifyRewardAmount(uint256 amount) external;

  function poke(uint256 _tokenId) external;

  function removeFactory(uint256 _pos) external;

  function renounceOwnership() external;

  function replaceFactory(
    address _pairFactory,
    address _gaugeFactory,
    uint256 _pos
  ) external;

  function reset(uint256 _tokenId) external;

  function reviveGauge(address _gauge) external;

  function setBribeFactory(address _bribeFactory) external;

  function setExternalBribeFor(address _gauge, address _external) external;

  function setGaugeFactory(address _gaugeFactory) external;

  function setInternalBribeFor(address _gauge, address _internal) external;

  function setMinter(address _minter) external;

  function setNewBribes(
    address _gauge,
    address _internal,
    address _external
  ) external;

  function setPairFactory(address _factory) external;

  function setPermissionsRegistry(address _permissionRegistry) external;

  function setVoteDelay(uint256 _delay) external;

  function transferOwnership(address newOwner) external;

  function vote(
    uint256 _tokenId,
    address[] memory _poolVote,
    uint256[] memory _weights
  ) external;

  function whitelist(address[] memory _token) external;
}
