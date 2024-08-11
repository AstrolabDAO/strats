import { addresses } from "@astrolabs/hardhat";
import merge from "lodash/merge";

// cf. https://www.vaultka.com/app/vaults
export default merge(addresses, {
  // arbitrum
  42161: {
    Vaultka: {
      // v2 lending/gearing pools
      USDCeLendingV2: "0x806e8538FC05774Ea83d9428F778E423F6492475", // sakeWaterV2
      USDCLendingV2: "0x9045ae36f963b7184861BDce205ea8B08913B48c", // vodkaV2 water
      ETHLendingV2: "0x8A98929750e6709Af765F976c6bddb5BfFE6C06c", // vodkaV2DN_ETH_Water
      ARBLendingV2: "0x175995159ca4F833794C88f7873B3e7fB12Bb1b6", // vodkaV2DN_ARB_Water
      BTCLendingV2: "0x4e9e41Bbf099fE0ef960017861d181a9aF6DDa07", // vodkaV2DN_BTC_Water

      // v1 lending/gearing pools (deprecated)
      // DAILendingV1: "0xa100E02e861132C4703ae96D6868664f27Eaa431", // whiskeyWater
      // USDCeLendingV1: "0x6b367F9EB22B2E6074E9548689cddaF9224FC0Ab", // sakeWater
      // USDCLendingV1: "0xC99C6427cB0B824207606dC2745A512C6b066E7C", // vodkaV1_Water

      // v2 vaults
      VLPLeverage: "0xc53A53552191BeE184557A15f114a87a757e5b6F", // sake
      ALPLeverage: "0x482368a8E701a913Aa53CB2ECe40F370C074fC7b", // gin
      GLPLeverageV1A: "0x0E8A12e59C2c528333e84a12b0fA4B817A35909A", // vodkav1
      GMLeverage: "0x9198989a85E35adeC46309E06684dCA444c9cF27", // vodkaV2
      HLPLeverage: "0x739fe1BE8CbBeaeA96fEA55c4052Cd87796c0a89", // rum
      GLPCompound: "0x9566db22DC32E54234d2D0Ae7B72f44e05158239", // agedVodka
      GMLeverageNeutral: "0x316142C166AdA230D0aFAD9493ef4bF053289269", // vodkaV2DN
      GMCompoundETH: "0xE502474DfC23Cd11C28c379819Ea97A69aF7E10F", // agedVodkaV2_ETH
      GMCompoundBTC: "0x83C8A6B6867A3706a99573d39dc65a6805D26770", // agedVodkaV2_BTC
      GLPNeutral: "0x0081772FD29E4838372CbcCdD020f53954f5ECDE", // dilutedVodka
      gDAILeverage: "0x6532eFCC1d617e094957247d188Ae6d54093718A", // whiskey

      // Staking
      VaultkaStaking: "0x314223E2fA375F972E159002Eb72A96301E99e22", // singleStaking
      // v1 vaults (deprecated)
      // VLPLeverageV1: "0x45BeC5Bb0EE87181A7Aa20402C66A6dC4A923758", // legacy sake/esVELA
      // GLPLeverage: "0x88D7500aF99f11fF52E9f185C7aAFBdF9acabD93", // vodkaV1

      // gmx
      gmWeth: "0x70d95587d40A2caf56bd97485aB3Eec10Bee6336", // weth/usdc.e
      gmArb: "0xC25cEf6061Cf5dE5eb761b50E4743c1F5D7E5407", // arb/usdc.e
      gmBtc: "0x47c031236e19d024b42f8AE6780E44A573170703", // btc/usdc.e
      // vela
      VLP: "0xc5b2d9fda8a82e8dcecd5e9e6e99b78a9188eb05",
      // gtrade
      gDAI: "0xd85e038593d7a098614721eae955ec2022b9b91b",
      // hmx
      hlpStaking: "0xbE8f8AF5953869222eA8D39F1Be9d03766010B1C",
      hlp: "0x4307fbDCD9Ec7AEA5a1c2958deCaa6f316952bAb",

    }
  },
} as { [chainId: number]: { [id: string]: any } });
