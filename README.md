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

This repo holds Astrolab DAO's yield primitives.

- Strategy abstract contracts 🎯
  - [As4626.sol](./src/abstract/As4626.sol) (light-weight, full-featured ERC4626 tokenized vault implementation)
  - [StrategyV5.sol](./src/abstract/StrategyV5.sol) (strategy contract, extended by strategies, transparent proxy delegating to StrategyV5Agent)
  - [StrategyV5Agent.sol](./src/abstract/StrategyV5Agent.sol) (common strategy logic, implementation inheriting from As4626)
  - Add-ons 🧩
    - [StrategyV5Chainlink.sol](./src/abstract/StrategyV5Chainlink.sol)
    - [StrategyV5Pyth.sol](./src/abstract/StrategyV5Pyth.sol)

- Implementations of DeFi multi-protocol, multi-chain strategies ([cf. below](#strategies))

- Libs 📚
  - [AsMaths.sol](./src/libs/AsMaths.sol)
  - [AsArrays.sol](./src/libs/AsArrays.sol)
  - [AsAccounting.sol](./src/libs/AsAccounting.sol) Strategy accounting helpers
  - [ChainlinkUtils.sol](./src/libs/ChainlinkUtils.sol) Chainlink specific oracle utils
  - [PythUtils.sol](./src/libs/PythUtils.sol) Pyth specific oracle utils

Besides harvesting/compounding automation (cf. [Astrolab Botnet](https://github.com/AstrolabDAO/monorepo/nptnet)), some of the strategies have off-chain components (eg. cross-chain arb, statistical arb, triangular arb, carry trading etc.), which are not part of this repository, and kept closed-source as part of our Protocol secret sauce.

## Disclaimer ⚠️
Astrolab DAO and its core team members will not be held accountable for losses related to the deployment and use of this repository's codebase.
As per the [licence](./LICENCE) states, the code is provided as-is and is under active development. The codebase, documentation, and other aspects of the project may be subject to changes and improvements over time.

## Testing
Testing As4626+StrategyV5 with Hardhat (make sure to set `HARDHAT_CHAIN_ID=42161` in `.env` to run the below test to be successful):
```bash
yarn test-hardhat # yarn hardhat test test/Compound/CompoundV3MultiStake.test.ts --network hardhat
```

Testing As4626+StrategyV5 with Tenderly (make sure to set `TENDERLY_CHAIN_ID=42161` and define your tenderly fork ids in `.env` for the below  test to be successful):
```bash
yarn test-tenderly # yarn hardhat test test/Compound/CompoundV3MultiStake.test.ts --network tenderly
```

The repo imports [@astrolabs/hardhat](https://github.com/AstrolabDAO/hardhat), therefore you can use our generic deployment functions for fine-grain partial deployments of the stack:
```typescript
import { deployAll } from "@astrolabs/hardhat";

async function main() {
  await deployAll({
    name: "AsMaths", // deployment unit name
    contract: "AsMaths", // contract name
    verify: true, // automatically verify on Tenderly or relevant explorer
    export: false, // do not export abi+deployment .son
  });
}
```

## Strategies 🚧
- [AaveMultiStake](./src/implementations/Aave/AaveMultiStake.sol)
- [HopMultiStake](./src/implementations/Hop/HopMultiStake.sol)
- [LodestarMultiStake](./src/implementations/Lodestar/LodestarMultiStake.sol)
- [VenusMultiStake](./src/implementations/Venus/VenusMultiStake.sol)
- [SonneMultiStake](./src/implementations/Sonne/SonneMultiStake.sol)
- [CompoundV3MultiStake](./src/implementations/Compound/CompoundV3MultiStake.sol)
- [AaveV3MultiStake](./src/implementations/Aave/AaveV3MultiStake.sol)
- [MoonwellMultiStake](./src/implementations/Moonwell/MoonwellMultiStake.sol)
- [MoonwellLegacyMultiStake](./src/implementations/Moonwell/MoonwellLegacyMultiStake.sol)
- [StargateMultiStake](./src/implementations/Stargate/StargateMultiStake.sol)
- [AgaveMultiStake](./src/implementations/Agave/AgaveMultiStake.sol)
- [BenqiMultiStake](./src/implementations/Benqi/BenqiMultiStake.sol)
- ...

## Integrated/Watched Protocols 👀

### Staking
Primitives
  - [Lido/stETH](https://github.com/lidofinance/lido-dao)
  - [RocketPool/rETH](https://github.com/rocket-pool/rocketpool)
  - [StakeWise/rETH2](https://github.com/stakewise/contracts)
  - [Stader/ETHx](https://github.com/stader-labs/ethx)
  - [Swell/swETH](https://github.com/SwellNetwork/v3-core-public)
  - [Frax/sfrxETH](https://github.com/FraxFinance/frxETH-public)
  - [Coinbase/cbETH](https://github.com/coinbase/wrapped-tokens-os)
  - [Binance/wBETH](https://github.com/bnb-chain)

Derivatives
  - [Prisma](https://github.com/prisma-fi/prisma-contracts)
  - [Lybra](https://github.com/LybraFinance/LybraV2)
  - [Stakehouse/dETH](https://github.com/stakehouse-dev/compound-staking)
  - [Manifold/mevETH2](https://github.com/manifoldfinance/mevETH2)
  - [unshEth](https://github.com/UnshETH/merkle-distributor)

### ReStaking
Primitives
  - [EigenLayer](https://github.com/Layr-Labs/eigenlayer-contracts)
  - [Stakehouse](https://github.com/stakehouse-dev/compound-staking)

### RWA
Primitives
  - [Spark/sDAI](https://github.com/marsfoundation/sparklend)
  - [stUSDT](https://github.com/justlend/justlend-protocol)
  - [Ondo/USDY/OUSG](https://github.com/ondoprotocol/usdy) `KYC`
  - [Matrixdock/STBT](https://stbt.matrixdock.com/) `KYC`
  - [OpenEden/TBill](https://github.com/OpenEdenHQ/openeden.smartcontract.audit) `KYC`
  - [BackedFi/bIB01](https://backed.fi) `KYC`
  - [Hashnote/USYC](https://usyc.hashnote.com) `KYC`
  - [Goldfinch](https://github.com/goldfinch-eng/goldfinch-contracts)
  - [Centrifuge](https://github.com/centrifuge/liquidity-pools)
  - [Maple](https://github.com/maple-labs/maple-core-v2)
  - [TrueFi](https://github.com/trusttoken/contracts-pre22)

### Money Markets
Primitives
  - [AAVE V2](https://github.com/aave/protocol-v2)
  - [AAVE V3](https://github.com/aave/aave-v3-core)
  - [Compound V2](https://github.com/compound-finance/compound-protocol)
  - [Compound V3](https://github.com/compound-finance/compound-protocol)
  - [JustLend](https://github.com/justlend/justlend-protocol)
  - [Spark](https://github.com/marsfoundation/sparklend)
  - [Frax](https://github.com/FraxFinance/fraxlend)
  - [Silo](https://github.com/silo-finance/silo-core-v1)
  - [Venus](https://github.com/VenusProtocol/venus-protocol)
  - [Radiant](https://github.com/radiant-capital)
  - [Agave](https://github.com/Agave-DAO/protocol-v2)
  - [Lodestar](https://github.com/LodestarFinance)
  - [Abracadabra](https://github.com/Abracadabra-money/abracadabra-money-contracts)

Derivatives
  - [Morpho](https://github.com/morpho-org)
  - [Gearbox](https://github.com/Gearbox-protocol/core-v3)
  - [Sturdy](https://github.com/sturdyfi/sturdy-aggregator)

### Spot DEXs
Primitives
  - [Uniswap V2](https://github.com/Uniswap/v2-core)
  - [Uniswap V3](https://github.com/Uniswap/v3-core)
  - [Uniswap V4](https://github.com/Uniswap/v4-core)
  - [Balancer V1](https://github.com/balancer/balancer-core)
  - [Balancer V2](https://github.com/balancer/balancer-v2-monorepo)
  - [Curve](https://github.com/curvefi/curve-contract)
  - [Maverick](https://github.com/maverickprotocol/maverick-v1-interfaces)
  - [Sushi](https://github.com/sushiswap/v2-core)
  - [PancakeSwap](https://github.com/pancakeswap/pancake-smart-contracts)
  - [QuickSwap](https://github.com/QuickSwap/quickswap-core)
  - [Trader Joe](https://github.com/traderjoe-xyz/joe-v2)
  - [KyberSwap](https://github.com/KyberNetwork/ks-elastic-sc)
  - [DODO](https://github.com/DODOEX/dodo-smart-contract)
  - [Wombat](https://app.wombat.exchange)
  - [Biswap](https://github.com/biswap-org/core)
  - [Camelot](https://github.com/CamelotLabs/core)
  - [Velodrome](https://github.com/velodrome-finance/contracts)
  - [iZUMi/iZiSwap](https://github.com/izumiFinance/iZiSwap-core)
  - [SyncSwap](https://github.com/syncswap/core-contracts)

Derivatives
  - [Convex](https://github.com/convex-eth/platform)
  - [Aura](https://github.com/aurafinance/aura-contracts)
  - [Gamma](https://github.com/GammaStrategies/hypervisor)
  - [Arrakis V2](https://github.com/ArrakisFinance/v2-core)
  - [Tokemak V1](https://github.com/Tokemak/contracts-v1)
  - [Tokemak V2](https://github.com/Tokemak)
  - [Beefy](https://github.com/beefyfinance/beefy-contracts)

### Derivatives DEXs
Primitives
  - [GMX](https://github.com/gmx-io/gmx-contracts)
  - [Gains/gTrade](https://github.com/GainsNetwork/gTrade-v6.1)
  - [MUX](https://github.com/mux-world/mux-protocol)
  - [HMX](https://github.com/HMXOrg/v2-evm)
  - [Pika](https://github.com/PikaProtocol/PikaPerpV4)
  - [Vela](https://github.com/VelaExchange/vela-exchange-contracts)
  - [ApolloX](https://github.com/apollox-finance/apollox-contracts)

Derivatives
  - [Vaultka](https://github.com/Vaultka-Project)
  - [JonesDAO](https://github.com/Jones-DAO/jaura-oracle)
  - [Umami](https://github.com/UmamiDAO/arbis-contracts)

### Structured Finance
Primitives
  - [Pendle](https://github.com/pendle-finance/pendle-core-v2-public)

Derivatives
  - [Equilibria](https://github.com/eqbtech/equilibria-contracts)

### Bridges
Primitives
  - [Hop](https://github.com/hop-protocol/contracts-v2)
  - [Stargate](https://github.com/stargate-protocol/stargate-dao)
  - [Synapse](https://github.com/synapsecns/synapse-contracts)
  - [Across](https://github.com/across-protocol/contracts-v2)
  - [Connext](https://github.com/connext/interfaces)
  - [Celer/cBridge](https://github.com/celer-network/sgn-v2-contracts)

Derivatives
  - [Beefy](https://github.com/beefyfinance/beefy-contracts)
  - [Socket](https://github.com/SocketDotTech/socket-DL)
  - [LiFi]()
  - [Squid]()

### Yield Aggregators
- [Yearn](https://github.com/yearn/tokenized-strategy-periphery)
- [Sommelier](https://github.com/PeggyJV/cellar-contracts)
- [Overnight/USD+](https://github.com/ovnstable/ovnstable-core)
- [Origin/OUSD](https://github.com/OriginProtocol/origin-dollar)
- [Idle](https://github.com/Idle-Finance)
- [dHedge/Toros](https://github.com/dhedge/V2-Public)
- [Neutra](https://github.com/NeutraFinance/neutra-strategies)

## Credits
Special thanks to peer aggregators who also open source their strategies
- [Beefy](https://github.com/beefyfinance/beefy-contracts/tree/master/contracts/BIFI/strategies)
- [Overnight/USD+](https://github.com/ovnstable/ovnstable-core/tree/master/pkg/strategies)
- [DefiSaver](https://github.com/defisaver/defisaver-v3-contracts/tree/main)
- [Origin/OUSD](https://github.com/OriginProtocol/origin-dollar/tree/master/contracts/contracts/strategies)
- [Vesper](https://github.com/vesperfi/vesper-pools-v2/tree/master/contracts/strategies)
- [YieldYak](https://github.com/yieldyak/smart-contracts/tree/master/contracts/strategies)
- [Idle](https://github.com/Idle-Labs/idle-tranches/tree/master/contracts)
- [Affine](https://github.com/AffineLabs/contracts/tree/master/src/strategies)
- [ACryptoS](https://github.com/acryptos/acryptos-protocol/tree/main/strategies)
- [Sushi/Bentobox](https://github.com/sushiswap/strategies)


## Contributing
Contributions are welcome, the DAO is always open to team up with like-minded builders and strategists.
Find us on [Discord](https://discord.gg/zYV2pguXge) by day or night 🌞🌛
Up to 20% of a strategy PnL is claimable to their rightful designer.

Astrolab DAO vetting process on strategy submission is in the works, and will be similar to [that of Yearn](https://docs.yearn.fi/developers/v3/strategy_writing_guide)

Feel free to open an issue or create a pull request if you have any improvements or suggestions.

Started with ❤️ at [DevCon/EthGlobal IST 2023](https://ethglobal.com/events/istanbul)
