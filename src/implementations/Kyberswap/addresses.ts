import addresses from "../../addresses";
import merge from "lodash/merge";

// cf. https://github.com/hop-protocol/hop/blob/develop/packages/core/src/addresses/mainnet.ts
export default merge(addresses, {
  // scroll
  534352: {
    kyberswap: {
      USDC_USDT: {
        router: ' 0xF9c2b5746c946EF883ab2660BbbB1f10A5bdeAb4',
        antisnip: '0xe222fBE074A436145b255442D919E4E3A6c6a480', // AntiSnipAttackPositionManager
        tickfeesreader: '0x8Fd8Cb948965d9305999D767A02bf79833EADbB3' // TicksFeesReader
    },
    }
  }
} as { [chainId: number]: { [id: string]: any } });
