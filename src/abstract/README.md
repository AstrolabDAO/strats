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
StrategyV5 (57 slots)
├───┬─── AsManageable.sol (4 slots)
|   ├─── ReentrancyGuard.sol (1 slot)
|   ├─── Pausable.sol (1 slot)
|   ╰─── AsAccessControl.sol (1 slot)
|       ╰─── AsAccessControlAbstract (1 slot)
├─── AsProxy.sol (0 slot)
├─── ERC20Abstract (4 slots)
├─── As4626Abstract (24 slots)
├─── AsRescuable (1 slot)
|   ╰─── AsRescuableAbstract (1 slot)
╰─── StrategyV5Abstract (24 slots)

StrategyV5Agent (57 slots)
├─── As4626.sol (31 slots)
|   ├─── AsManageableAbstract.sol (4 slots)
|   |   ├─── AsAccessControlAbstract.sol (1 slot)
|   |   ╰─── ERC20 (4 slots)
|   |       ╰─── ERC20Abstract (4 slots)
|   ╰─── As4626Abstract.sol (24 slots)
├─── AsRescuableAbstract (1 slot)
╰─── StrategyV5Abstract (24 slots)
```

### Table view

Here is a table view of the above described sequential storage layout

### Table view

Here is a table view of the above described sequential storage layout

| Slots | Variable | StrategyV5 inheritance | StrategyV5Agent inheritance |
| --- | --- | --- | --- |
| 1 | IWETH9 _wgas | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 2 | ISwapper swapper | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 3 | IStrategyV5 agent | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 4->12 | IERC20Metadata[8] inputs | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 12 | uint8[8] _inputDecimals | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 13 | uint16[8] inputWeights | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 14->22 | address[8] rewardTokens | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 22 | mapping _rewardTokenIndexes | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 23 | uint8 _inputLength | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 24 | uint8 _rewardLength | StrategyV5Abstract.sol | StrategyV5Abstract.sol |
| 25 | uint256 maxTotalAssets | As4626Abstract.sol | As4626.sol |
| 26 | uint256 minLiquidity | As4626Abstract.sol | As4626.sol |
| 27 | IERC20Metadata asset | As4626Abstract.sol | As4626.sol |
| 28 | uint8 _assetDecimals | As4626Abstract.sol | As4626.sol |
| 29 | uint256 _weiPerAsset | As4626Abstract.sol | As4626.sol |
| 30->36 | Epoch last | As4626Abstract.sol | As4626.sol |
| 36 | uint256 _profitCooldown | As4626Abstract.sol | As4626.sol |
| 37 | uint256 _expectedProfits | As4626Abstract.sol | As4626.sol |
| 38->40 | Fees fees | As4626Abstract.sol | As4626.sol |
| 40 | address feeCollector | As4626Abstract.sol | As4626.sol |
| 41 | uint256 claimableAssetFees | As4626Abstract.sol | As4626.sol |
| 42 | mapping exemptionList | As4626Abstract.sol | As4626.sol |
| 43->48 | Requests _req | As4626Abstract.sol | As4626.sol |
| 48 | uint256 _requestId | As4626Abstract.sol | As4626.sol |
| 49 | string name | ERC20Abstract.sol | ERC20.sol |
| 50 | string symbol | ERC20Abstract.sol | ERC20.sol |
| 51 | uint8 decimals | ERC20Abstract.sol | ERC20.sol |
| 52 | bool _initialized | ERC20Abstract.sol | ERC20.sol |
| 53 | mapping pendingAcceptance | AsManageable.sol | AsManageableAbstract.sol |
| 54 | mapping _roles | AsAccessControl.sol | AsManageableAbstract.sol |
| 55 | bool private _paused | Pausable.sol | AsManageableAbstract.sol |
| 56 | uint256 _status | ReentrancyGuard.sol | AsManageableAbstract.sol |
| 57 | mapping _rescueRequests | AsRescuable.sol | AsRescuableAbstract.sol |
