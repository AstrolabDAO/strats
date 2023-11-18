import addresses from "../../addresses";
import merge from "lodash/merge";

// cf. https://devs.spark.fi/deployment-addresses/
export default merge(addresses, {
  // eth
  1: {
    spark: {
      DAI: {
        lp: '0x4DEDf26112B3Ec8eC46e7E31EA5e123490B05B8B', // _aToken
        pool: '0xC13e21B648A5Ee794902342038FF3aDAB66BE987' // pool
      }
    },
  }, 
  // xdai
  100: {
    spark: {
      WXDAI: {
        lp: '0xC9Fe2D32E96Bb364c7d29f3663ed3b27E30767bB', // _aToken
        pool: '0x2Dae5307c5E3FD1CF5A72Cb6F698f915860607e0' // pool
      }
    }
  },
} as { [chainId: number]: { [id: string]: any } });
