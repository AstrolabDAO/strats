import addresses from "../../addresses";
import merge from "lodash/merge";

export default merge(addresses, {
  // scroll
  534352: {
    syncswap: {
      DAI_USDT: {
        router: '0x80e38291e06339d10AAB483C65695D004dBD5C69', // 
        pool: '0x52dBD671CFBc50C17F50529059f3d6c70E5403d8', // SyncSwapStablePool
      },
    }
  }
} as { [chainId: number]: { [id: string]: any } });
