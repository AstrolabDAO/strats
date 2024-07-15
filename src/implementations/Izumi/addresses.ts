import { addresses } from "@astrolabs/hardhat";
import merge from "lodash/merge";

export default merge(addresses, {
  // scroll
  534352: {
    izumi: {
      USDC_USDT: {
        liquidityManager: '0x1502d025bfa624469892289d45c0352997251728', // iZiSwap Liquidity NFT
      },
    }
  }
} as { [chainId: number]: { [id: string]: any } });
