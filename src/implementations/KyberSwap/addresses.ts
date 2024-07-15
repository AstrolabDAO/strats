import { addresses } from "@astrolabs/hardhat";
import merge from "lodash/merge";

// cf. https://github.com/hop-protocol/hop/blopb/develop/packages/core/src/addresses/mainnet.ts
export default merge(addresses, {
  // scroll
  534352: {
    "KyberSwap.USDC-USDT": {
      router: ' 0xF9c2b5746c946EF883ab2660BbbB1f10A5bdeAb4', // Router
      elasticLM: '0x7D5ba536ab244aAA1EA42aB88428847F25E3E676', // KSElasticLMV2
      tickfeesreader: '0x8Fd8Cb948965d9305999D767A02bf79833EADbB3', // TicksFeesReader
      antisnip: '0xe222fBE074A436145b255442D919E4E3A6c6a480', // AntiSnipAttackPositionManager
      pool: '0x77D607915D5bb744C9DF049c2144f48Aa9bb2e30', // Pool
    }
  }
} as { [chainId: number]: { [id: string]: any } });
