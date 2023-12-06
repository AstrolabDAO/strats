<div align="center">
  <img border-radius="25px" max-height="250px" src="./banner.png" />
  <h1>Astrolab Strategies</h1>
  <p>
    <strong>by <a href="https://astrolab.fi">Astrolab<a></strong>
  </p>
  <p>
    <!-- <a href="https://github.com/AstrolabDAO/strats/actions"><img alt="Build Status" src="https://github.com/AstrolabDAO/strats/actions/workflows/tests.yaml/badge.svg" /></a> -->
    <a href="https://opensource.org/licenses/MIT"><img alt="License" src="https://img.shields.io/github/license/AstrolabDAO/strats?color=3AB2FF" /></a>
    <a href="https://discord.gg/PtAkTCwueu"><img alt="Discord Chat" src="https://img.shields.io/discord/984518964371673140"/></a>
    <a href="https://docs.astrolab.fi"><img alt="Astrolab Docs" src="https://img.shields.io/badge/astrolab_docs-F9C3B3" /></a>
  </p>
</div>

This repo holds Astrolab's strategies smart contracts, aka the DAO's yield primitives.
- Libs
  - [AsMaths.sol](./src/abstract/AsMaths.sol): math utils
  - [AsArrays.sol](./src/abstract/AsArrays.sol): array utils
  - [AsAccounting.sol](./src/abstract/AsAccounting.sol): strategy accounting helpers
  - [ChainlinkUtils.sol](./src/abstract/ChainlinkUtils.sol): chainlink specific oracle utils
  - [PythUtils.sol](./src/abstract/PythUtils.sol): pyth specific oracle utils

- Strategy abstract contracts
  - [As4626.sol](./src/abstract/As4626.sol) (light-weight, full-featured ERC4626 tokenized vault implementation)
  - [StrategyV5.sol](./src/abstract/StrategyV5.sol) (strategy contract, extended by strategies, transparent proxy delegating to StrategyV5Agent)
  - [StrategyV5Agent.sol](./src/abstract/StrategyV5Agent.sol) (common strategy logic, implementation inheriting from As4626)
  - Add-ons:
    - [StrategyV5Chainlink.sol](./src/abstract/StrategyV5Chainlink.sol)
    - [StrategyV5Pyth.sol](./src/abstract/StrategyV5Pyth.sol)

