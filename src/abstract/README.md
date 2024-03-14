# StrategyV5 on-chain Architecture

Core abstract contracts
- [As4626.sol](./src/abstract/As4626.sol) (full-featured tokenized vault ERC4626/ERC7540 hybrid implementation)
- [StrategyV5.sol](./src/abstract/StrategyV5.sol) (base strategy contract, extended by all strategies, transparent proxy delegating to StrategyV5Agent)
- [StrategyV5Agent.sol](./src/abstract/StrategyV5Agent.sol) (shared strategy logic, implementation inheriting from As4626)
- Add-ons
  - [StrategyV5Chainlink.sol](./src/abstract/StrategyV5Chainlink.sol)
  - [StrategyV5Pyth.sol](./src/abstract/StrategyV5Pyth.sol)

## Agent delegate calls (ERC-897 transparent proxy)

`StrategyV5` is a transparent proxy that delegates to `StrategyV5Agent`, this is done to minimize redundancy and lighten the strategies deployment size.
`StrategyV5Agent` acts as a common back-end for accounting and generic 4626/Strategy workload.

When a function of `StrategyV5` is called, it will either execute its logic on the specific `StrategyV5` implementation or default to a delegatecall to `StrategyV5Agent`. If none of the contracts implements the function signature, the call will revert.
The delegate nature of a `StrategyV5Agent` call, means it always uses the storage slots of the caller `StrategyV5`, hence does not need to be initialized, nor stateful.

```
╭────────────────╮       ╭──────────────────────╮
|  StrategyV5    |       |  StrategyV5Agent     |
| (Transparent   |──────>|  (Shared Logic &     |
|  Proxy)        |       |   ERC4626 Vault)     |
╰────────────────╯       ╰──────────────────────╯
```

## Partial immutability

As per the above, `StrategyV5` implementations are immutable, ensuring future integrity of critical tasks such as
- role management
- asset rescue
- pausability logic
- third party protocol integration

While `StrategyV5Agent` remains upgradable, allowing Astrolab DAO to fix generic protocol mechanisms such as
- accounting of profits
- calculation of a strategy share price
- ERC4626 implementation
- ERC7540 implementation

And even add features to already deployed Strategies such as
- ERC3156 flash lending
- incentives management
- compatibility with future standards

This architecture offers a scalable, secure, and efficient framework, suiting our DeFi aggregation well and designed for easy expansion.

## Storage layout

The above transparent proxy architecture means that storage slots of the two contracts must be identical at runtime.

### Abstract inheritance-defined storage

The following contract hierarchy dictates the storage layout, which must remain compatible between a `StrategyV5` revision and its `StrategyV5Agent` back-end.

```
StrategyV5 (54 slots)
├───┬─── AsManageable.sol (4 slots)
|   ├─── ReentrancyGuard.sol (1 slot)
|   ├─── Pausable.sol (1 slot)
|   ╰─── AccessController.sol (1 slot)
|       ╰─── AccessControllerAbstract (1 slot)
├─── AsProxy.sol (0 slot)
├─── ERC20Abstract (3 slots)
├─── As4626Abstract (24 slots)
├─── AsRescuable (1 slot)
|   ╰─── AsRescuableAbstract (1 slot)
╰─── StrategyV5Abstract (22 slots)

StrategyV5Agent (54 slots)
├─── As4626.sol (31 slots)
|   ├─── AsManageableAbstract.sol (4 slots)
|   |   ├─── AccessControllerAbstract.sol (1 slot)
|   |   ╰─── ERC20 (3 slots)
|   |       ╰─── ERC20Abstract (3 slots)
|   ╰─── As4626Abstract.sol (24 slots)
├─── AsRescuableAbstract (1 slot)
╰─── StrategyV5Abstract (22 slots)
```

### Table view

Here is a table view of the above described sequential storage layout

| Slots | Variable | StrategyV5 inheritance | StrategyV5Agent inheritance |
| --- | --- | --- | --- |
| 0 | IWETH9 _wgas | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 1 | ISwapper swapper | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 2 | IStrategyV5 agent | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 3->10| IERC20Metadata[8] inputs | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 11 | uint8[8] _inputDecimals | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 12 | uint16[8] inputWeights | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 13->20 | address[8] rewardTokens | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 21 | mapping _rewardTokenIndexes | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 22 | uint8 _inputLength | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 22 | uint8 _rewardLength | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 23 | uint256 maxTotalAssets | As4626Abstract.sol | As4626.sol |
| 24 | uint256 minLiquidity | As4626Abstract.sol | As4626.sol |
| 25 | IERC20Metadata asset | As4626Abstract.sol | As4626.sol |
| 25 | uint8 _assetDecimals | As4626Abstract.sol | As4626.sol |
| 26 | uint256 _weiPerAsset | As4626Abstract.sol | As4626.sol |
| 27->32 | Epoch last | As4626Abstract.sol | As4626.sol |
| 33 | uint256 _profitCooldown | As4626Abstract.sol | As4626.sol |
| 34 | uint256 _expectedProfits | As4626Abstract.sol | As4626.sol |
| 35->36 | Fees fees | As4626Abstract.sol | As4626.sol |
| 37 | address feeCollector | As4626Abstract.sol | As4626.sol |
| 38 | uint256 claimableAssetFees | As4626Abstract.sol | As4626.sol |
| 39 | mapping exemptionList | As4626Abstract.sol | As4626.sol |
| 40->44 | Requests _req | As4626Abstract.sol | As4626.sol |
| 45 | uint256 _requestId | As4626Abstract.sol | As4626.sol |
| 46 | string name | ERC20Abstract.sol | ERC20.sol |
| 47 | string symbol | ERC20Abstract.sol | ERC20.sol |
| 48 | uint8 decimals | ERC20Abstract.sol | ERC20.sol |
| 48 | bool _initialized | ERC20Abstract.sol | ERC20.sol |
| 49 | mapping _roles | AccessController.sol | AsManageableAbstract.sol |
| 50 | bool private _paused | Pausable.sol | AsManageableAbstract.sol |
| 51 | uint256 _status | ReentrancyGuard.sol | AsManageableAbstract.sol |
| 52 | mapping pendingAcceptance | AsManageable.sol | AsManageableAbstract.sol |
| 53 | mapping _rescueRequests | AsRescuable.sol | AsRescuableAbstract.sol |

