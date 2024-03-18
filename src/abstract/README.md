# StrategyV5 on-chain Architecture

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
StrategyV5 (57 slots total)
├─── AsManageable.sol (0 slot, 2 slots total)
|   ├─── ReentrancyGuard.sol (1 slot)
|   ├─── Pausable.sol (1 slot)
|   ╰─── AsPermissioned.sol (0 slot)
├─── AsRescuable (0 slot)
├─── StrategyV5Abstract (30 slots, 55 slots total)
|   ╰─── As4626Abstract (22 slots, 25 slots total)
|       ╰─── ERC20Abstract (3 slots)
╰─── AsPriceAware.sol (0 slot)

StrategyV5Agent (57 slots total)
╰─── StrategyV5Abstract (30 slots, 57 slots total)
|   ╰─── As4626Abstract (22 slots, 27 slots total)
|       ├─── ERC20Abstract (3 slots, 5 slots total)
|       ╰─── AsManageable.sol (0 slot, 2 slots total)
|           ├─── ReentrancyGuard.sol (1 slot)
|           ├─── Pausable.sol (1 slot)
|           ╰─── AsPermissioned.sol (0 slot)
╰─── AsFlashLender.sol (0 slot)
```

### Table view

Here is a table view of the above described sequential storage layout

| Name                | Type                        | Slot | Offset | Bytes |
|---------------------|-----------------------------|------|--------|-------|
| name                | string                      | 0    | 0      | 32    |
| symbol              | string                      | 1    | 0      | 32    |
| decimals            | uint8                       | 2    | 0      | 1     |
| _initialized        | bool                        | 2    | 1      | 1     |
| _paused             | bool                        | 2    | 2      | 1     |
| _status             | uint256                     | 3    | 0      | 32    |
| maxTotalAssets      | uint256                     | 4    | 0      | 32    |
| minLiquidity        | uint256                     | 5    | 0      | 32    |
| asset               | contract IERC20Metadata     | 6    | 0      | 20    |
| _assetDecimals      | uint8                       | 6    | 20     | 1     |
| _weiPerAsset        | uint256                     | 7    | 0      | 32    |
| last                | struct Epoch                | 8    | 0      | 192   |
| _profitCooldown     | uint256                     | 14   | 0      | 32    |
| _expectedProfits    | uint256                     | 15   | 0      | 32    |
| fees                | struct Fees                 | 16   | 0      | 64    |
| feeCollector        | address                     | 18   | 0      | 20    |
| claimableAssetFees  | uint256                     | 19   | 0      | 32    |
| exemptionList       | mapping(address => bool)    | 20   | 0      | 32    |
| _req                | struct Requests             | 21   | 0      | 160   |
| _requestId          | uint256                     | 26   | 0      | 32    |
| _wgas               | contract IWETH9             | 27   | 0      | 20    |
| swapper             | contract ISwapper           | 28   | 0      | 20    |
| inputs              | contract IERC20Metadata[8]  | 29   | 0      | 256   |
| _inputDecimals      | uint8[8]                    | 37   | 0      | 32    |
| inputWeights        | uint16[8]                   | 38   | 0      | 32    |
| lpTokens            | contract IERC20Metadata[8]  | 39   | 0      | 256   |
| _lpTokenDecimals    | uint8[8]                    | 47   | 0      | 32    |
| rewardTokens        | address[8]                  | 48   | 0      | 256   |
| _rewardTokenIndexes | mapping(address => uint256) | 56   | 0      | 32    |
| _inputLength        | uint8                       | 57   | 0      | 1     |
| _rewardLength       | uint8                       | 57   | 1      | 1     |

#### The above storage layout and compliance can be checked using forge storage slots inspector

```bash
$> forge inspect --pretty CompoundV3MultiStake storage-layout`
```

