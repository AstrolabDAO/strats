import addresses from "../../addresses";
import merge from "lodash/merge";;
// cf. https://https://docs.aave.com/developers/deployed-contracts/v3-mainnet/
export default merge(addresses, {
  // op
  10: {
    aave: {
      USDC: {
        lp: "0x625E7708f30cA75bfd92586e17077590C60eb4cD", // _aToken
        pool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD", // pool
      },
    },
  },
  // xdai
  100: {
    aave: {
      XDAI: {
        lp: "0xd0Dd6cEF72143E22cCED4867eb0d5F2328715533", // _aToken
        pool: "0xb50201558B00496A145fE76f7424749556E326D8", // pool
      },
    },
  },
  42161: {
    aave: {
      DAI: {
        lp: "0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE", // _aToken
        pool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD", //pool
      },
    },
  },
} as { [chainId: number]: { [id: string]: any } });