#### A strategy's storage compliance can be ensured using forge storage slots inspector:

```bash
$> forge inspect --pretty CompoundV3MultiStake storage-layout`
```

| Name                | Type                                                | Slot | Offset | Bytes | Contract                   |
|---------------------|-----------------------------------------------------|------|--------|-------|----------------------------|
| _wgas               | contract IWETH9                                     | 0    | 0      | 20    | ./CompoundV3MultiStake.sol |
| swapper             | contract ISwapper                                   | 1    | 0      | 20    | ./CompoundV3MultiStake.sol |
| agent               | contract IStrategyV5                                | 2    | 0      | 20    | ./CompoundV3MultiStake.sol |
| inputs              | contract IERC20Metadata[8]                          | 3    | 0      | 256   | ./CompoundV3MultiStake.sol |
| _inputDecimals      | uint8[8]                                            | 11   | 0      | 32    | ./CompoundV3MultiStake.sol |
| inputWeights        | uint16[8]                                           | 12   | 0      | 32    | ./CompoundV3MultiStake.sol |
| rewardTokens        | address[8]                                          | 13   | 0      | 256   | ./CompoundV3MultiStake.sol |
| _rewardTokenIndexes | mapping(address => uint256)                         | 21   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _inputLength        | uint8                                               | 22   | 0      | 1     | ./CompoundV3MultiStake.sol |
| _rewardLength       | uint8                                               | 22   | 1      | 1     | ./CompoundV3MultiStake.sol |
| maxTotalAssets      | uint256                                             | 23   | 0      | 32    | ./CompoundV3MultiStake.sol |
| minLiquidity        | uint256                                             | 24   | 0      | 32    | ./CompoundV3MultiStake.sol |
| asset               | contract IERC20Metadata                             | 25   | 0      | 20    | ./CompoundV3MultiStake.sol |
| _assetDecimals      | uint8                                               | 25   | 20     | 1     | ./CompoundV3MultiStake.sol |
| _weiPerAsset        | uint256                                             | 26   | 0      | 32    | ./CompoundV3MultiStake.sol |
| last                | struct Epoch                                        | 27   | 0      | 192   | ./CompoundV3MultiStake.sol |
| _profitCooldown     | uint256                                             | 33   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _expectedProfits    | uint256                                             | 34   | 0      | 32    | ./CompoundV3MultiStake.sol |
| fees                | struct Fees                                         | 35   | 0      | 64    | ./CompoundV3MultiStake.sol |
| feeCollector        | address                                             | 37   | 0      | 20    | ./CompoundV3MultiStake.sol |
| claimableAssetFees  | uint256                                             | 38   | 0      | 32    | ./CompoundV3MultiStake.sol |
| exemptionList       | mapping(address => bool)                            | 39   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _req                | struct Requests                                     | 40   | 0      | 160   | ./CompoundV3MultiStake.sol |
| _requestId          | uint256                                             | 45   | 0      | 32    | ./CompoundV3MultiStake.sol |
| name                | string                                              | 46   | 0      | 32    | ./CompoundV3MultiStake.sol |
| symbol              | string                                              | 47   | 0      | 32    | ./CompoundV3MultiStake.sol |
| decimals            | uint8                                               | 48   | 0      | 1     | ./CompoundV3MultiStake.sol |
| _initialized        | bool                                                | 48   | 1      | 1     | ./CompoundV3MultiStake.sol |
| _roles              | mapping(bytes32 => struct RoleState)                | 49   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _paused             | bool                                                | 50   | 0      | 1     | ./CompoundV3MultiStake.sol |
| _status             | uint256                                             | 51   | 0      | 32    | ./CompoundV3MultiStake.sol |
| pendingAcceptance   | mapping(address => struct PendingAcceptance)        | 52   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _rescueRequests     | mapping(address => struct RescueRequest)            | 53   | 0      | 32    | ./CompoundV3MultiStake.sol |
| feedByAsset         | mapping(address => contract IChainlinkAggregatorV3) | 54   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _decimalsByFeed     | mapping(contract IChainlinkAggregatorV3 => uint8)   | 55   | 0      | 32    | ./CompoundV3MultiStake.sol |
| validityByFeed      | mapping(contract IChainlinkAggregatorV3 => uint256) | 56   | 0      | 32    | ./CompoundV3MultiStake.sol |
| cTokens             | address[8]                                          | 57   | 0      | 256   | ./CompoundV3MultiStake.sol |
| _cometRewards       | contract ICometRewards                              | 65   | 0      | 20    | ./CompoundV3MultiStake.sol |
| _rewardConfigs      | struct ICometRewards.RewardConfig[8]                | 66   | 0      | 512   | ./CompoundV3MultiStake.sol |