| Name                | Type                                 | Slot | Offset | Bytes | Contract                   |
|---------------------|--------------------------------------|------|--------|-------|----------------------------|
| name                | string                               | 0    | 0      | 32    | ./CompoundV3MultiStake.sol |
| symbol              | string                               | 1    | 0      | 32    | ./CompoundV3MultiStake.sol |
| decimals            | uint8                                | 2    | 0      | 1     | ./CompoundV3MultiStake.sol |
| _initialized        | bool                                 | 2    | 1      | 1     | ./CompoundV3MultiStake.sol |
| _paused             | bool                                 | 2    | 2      | 1     | ./CompoundV3MultiStake.sol |
| _status             | uint256                              | 3    | 0      | 32    | ./CompoundV3MultiStake.sol |
| maxTotalAssets      | uint256                              | 4    | 0      | 32    | ./CompoundV3MultiStake.sol |
| minLiquidity        | uint256                              | 5    | 0      | 32    | ./CompoundV3MultiStake.sol |
| asset               | contract IERC20Metadata              | 6    | 0      | 20    | ./CompoundV3MultiStake.sol |
| _assetDecimals      | uint8                                | 6    | 20     | 1     | ./CompoundV3MultiStake.sol |
| _weiPerAsset        | uint256                              | 7    | 0      | 32    | ./CompoundV3MultiStake.sol |
| last                | struct Epoch                         | 8    | 0      | 192   | ./CompoundV3MultiStake.sol |
| _profitCooldown     | uint256                              | 14   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _expectedProfits    | uint256                              | 15   | 0      | 32    | ./CompoundV3MultiStake.sol |
| fees                | struct Fees                          | 16   | 0      | 64    | ./CompoundV3MultiStake.sol |
| feeCollector        | address                              | 18   | 0      | 20    | ./CompoundV3MultiStake.sol |
| claimableAssetFees  | uint256                              | 19   | 0      | 32    | ./CompoundV3MultiStake.sol |
| exemptionList       | mapping(address => bool)             | 20   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _req                | struct Requests                      | 21   | 0      | 160   | ./CompoundV3MultiStake.sol |
| _requestId          | uint256                              | 26   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _wgas               | contract IWETH9                      | 27   | 0      | 20    | ./CompoundV3MultiStake.sol |
| swapper             | contract ISwapper                    | 28   | 0      | 20    | ./CompoundV3MultiStake.sol |
| inputs              | contract IERC20Metadata[8]           | 29   | 0      | 256   | ./CompoundV3MultiStake.sol |
| _inputDecimals      | uint8[8]                             | 37   | 0      | 32    | ./CompoundV3MultiStake.sol |
| inputWeights        | uint16[8]                            | 38   | 0      | 32    | ./CompoundV3MultiStake.sol |
| lpTokens            | contract IERC20Metadata[8]           | 39   | 0      | 256   | ./CompoundV3MultiStake.sol |
| _lpTokenDecimals    | uint8[8]                             | 47   | 0      | 32    | ./CompoundV3MultiStake.sol |
| rewardTokens        | address[8]                           | 48   | 0      | 256   | ./CompoundV3MultiStake.sol |
| _rewardTokenIndexes | mapping(address => uint256)          | 56   | 0      | 32    | ./CompoundV3MultiStake.sol |
| _inputLength        | uint8                                | 57   | 0      | 1     | ./CompoundV3MultiStake.sol |
| _rewardLength       | uint8                                | 57   | 1      | 1     | ./CompoundV3MultiStake.sol |
| _rewardController   | contract ICometRewards               | 57   | 2      | 20    | ./CompoundV3MultiStake.sol |
| _rewardConfigs      | struct ICometRewards.RewardConfig[8] | 58   | 0      | 512   | ./CompoundV3MultiStake.sol |

### Alternatively, [hardhat-storage-layout](https://github.com/aurora-is-near/hardhat-storage-layout) is just as good

```bash
$> yarn hardhat check
```