- Implementations of DeFi multi-protocol, multi-chain strategies ([cf. below](#strategies))

Besides harvesting/compounding automation (cf. [Astrolab Botnet](https://github.com/AstrolabDAO/monorepo/nptnet)), some of the strategies have off-chain components (eg. cross-chain arb, statistical arb, triangular arb, carry trading etc.), which are not part of this repository, and kept closed-source as part of our Protocol secret sauce.

## ⚠️ Disclaimer
Astrolab DAO and its core team members will not be held accountable for losses related to the deployment and use of this repository's codebase.
As per the [licence](./LICENCE) states, the code is provided as-is and is under active development. The codebase, documentation, and other aspects of the project may be subject to changes and improvements over time.

## Strategies
- [AaveMultiStake](./src/implementations/Aave/AaveMultiStake.sol)
- [HopMultiStake](./src/implementations/Aave/HopMultiStake.sol)
- ...

## Integrated Protocols

### Staking
Primitives
  - [Lido/stETH](https://github.com/lidofinance/lido-dao) `todo`
  - [RocketPool/rETH](https://github.com/rocket-pool/rocketpool) `todo`
  - [StakeWise/rETH2](https://github.com/stakewise/contracts) `todo`
  - [Stader/ETHx](https://github.com/stader-labs/ethx) `todo`
  - [Swell/swETH](https://github.com/SwellNetwork/v3-core-public) `todo`
  - [Frax/sfrxETH](https://github.com/FraxFinance/frxETH-public) `todo`
  - [Coinbase/cbETH](https://github.com/coinbase/wrapped-tokens-os) `todo`
  - [Binance/wBETH](https://github.com/bnb-chain) `todo`

Derivatives
  - [Prisma](https://github.com/prisma-fi/prisma-contracts) `todo`
  - [Lybra](https://github.com/LybraFinance/LybraV2) `todo`
  - [Stakehouse/dETH](https://github.com/stakehouse-dev/compound-staking) `todo`
  - [Manifold/mevETH2](https://github.com/manifoldfinance/mevETH2)
  - [unshEth](https://github.com/UnshETH/merkle-distributor) `todo`

### ReStaking
Primitives
  - [EigenLayer](https://github.com/Layr-Labs/eigenlayer-contracts) `todo`
  - [Stakehouse](https://github.com/stakehouse-dev/compound-staking) `todo`

### RWA
Primitives
  - [Spark](https://github.com/marsfoundation/sparklend) `todo`
  - [stUSDT](https://github.com/justlend/justlend-protocol) `todo`
  - [Ondo/USDY](https://github.com/ondoprotocol/usdy) `todo`
  - [OpenEden/TBill](https://github.com/OpenEdenHQ/openeden.smartcontract.audit) `todo`
  - [Goldfinch](https://github.com/goldfinch-eng/goldfinch-contracts) `todo`
  - [Centrifuge](https://github.com/centrifuge/liquidity-pools) `todo`
  - [Maple](https://github.com/maple-labs/maple-core-v2) `todo`
  - [TrueFi](https://github.com/trusttoken/contracts-pre22) `todo`

### Money Markets
Primitives
  - [AAVE V2](https://github.com/aave/protocol-v2) `todo`
  - [AAVE V3](https://github.com/aave/aave-v3-core) `todo`
  - [Compound V2](https://github.com/compound-finance/compound-protocol) `todo`
  - [Compound V3](https://github.com/compound-finance/compound-protocol) `todo`
  - [JustLend](https://github.com/justlend/justlend-protocol) `todo`
  - [Spark](https://github.com/marsfoundation/sparklend) `todo`
  - [Frax](https://github.com/FraxFinance/fraxlend) `todo`
  - [Silo](https://github.com/silo-finance/silo-core-v1)
  - [Venus](https://github.com/VenusProtocol/venus-protocol) `todo`
  - [Radiant](https://github.com/radiant-capital) `todo`
  - [Agave](https://github.com/Agave-DAO/protocol-v2) `todo`
  - [Lodestar](https://github.com/LodestarFinance) `todo`
  - [Abracadabra](https://github.com/Abracadabra-money/abracadabra-money-contracts) `todo`

Derivatives
  - [Morpho](https://github.com/morpho-org) `todo`
  - [Gearbox](https://github.com/Gearbox-protocol/core-v3) `todo`
  - [Sturdy](https://github.com/sturdyfi/sturdy-aggregator)`todo`

### Spot DEXs
Primitives
  - [Uniswap V2](https://github.com/Uniswap/v2-core) `todo`
  - [Uniswap V3](https://github.com/Uniswap/v3-core) `todo`
  - [Uniswap V4](https://github.com/Uniswap/v4-core) `todo`
  - [Balancer V1](https://github.com/balancer/balancer-core) `todo`
  - [Balancer V2](https://github.com/balancer/balancer-v2-monorepo) `todo`
  - [Curve](https://github.com/curvefi/curve-contract) `todo`
  - [Maverick](https://github.com/maverickprotocol/maverick-v1-interfaces) `todo`
  - [Sushi](https://github.com/sushiswap/v2-core) `todo`
  - [PancakeSwap](https://github.com/pancakeswap/pancake-smart-contracts) `todo`
  - [QuickSwap](https://github.com/QuickSwap/quickswap-core) `todo`
  - [Trader Joe](https://github.com/traderjoe-xyz/joe-v2) `todo`
  - [KyberSwap](https://github.com/KyberNetwork/ks-elastic-sc) `todo`
  - [DODO](https://github.com/DODOEX/dodo-smart-contract) `todo`
  - [Biswap](https://github.com/biswap-org/core) `todo`
  - [Camelot](https://github.com/CamelotLabs/core) `todo`
  - [Velodrome](https://github.com/velodrome-finance/contracts) `todo`
  - [iZUMi/iZiSwap](https://github.com/izumiFinance/iZiSwap-core) `todo`
  - [SyncSwap](https://github.com/syncswap/core-contracts) `todo`

Derivatives
  - [Convex](https://github.com/convex-eth/platform) `todo`
  - [Aura](https://github.com/aurafinance/aura-contracts) `todo`
  - [Gamma](https://github.com/GammaStrategies/hypervisor) `todo`
  - [Arrakis V2](https://github.com/ArrakisFinance/v2-core) `todo`
  - [Tokemak V1](https://github.com/Tokemak/contracts-v1) `todo`
  - [Tokemak V2](https://github.com/Tokemak) `todo`
  - [Beefy](https://github.com/beefyfinance/beefy-contracts) `todo`

### Derivatives DEXs
Primitives
  - [GMX](https://github  .com/gmx-io/gmx-contracts) `todo`
  - [Gains/gTrade](https://github.com/GainsNetwork/gTrade-v6.1) `todo`
  - [MUX](https://github.com/mux-world/mux-protocol) `todo`
  - [HMX](https://github.com/HMXOrg/v2-evm) `todo`
  - [Pika](https://github.com/PikaProtocol/PikaPerpV4) `todo`
  - [Vela](https://github.com/VelaExchange/vela-exchange-contracts) `todo`
  - [ApolloX](https://github.com/apollox-finance/apollox-contracts) `todo`

Derivatives
  - [Vaultka](https://github.com/Vaultka-Project) `todo`
  - [JonesDAO](https://github.com/Jones-DAO/jaura-oracle) `todo`
  - [Umami](https://github.com/UmamiDAO/arbis-contracts) `todo`

### Structured Finance
Primitives
  - [Pendle](https://github.com/pendle-finance/pendle-core-v2-public) `todo`

Derivatives
  - [Equilibria](https://github.com/eqbtech/equilibria-contracts) `todo` `todo`

### Bridges
Primitives
  - [Hop](https://github.com/hop-protocol/contracts-v2) `todo`
  - [Stargate](https://github.com/stargate-protocol/stargate-dao) `todo`
  - [Synapse](https://github.com/synapsecns/synapse-contracts) `todo`
  - [Across](https://github.com/across-protocol/contracts-v2) `todo`
  - [Connext](https://github.com/connext/interfaces) `todo`
  - [Celer/cBridge](https://github.com/celer-network/sgn-v2-contracts) `todo`

Derivatives
  - [Beefy](https://github.com/beefyfinance/beefy-contracts) `todo`
  - [Socket](https://github.com/SocketDotTech/socket-DL)
  - [LiFi]()
  - [Squid]()

### Yield Aggregators
- [Yearn](https://github.com/yearn/tokenized-strategy-periphery) `todo`
- [Sommelier](https://github.com/PeggyJV/cellar-contracts) `todo`
- [Overnight/USD+](https://github.com/ovnstable/ovnstable-core) `todo`
- [Origin/OUSD](https://github.com/OriginProtocol/origin-dollar) `todo`
- [Idle](https://github.com/Idle-Finance) `todo`
- [dHedge/Toros](https://github.com/dhedge/V2-Public) `todo`
- [Neutra](https://github.com/NeutraFinance/neutra-strategies) `todo`

## Credits
Special thanks to peer aggregators who also open source their strategies
- [Beefy](https://github.com/beefyfinance/beefy-contracts/tree/master/contracts/BIFI/strategies)
- [Overnight/USD+](https://github.com/ovnstable/ovnstable-core/tree/master/pkg/strategies)
- [Origin/OUSD](https://github.com/OriginProtocol/origin-dollar/tree/master/contracts/contracts/strategies)
- [Vesper](https://github.com/vesperfi/vesper-pools-v2/tree/master/contracts/strategies)
- [YieldYak](https://github.com/yieldyak/smart-contracts/tree/master/contracts/strategies)
- [Idle](https://github.com/Idle-Labs/idle-tranches/tree/master/contracts)
- [ACryptoS](https://github.com/acryptos/acryptos-protocol/tree/main/strategies)
- [Sushi/Bentobox](https://github.com/sushiswap/strategies)

## Contributing
Contributions are welcome, the DAO is always open to team up with like-minded builders and strategists.
Find us on [Discord](https://discord.gg/zYV2pguXge) by day or night 🌞🌛
Up to 20% of a strategy PnL is claimable to their rightful designer.

Astrolab DAO vetting process on strategy submission is in the works, and will be similar to [that of Yearn](https://docs.yearn.fi/developers/v3/strategy_writing_guide)

Feel free to open an issue or create a pull request if you have any improvements or suggestions.

Started with ❤️ at [DevCon/EthGlobal IST 2023](https://ethglobal.com/events/istanbul)
