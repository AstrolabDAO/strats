import { addresses } from "@astrolabs/hardhat";
import merge from "lodash/merge";

// cf. https://docs.sonne.finance/protocol/contract-addresses
export default merge(addresses, {
  // arbitrum
  42161: {
    Lodestar: {
        // v1
        Unitroller: "0xa86DD95c210dd186Fa7639F93E4177E97d057576",
        Comptroller: "0xe64e44c97f9a019f70f8cdb3f4d3d465c56e9ab2",
        lDPX: "0x5d27cFf80dF09f28534bb37d386D43aA60f88e25",
        lFRAX: "0xD12d43Cdf498e377D3bfa2c6217f05B466E14228",
        lMAGIC: "0xf21Ef887CB667f84B8eC5934C1713A7Ade8c38Cf",
        lPLVGLP: "0xeA0a73c17323d1a9457D722F10E7baB22dc0cB83",
        lUSDCe: "0x1ca530f02DD0487cef4943c674342c5aEa08922F",
        lUSDT: "0x9365181A7df82a1cC578eAE443EFd89f00dbb643",
        lWBTC: "0xC37896BF3EE5a2c62Cdbd674035069776f721668",
        lDAI: "0x4987782da9a63bC3ABace48648B15546D821c720",
        lETH: "0x2193c45244AF12C280941281c8aa67dD08be0a64",
        lARB: "0x8991d64fe388fA79A4f7Aa7826E8dA09F0c3C96a",
        lwstETH: "0xfECe754D92bd956F681A941Cef4632AB65710495",
        lGMX: "0x79B6c5e1A7C0aD507E1dB81eC7cF269062BAb4Eb",
        lUSDC: "0x4C9aAed3b8c443b4b634D1A189a5e25C604768dE",

        Loopy: "0xd77fEbE1eb7823DE6e006D96066bb3bA3B5BCa69",
        LodestarHandler: "0x8c893364c7141197a52f8eebc049c161b8c3e9f7",
        LodestarLens: "0x24C25910aF4068B5F6C3b75252a36c4810849135",
        StakingRewardsProxy: "0x8ab1774A6FC5eE51559964e13ECD54155340c116",
        StakingRewards: "0x7AE5D241Ee2D9CDa7Fd392604e05eD5252D031c5",
        VotingPowerProxy: "0xFf4eF7844fAFF2bb20a8ba5E479b0a67d8642146",
        VotingPower: "0x1b933F3601F9CAD015A8f4791D407a40e8CA90Ad",
        TokenClaim: "0xd69ee8a388652a712186E327Cfdf6db2bc76C898",
        esLODE: "0x501f4f041655a3CEDd4211FE5ECdC27738D88aF2",
        RewardRouterProxy: "0xBEeCf02818A3664F49f7465CFF854f1FC5081Cd3",
        RewardRouter: "0x0b6e0656003a426323ac328721229edb77d224c9",
        Whitelist: "0xbBCDeBe4615379345ABD7030B04e62Ae43f61737",
        Maximillion: "0xDB1Ae8C1B5A387147DE628BcaD837Fe7A4190284",
        PriceOracleProxyETH: "0xcCf9393df2F656262FD79599175950faB4D4ec01",
        JumpRateModel1: "0xEc68bc9190c815289a5a187cA88d3769A4406DCf",
        JumpRateModel2: "0x0c6f39040b4eAaa8970b6Ec07ADa9F9151d352fB",
        JumpRateModel3: "0xB74e21f4B73380ABf617AFFe8C564A612B655d93",
        JumpRateModel4: "0x8181deA7f49B30175eF3E14B1B86412c17B0961C",
        JumpRateModel5: "0x06D322a466993fd394C99d73C601eB88239F300f",
        DPXDelegate: "0xfAD157A82243546832bb40121e2f9132DF833Bb1",
        MAGICDelegate: "0x48bf1D7966Cc74f57E39c55FE6bdE5f456f0335B",
        USDCeDelegate: "0xEA1dCc22339520a9E5442C3B9315eCf41d24dDec",
        USDCDelegate: "0x254936d0451F0198272f9C64bcdA2534061fbBcC",
        USDTDelegate: "0x5ff0b96F0B1BA8A441BAa9eE3aCbec94517a3D9B",
        WBTCDelegate: "0x1D8f62736CCcDdddd0914E5822743d6a54C60Fe1",
        FRAXDelegate: "0xfC47e6A405402A7dA7D66d360cC58D2F93f81f47",
        PLVGLPDelegate: "0x3bBfBE6FA43D75413968b1C9A7b7305E4d36e47C",
        DAIDelegate: "0x0b2C0a787cf2E13bab703Fd5b12f21dbdb0706b1",
        ETHDelegate: "0xf96Bc59fC200B485fE5A84Cc077529De3627b24B",
        ARBDelegate: "0x8a76ff3410ED18a404eA5624a2C2c145a16b0f5d",
        wstETHDelegate: "0xb7F7d0790b21DECc56493Fdb62C690B2C1a9a7Ba",
        GMXDelegate: "0xFAB93372A50878a340DD03079Ff332f33B36DB65",
        Reservior: "0x941a4EE8a96e0EEd086D5853c3661Bc4f2357ef2",
        TokenFix: "0x8dF8E39103F196820EA56403733a79C60086608C",
        Disperse2: "0x3aEd259BE916F6Fb4f44Adf05a3CE37DFa1AD3cF",
        TeamVesting1: "0x05bc2c8310D18dB816264E95383b1C50FC32d297",
        TeamVesting2: "0x2dd5b039a7c54132b8733573a28cd9d1a5fa5328",
        TeamVesting3: "0x71c85f343715c406c58c1e8099f13890f2925c85",
        rewardTokens: [addresses[42161].tokens.LODE, addresses[42161].tokens.ARB],
    }
  },

} as { [chainId: number]: { [id: string]: any } });