| contract         | state_variable    | storage_slot | offset | type                                           | idx | artifact               | numberOfBytes |
|------------------|-------------------|--------------|--------|------------------------------------------------|-----|------------------------|---------------|
| AaveV3MultiStake   | name              | 0            | 0      | t_string_storage                               | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | symbol            | 1            | 0      | t_string_storage                               | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | decimals          | 2            | 0      | t_uint8                                        | 0   | /build-info/xxx.json   | 1             |
| AaveV3MultiStake   | _initialized      | 2            | 1      | t_bool                                         | 0   | /build-info/xxx.json   | 1             |
| AaveV3MultiStake   | _paused           | 2            | 2      | t_bool                                         | 0   | /build-info/xxx.json   | 1             |
| AaveV3MultiStake   | _status           | 3            | 0      | t_uint256                                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | maxTotalAssets    | 4            | 0      | t_uint256                                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | minLiquidity      | 5            | 0      | t_uint256                                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | asset             | 6            | 0      | t_contract(IERC20Metadata)495                  | 0   | /build-info/xxx.json   | 20            |
| AaveV3MultiStake   | _assetDecimals    | 6            | 20     | t_uint8                                        | 0   | /build-info/xxx.json   | 1             |
| AaveV3MultiStake   | _weiPerAsset      | 7            | 0      | t_uint256                                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | last              | 8            | 0      | t_struct(Epoch)5391_storage                    | 0   | /build-info/xxx.json   | 192           |
| AaveV3MultiStake   | _profitCooldown   | 14           | 0      | t_uint256                                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | _expectedProfits  | 15           | 0      | t_uint256                                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | fees              | 16           | 0      | t_struct(Fees)5303_storage                     | 0   | /build-info/xxx.json   | 64            |
| AaveV3MultiStake   | feeCollector      | 18           | 0      | t_address                                      | 0   | /build-info/xxx.json   | 20            |
| AaveV3MultiStake   | claimableAssetFees| 19           | 0      | t_uint256                                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | exemptionList     | 20           | 0      | t_mapping(t_address,t_bool)                    | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | _req              | 21           | 0      | t_struct(Requests)5372_storage                 | 0   | /build-info/xxx.json   | 160           |
| AaveV3MultiStake   | _requestId        | 26           | 0      | t_uint256                                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | _wgas             | 27           | 0      | t_contract(IWETH9)29126                        | 0   | /build-info/xxx.json   | 20            |
| AaveV3MultiStake   | swapper           | 28           | 0      | t_contract(ISwapper)273                        | 0   | /build-info/xxx.json   | 20            |
| AaveV3MultiStake   | inputs            | 29           | 0      | t_array(t_contract(IERC20Metadata)495)8_storage| 0   | /build-info/xxx.json   | 256           |
| AaveV3MultiStake   | _inputDecimals    | 37           | 0      | t_array(t_uint8)8_storage                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | inputWeights      | 38           | 0      | t_array(t_uint16)8_storage                     | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | lpTokens          | 39           | 0      | t_array(t_contract(IERC20Metadata)495)8_storage| 0   | /build-info/xxx.json   | 256           |
| AaveV3MultiStake   | _lpTokenDecimals  | 47           | 0      | t_array(t_uint8)8_storage                      | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | rewardTokens      | 48           | 0      | t_array(t_address)8_storage                    | 0   | /build-info/xxx.json   | 256           |
| AaveV3MultiStake   | _rewardTokenIndexes | 56        | 0      | t_mapping(t_address,t_uint256)                 | 0   | /build-info/xxx.json   | 32            |
| AaveV3MultiStake   | _inputLength      | 57           | 0      | t_uint8                                        | 0   | /build-info/xxx.json   | 1             |
| AaveV3MultiStake   | _rewardLength     | 57           | 1      | t_uint8                                        | 0   | /build-info/xxx.json   | 1             |
| AaveV3MultiStake   | _poolProvider     | 57           | 2      | t_contract(IPoolAddressesProvider)11015       | 0   | /build-info/xxx.json   | 20            |
