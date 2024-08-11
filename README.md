<div align="center">
  <img border-radius="25px" max-height="250px" src="./banner.png" alt="Astrolab Strategies" />
  <p>
    <strong>by <a href="https://astrolab.fi">Astrolab DAO<a></strong>
  </p>
  <p>
    <!-- <a href="https://github.com/AstrolabDAO/strats/actions"><img alt="Build Status" src="https://github.com/AstrolabDAO/strats/actions/workflows/tests.yaml/badge.svg" /></a> -->
    <a href="https://opensource.org/licenses/MIT"><img alt="License" src="https://img.shields.io/github/license/AstrolabDAO/strats?color=3AB2FF" /></a>
    <a href="https://discord.gg/PtAkTCwueu"><img alt="Discord Chat" src="https://img.shields.io/discord/984518964371673140"/></a>
    <a href="https://docs.astrolab.fi"><img alt="Astrolab Docs" src="https://img.shields.io/badge/astrolab_docs-F9C3B3" /></a>
  </p>
</div>

This repo holds Astrolab DAO's yield primitives and dependencies.

Besides harvesting/compounding automation (cf. [Astrolab Botnet](https://github.com/AstrolabDAO/monorepo/nptnet)), most of [CSA](#strategy-types) and [NSA](#strategy-types) strategies have off-chain components (eg. cross-chain arb, triangular arb, carry trading), which are not part of this repository, and kept closed-source as part of our Protocol secret sauce.

## Disclaimer ⚠️
Astrolab DAO and its core team members will not be held accountable for losses related to the deployment and use of this repository's codebase.
As per the [licence](./LICENCE) states, the code is provided as-is and is under active development. The codebase, documentation, and other aspects of the project may be subject to changes and improvements over time.

## Content
- Core contracts
  - [StrategyV5.sol](./src/abstract/StrategyV5.sol) 🎯
    Strategy base contract, extended by all, delegating common logic to StrategyV5Agent
  - [StrategyV5Agent.sol](./src/abstract/StrategyV5Agent.sol) 🎭
    Shared strategy back-end, inheriting from As4626

- Base contracts
  - [As4626.sol](./src/abstract/As4626.sol) 📦
    Full-featured ERC4626 tokenized vault implementation
  - [AsPermissioned](./src/abstract/AsPermissioned.sol) 🛡️
    `AccessController` consummer enabling contract RBAC
  - [AsPriceAware](./src/abstract/AsPermissioned.sol) 📡
    `PriceProvider` consummer feeding contracts with live exchange rates
  - [AsFlashLender](./src/abstract/AsPermissioned.sol) 🏦
    Grants the contract EIP-3156 flash lending capabilitites
  - [AsRescuable](./src/abstract/AsRescuable.sol) ⛑️
    Grants the contract native and ERC20 emergency token rescue capabilities

- Standalone deployments
  - [AccessController](./src/abstract/AccessController.sol) 🛡️
    DAO's standalone access controller used for RBAC
  - [PriceProvider](./src/abstract/PriceProvider.sol) 📡
    Oracle adapter dedicated to price retrieval from Chainlink, Pyth, Redstone and more
  - [Bridger](./) ⛓️
    Bridge aggregator unifying cross-chain interoperability through Axelar, LayerZero, Wormhole, Chainlink CCTP.
    Powers the DAO's cross-chain composite Strategies, acUSD, acETH and acBTC (to be migrated from v0)
  - [Swapper](https://github.com/AstrolabFinance/swapper) ♻️
    DAO's standalone liquidity aggregator

- Implementations of DeFi multi-protocol, multi-chain strategies ([cf. below](#strategies))

- Libs 📚
  - [AsCast.sol](./src/libs/AsCast.sol)
    Safe and unsafe casting
  - [AsMaths.sol](./src/libs/AsMaths.sol)
    Standard maths library, borrowing from OZ's, ABDK's, PRB's, Uniswap's and Vectorized's
  - [AsArrays.sol](./src/libs/AsArrays.sol)
    Array manipulation library
  - [AsAccounting.sol](./src/libs/AsAccounting.sol)
    Strategy accounting library
  - [AsRisk.sol](./src/libs/AsRisk.sol)
    Protocol risk management library

## Testing
Testing As4626+StrategyV5 with Hardhat (make sure to set `HARDHAT_CHAIN_ID=42161` in `.env` to run the below test to be successful):
```bash
yarn test-hardhat # yarn hardhat test test/Compound/CompoundV3Optimizer.test.ts --network hardhat
```

Testing As4626+StrategyV5 with Tenderly (make sure to set `TENDERLY_CHAIN_ID=42161` and define your tenderly fork ids in `.env` for the below  test to be successful):
```bash
yarn test-tenderly # yarn hardhat test test/Compound/CompoundV3Optimizer.test.ts --network tenderly
```

Foundry tests are also in the works, used for fuzzing, drafting and debugging (not integration as test suites require extensive data manipulation and http querying).

The repo depends on [@astrolabs/hardhat](https://github.com/AstrolabDAO/hardhat), therefore you can use our generic deployment functions for fine-grain partial deployments of the stack:
```typescript
import { deployAll } from "@astrolabs/hardhat";

async function main() {
  await deployAll({
    name: "AsMaths", // deployment unit name
    contract: "AsMaths", // contract name
    verify: true, // automatically verify on Tenderly or relevant explorer
    export: false, // do not export abi+deployment .json
  });
}
```
<style>
.ic {
  width: 18px;  /* Adjust the size as needed */
  height: 18px;
  margin-right: 4px;
  margin-top: 5px;
  display: inline-block;
  background-size: contain;
  background-repeat: no-repeat;
}

.eth { background-image: url('https://cdn.astrolab.fi/assets/images/networks/ethereum.svg'); }
.op { background-image: url('https://cdn.astrolab.fi/assets/images/networks/optimism.svg'); }
.arb { background-image: url('https://cdn.astrolab.fi/assets/images/networks/arbitrum.svg'); }
.base { background-image: url('https://cdn.astrolab.fi/assets/images/networks/base.svg'); }
.poly { background-image: url('https://cdn.astrolab.fi/assets/images/networks/polygon.svg'); }
.bnb { background-image: url('https://cdn.astrolab.fi/assets/images/networks/bnb-chain.svg'); }
.gno { background-image: url('https://cdn.astrolab.fi/assets/images/networks/gnosis-chain.svg'); }
.avax { background-image: url('https://cdn.astrolab.fi/assets/images/networks/avalanche.svg'); }
.glmr { background-image: url('https://cdn.astrolab.fi/assets/images/networks/moonbeam.svg'); }
.blast { background-image: url('https://cdn.astrolab.fi/assets/images/networks/blast.svg'); }
.mode { background-image: url('https://cdn.astrolab.fi/assets/images/networks/mode.svg'); }
.ftm { background-image: url('https://cdn.astrolab.fi/assets/images/networks/fantom.svg'); }
.linea { background-image: url('https://cdn.astrolab.fi/assets/images/networks/linea.svg'); }
.scroll { background-image: url('https://cdn.astrolab.fi/assets/images/networks/scroll.svg'); }
.mntl { background-image: url('https://cdn.astrolab.fi/assets/images/networks/mantle.svg'); }
.celo { background-image: url('https://cdn.astrolab.fi/assets/images/networks/celo.svg'); }
.canto { background-image: url('https://cdn.astrolab.fi/assets/images/networks/canto.svg'); }
.kava { background-image: url('https://cdn.astrolab.fi/assets/images/networks/kava.svg'); }
.zksync { background-image: url('https://cdn.astrolab.fi/assets/images/networks/zksync-era.svg'); }
.zora { background-image: url('https://cdn.astrolab.fi/assets/images/networks/zora.svg'); }

</style>
## Strategy Types

| Type | Symbol | Description | Maximum Leverage | Underlyings |
| ---- | ------ | ----------- | ---------------- | ----------- |
| Lending | LND | Liquidity providing to highly utilized money markets or CDP issuers (eg. Maker, Frax) | 20:1 | Stables, ETH, BTC, LSDs, LRTs |
| Spot Market Making | SMM | Liquidity providing to bridges (eg. Stargate, Connext) and spot DEXs (eg. Uniswap V2's volatile market making aka. vAMM, Curve's stable market making aka. sAMM, Uniswap V3 concentrated liquidity market making aka. CLMM) direct or delegated to ALMs (active liquidity managers, eg. Gamma for CLMM, Elixir for central limit order books aka. CLOBs) | 20:1 | Stables, ETH, BTC, LSDs, LRTs |
| Derivatives Market Making | DMM | Liquidity providing to derivatives DEXs (eg. GMX, Hyperliquid, Gains) direct or delegated to liquidity managers (eg. Pendle, Elixir for CLOBs) | 20:1 | Stables, ETH, BTC, LSDs, LRTs |
| Unsecured Govt Debt | UGD | Liquidity providing to government debt (eg. US treasuries) through relevant on-chain issuers (e.g. Ondo, Backed) | 10:1 | Stables |
| Unsecured Corp Debt | UCD | Liquidity providing to corporate debt through relevant on-chain issuers (e.g. Maple, Clearpool, Goldfinch) | 10:1 | Stables |
| Hyper Staking | HST | Augmented staking (direct or delegated eg. Lido, Rocket Pool, Ankr, Coinbase, Binance) with restaking (eg. EigenLayer) and LSD arbitrage | 20:1 | Stables, ETH, BTC, LSDs, LRTs |
| Covered Stat Arb | CSA | Delta-neutral trading: carry trading (direct or delegated eg. Ethena), cross-DEX and cross-chain arbitrage | 500:1 | Stables, ETH, BTC, LSDs, LRTs, Alts |
| Naked Stat Arb | NSA | High delta trading: crypto, FX, and equity derivatives (trend following, momentum, mean reversal) | 500:1 | Stables, ETH, BTC, LSDs, LRTs, Alts |
| Insurance | INS | Liquidity providing to protocol-specific (eg. AAVE Umbrella) or multi-protocol (eg. Nexus Mutual) insurers | 10:1 | Stables, ETH, BTC, Alts |
| Services | SER | Liquidity providing to infrastructure providers (governance, identity, gaming, betting eg. ) | 10:1 | Stables, ETH, BTC, Alts |
| Composite | CMP | Structured product that cannot fit a single of the above categories (eg. Astrolab Composites) | 10:1 | Stables, ETH, BTC, LSDs, LRTs |

## Strategies

### Primitives
| Name                     | Type  | Identifier | Status | Compatible Chains |
| ------------------------ | ----- | ---------- | ------ | ----------------- |
| AaveV3 Optimizer         | LND | AAVE3-O | ✔️ Tested | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div><div class="ic scroll"></div><div class="ic gno"></div> |
| AaveV3 Arbitrage         | LND | AAVE3-A | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div><div class="ic scroll"></div><div class="ic gno"></div> |
| Compound V3 Optimizer    | LND | COMP3-O | ✔️ Tested | <div class="ic eth"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic scroll"></div> |
| Compound V3 Arbitrage    | LND | COMP3-A | 🚧 WIP | <div class="ic eth"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic scroll"></div> |
| Venus Optimizer          | LND | XVS-O | ✔️ Tested | <div class="ic bnb"></div> |
| Venus Arbitrage          | LND | XVS-A | ✔️ Tested | <div class="ic bnb"></div> |
| Lodestar Optimizer       | LND | LODE-O | ✔️ Tested | <div class="ic arb"></div> |
| Lodestar Arbitrage       | LND | LODE-A | ✔️ Tested | <div class="ic arb"></div> |
| Moonwell Optimizer       | LND | WELL-O | ✔️ Tested | <div class="ic glmr"></div><div class="ic base"></div> |
| Moonwell Arbitrage       | LND | WELL-A | 🚧 WIP | <div class="ic glmr"></div><div class="ic base"></div> |
| Benqi Optimizer          | LND | QI-O | ✔️ Tested | <div class="ic avax"></div> |
| Benqi Arbitrage          | LND | QI-A | 🚧 WIP | <div class="ic avax"></div> |
| Agave Optimizer          | LND | AGVE-O | ☠️ Axed | <div class="ic gno"></div> |
| Agave Arbitrage          | LND | AGVE-A | ☠️ Axed | <div class="ic gno"></div> |
| Sonne Optimizer          | LND | SONNE-O | ☠️ Axed | <div class="ic op"></div><div class="ic base"></div> |
| Sonne Arbitrage          | LND | SONNE-A | ☠️ Axed | <div class="ic op"></div><div class="ic base"></div> |
| Stargate Optimizer       | SMM | STG-O | ✔️ Tested | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div><div class="ic linea"></div><div class="ic mntl"></div><div class="ic scroll"></div> |
| Stargate V2 Optimizer    | SMM | STG2-O | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div><div class="ic linea"></div><div class="ic mntl"></div><div class="ic scroll"></div> |
| Hop Optimizer            | SMM | HOP-O | ✔️ Tested | <div class="ic eth"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic gno"></div><div class="ic linea"></div> |
| Synapse Optimizer        | SMM | SYN-O | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div></div><div class="ic blast"></div><div class="ic canto"></div> |
| Connext Optimizer        | SMM | NEXT-O | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic linea"></div><div class="ic gno"></div><div class="ic mode"></div> |
| Across Optimizer         | SMM | ACX-O | 🚧 WIP | <div class="ic eth"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div></div><div class="ic linea"></div><div class="ic scroll"></div><div class="ic blast"></div><div class="ic mode"></div><div class="ic zksync"></div> |
| Uniswap V3 Optimizer     | SMM | UNI3-O | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div></div><div class="ic blast"></div></div><div class="ic zksync"></div><div class="ic zora"></div> |
| Uniswap V4 Optimizer     | SMM | UNI4-O | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div></div><div class="ic blast"></div></div><div class="ic zksync"></div><div class="ic zora"></div> |
| Thena Optimizer          | SMM | THE-O | ✔️ Tested | <div class="ic bnb"></div> |
| Camelot Optimizer        | SMM | GRAIL-O | 🚧 WIP | <div class="ic arb"></div> |
| Velodrome Optimizer      | SMM | VELO-O | 🚧 WIP | <div class="ic op"></div> |
| Aerodrome Optimizer      | SMM | AERO-O | 🚧 WIP | <div class="ic base"></div> |
| Toros Optimizer          | DMM | TOROS-O | 🚧 WIP | <div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div></div><div class="ic poly"></div> |

### Composites
| Name                     | Type  | Identifier | Status | Compatible Chains |
| ------------------------ | ----- | ---------- | ------ | ----------------- |
| Astrolab Composite USD   | CMP   | acUSD | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div><div class="ic linea"></div><div class="ic mntl"></div><div class="ic scroll"></div><div class="ic gno"></div><div class="ic blast"></div> |
| Astrolab Composite ETH   | CMP   | acETH | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div><div class="ic linea"></div><div class="ic mntl"></div><div class="ic scroll"></div><div class="ic gno"></div><div class="ic blast"></div> |
| Astrolab Composite BTC   | CMP   | acBTC | 🚧 WIP | <div class="ic eth"></div><div class="ic bnb"></div><div class="ic arb"></div><div class="ic op"></div><div class="ic base"></div><div class="ic poly"></div><div class="ic avax"></div><div class="ic linea"></div><div class="ic mntl"></div><div class="ic scroll"></div><div class="ic gno"></div><div class="ic blast"></div> |

## Integrated/Watched Protocols 👀

### Staking
Primitives
  - [Lido/stETH](https://github.com/lidofinance/lido-dao)
  - [RocketPool/rETH](https://github.com/rocket-pool/rocketpool)
  - [StakeWise/rETH2+osETH](https://github.com/stakewise/contracts)
  - [Stader/ETHx](https://github.com/stader-labs/ethx)
  - [Swell/swETH](https://github.com/SwellNetwork/v3-core-public)
  - [Frax/sfrxETH](https://github.com/FraxFinance/frxETH-public)
  - [Coinbase/cbETH](https://github.com/coinbase/wrapped-tokens-os)
  - [Binance/WBETH](https://github.com/bnb-chain)
  - [Mantle/mETH](https://github.com/mantle-lsp/L2-token-contract)

Derivatives
  - [Prisma](https://github.com/prisma-fi/prisma-contracts)
  - [Lybra](https://github.com/LybraFinance/LybraV2)
  - [Stakehouse/dETH](https://github.com/stakehouse-dev/compound-staking)
  - [Manifold/mevETH2](https://github.com/manifoldfinance/mevETH2)
  - [unshEth](https://github.com/UnshETH/merkle-distributor)
  - [Puffer/pufETH](https://github.com/PufferFinance/pufETH)

### ReStaking
Primitives
  - [EigenLayer](https://github.com/Layr-Labs/eigenlayer-contracts)
  - [EtherFi/weETH](https://github.com/etherfi-protocol/smart-contracts)
  - [Renzo/ezETH+pzETH](https://github.com/Renzo-Protocol/contracts-public)
  - [Karak/KweETH+KmETH](https://github.com/karak-network/v1-contracts-public)
  - [Mellow](https://github.com/mellow-finance/mellow-lrt)
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
  - [Spark](https://github.com/marsfoundation/sparklend)
  - [Frax](https://github.com/FraxFinance/fraxlend)
  - [Venus](https://github.com/VenusProtocol/venus-protocol)
  - [JustLend](https://github.com/justlend/justlend-protocol)
  - [Silo](https://github.com/silo-finance/silo-core-v1)
  - [Radiant](https://github.com/radiant-capital)
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
