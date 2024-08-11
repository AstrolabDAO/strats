import { addresses } from "@astrolabs/hardhat";
import merge from "lodash/merge";

// cf. https://https://docs.aave.com/developers/deployed-contracts/v3-mainnet/
export default merge(addresses, {
  10: {
    Toros: {
      DHedgeEasySwapper: "0x3988513793bce39f0167064a9f7fc3617faf35ab",
      USDy: "0x1ec50880101022c11530a069690f5446d1464592", // Stablecoin Yield (Optimism)
      USDpy: "0xb9243c495117343981ec9f8aa2abffee54396fc0", // Perpetual Delta Neutral Yield (Optimism)
      USDmny: "0x49bf093277bf4dde49c48c6aa55a3bda3eedef68", // USD Delta Neutral Yield (Optimism)
      ETHy: "0xb2cfb909e8657c0ec44d3dd898c1053b87804755", // Ethereum Yield (Optimism)
      dSNX: "0x59babc14dd73761e38e5bda171b2298dc14da92d", // Synthetix Debt Hedge (Optimism)
      BTCBULL2X: "0x32ad28356ef70adc3ec051d8aacdeeaa10135296", // Bitcoin Bull 2X (Optimism)
      BTCBEAR1X: "0x83d1fa384ec44c2769a3562ede372484f26e141b", // Bitcoin Bear 1X (Optimism)
      ETHBULL2X: "0x9573c7b691cdcebbfa9d655181f291799dfb7cf5", // Ethereum Bull 2X (Optimism)
      ETHBEAR1X: "0xcacb5a722a36cff6baeb359e21c098a4acbffdfa", // Ethereum Bear 1X (Optimism)
    }
  },
  137: {
    Toros: {
      ETHGOLDi: "0xcdba5e22d5f013669f1c6ad7ad86bb2095358058", // Ethereum-Gold Index (Polygon)
      ETHBEAR2X: "0x027da30fadab6202801f97be344e2348a2a92842", // Ethereum Bear 2X (Polygon)
      ETHBULL3X: "0x460b60565cb73845d56564384ab84bf84c13e47d", // Ethereum Bull 3X (Polygon)
      ETHBEAR1X: "0x79d2aefe6a21b26b024d9341a51f6b7897852499", // Ethereum Bear 1X (Polygon)
      BTCBULL3X: "0xdb88ab5b485b38edbeef866314f9e49d095bce39", // Bitcoin Bull 3X (Polygon)
      BTCBEAR1X: "0x86c3dd18baf4370495d9228b58fd959771285c55", // Bitcoin Bear 1X (Polygon)
      BTCBEAR2X: "0x3dbce2c8303609c17aa23b69ebe83c2f5c510ada", // Bitcoin Bear 2X (Polygon)
      MATICBULL2X: "0x7dab035a8a65f7d33f1628a450c6780323d3c5e1", // MATIC Bull 2X (Polygon)
      MATICBEAR1X: "0x8987ca55e635d0d3ba9469ee31e9b8a7d447e9cc", // MATIC Bear 1X (Polygon)
    }
  },
  42161: {
    Toros: {
      USDsdn: "0xd5f4a300ab7a786245281452be9039abc8cc8e40", // Swell USD Delta Neutral Yield
    }
  }
} as { [chainId: number]: { [id: string]: any } });