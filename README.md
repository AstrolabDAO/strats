<div align="center">
  <img border-radius="25px" max-height="250px" src="./banner.png" />
  <h1>Radyal Strats</h1>
  <p>
    <strong>by <a href="https://astrolab.fi">Astrolab<a></strong>
  </p>
  <p>
    <!-- <a href="https://github.com/AstrolabFinance/strats/actions"><img alt="Build Status" src="https://github.com/AstrolabFinance/strats/actions/workflows/tests.yaml/badge.svg" /></a> -->
    <a href="https://opensource.org/licenses/MIT"><img alt="License" src="https://img.shields.io/github/license/AstrolabFinance/radyal-strats?color=3AB2FF" /></a>
    <a href="https://discord.gg/PtAkTCwueu"><img alt="Discord Chat" src="https://img.shields.io/discord/984518964371673140"/></a>
    <a href="https://docs.astrolab.fi"><img alt="Astrolab Docs" src="https://img.shields.io/badge/astrolab_docs-F9C3B3" /></a>
  </p>
</div>

This repo holds Radyal's smart contracts
- Libs
  - AsMaths: math utilities
  - AsAccounting: strategy accounting helpers
- Strategy Abstracts
  - As4626 (minimalistic, full-featured ERC4626 tokenized vault implementation)
  - StrategyV5 (tokenized strategy contract, inheriting from As4626)
- Implementations of DeFi multi-protocol, multi-chain strategies

## ⚠️ Disclaimer
Astrolab DAO and its core team members will not be held accountable for losses related to the deployment and use of this repository's codebase.
As per the [licence](./LICENCE) states, the code is provided as-is and is under active development. The codebase, documentation, and other aspects of the project may be subject to changes and improvements over time.

## Integrated Protocols
- [Spark](https://github.com/marsfoundation/sparklend) `todo`
- [stUSDT](https://github.com/justlend/justlend-protocol) `todo`
- [AAVE V3](https://github.com/aave/aave-v3-core) `todo`
- [Compound V3](https://github.com/compound-finance/compound-protocol) `todo`
- [Frax](https://github.com/FraxFinance/fraxlend) `todo`
- [Radiant](https://github.com/radiant-capital) `todo`
- [Uniswap V3](https://github.com/Uniswap/v3-core) `todo`
- [Balancer V2](https://github.com/balancer/balancer-v2-monorepo) `todo`
- [Curve](https://github.com/curvefi/curve-contract) `todo`
- [PancakeSwap](https://github.com/pancakeswap/pancake-smart-contracts) `todo`
- [KyberSwap](https://github.com/KyberNetwork/ks-elastic-sc) `todo`
- [iZUMi/iZiSwap](https://github.com/izumiFinance/iZiSwap-core) `todo`
- [SyncSwap](https://github.com/syncswap/core-contracts) `todo`
- [Convex](https://github.com/convex-eth/platform) `todo`
- [Gamma](https://github.com/GammaStrategies/hypervisor) `todo`
- [Hop](https://github.com/hop-protocol/contracts-v2) `todo`
- [Overnight/USD+](https://github.com/ovnstable/ovnstable-core) `todo`
- [Origin/OUSD](https://github.com/OriginProtocol/origin-dollar) `todo`
- [Idle](https://github.com/Idle-Finance) `todo`
- [dHedge/Toros](https://github.com/dhedge/V2-Public) `todo`

## Contributing
Contributions are welcome, reach out at the DAO to claim rewards based on your work.
Up to 20% of a strategy realized profits are claimable by their designer to the DAO treasury.

Astrolab DAO vetting process on strategy submission will be similar to [that of Yearn](https://docs.yearn.fi/developers/v3/strategy_writing_guide)

Feel free to open an issue or create a pull request if you have any improvements or suggestions.

Built with ❤️ at [EthGlobal Istanbul 2k23](https://ethglobal.com/events/istanbul)
