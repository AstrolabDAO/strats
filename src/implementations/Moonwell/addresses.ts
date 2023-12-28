import addresses from "../../addresses";
import merge from "lodash/merge";

// cf. https://docs.moonwell.fi/moonwell/protocol-information/contracts
export default merge(addresses, {
  // base
  8453: {
    Moonwell: {
      Comptroller: "0xfBb21d0380beE3312B33c4353c8936a0F13EF26C",
      TemporalGovernor: "​0x8b621804a7637b781e2BbD58e256a591F2dF7d51​",
      MultiRewardDistributor: "​0xe9005b078701e2A0948D2EaC43010D35870Ad9d2​",
      mDAI: "0x73b06D8d18De422E269645eaCe15400DE7462417",
      mUSDC: "0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22",
      mUSDbC: "0x703843C3379b52F9FF486c9f5892218d2a065cC8",
      mWETH: "​0x628ff693426583D9a7FB391E54366292F509D457​",
      mcbETH: "​0x3bf93770f2d4a794c3d9EBEfBAeBAE2a8f09A5E5​",
      mwstETH: "​0x627Fe393Bc6EdDA28e99AE648fD6fF362514304b​",
      mrETH: "​0xcb1dacd30638ae38f2b94ea64f066045b7d45f44​",
      WETHRouter: "​0x31CCFB038771d9bF486Ef7c7f3A9F91bE72124C4​",
      ChainlinkOracle: "​0xEC942bE8A8114bFD0396A5052c36027f2cA6a9d0​",

      rewardTokens: [addresses[8453].tokens.WELL],
    }
  },
  // moonbeam
  1284: {
    Moonwell: {
      Comptroller: "0x8E00D5e02E65A19337Cdba98bbA9F84d4186a180",
      ChainlinkOracle: "​0xED301cd3EB27217BDB05C4E9B820a8A3c8B665f9​",
      Maximillion: "​0xe5Ef9310cC7E3437bAD83466675f24FD62A380c3​",
      EcosystemReserve: "​0x7793E08Eb4525309C46C9BA394cE33361A167ba4​",
      EcosystemReserveController: "​0xCa889f40aae37FFf165BccF69aeF1E82b5C511B9​",
      GovernorAlpha: "​0xfc4DFB17101A12C5CEc5eeDd8E92B5b16557666d​",
      breakGlassGuardian: "​0x5402447a0db03EeE98c98b924F7d346bd19cdD17​",
      Timelock: "​0x3a9249d70dCb4A4E9ef4f3AF99a3A130452ec19B​",
      mGLMR: "​0x091608f4e4a15335145be0A279483C0f8E4c7955​",
      mxcDOT: "​0xD22Da948c0aB3A27f5570b604f3ADef5F68211C3​",
      mxcUSDT: "​0x42A96C0681B74838eC525AdbD13c37f66388f289​",
      mFRAX: "0x1C55649f73CDA2f72CEf3DD6C5CA3d49EFcF484C",
      mUSDC: "0x744b1756e7651c6D57f5311767EAFE5E931D615b",
      mwhUSDC: "0x744b1756e7651c6D57f5311767EAFE5E931D615b",
      mxcUSDC: "​0x22b1a40e3178fe7c7109efcc247c5bb2b34abe32​",
      mwhETH: "​0xb6c94b3A378537300387B57ab1cC0d2083f9AeaC​",
      mwhWBTC: "​0xaaa20c5a584a9fECdFEDD71E46DA7858B774A9ce​",
      stkWELL: "​0x8568A675384d761f36eC269D695d6Ce4423cfaB1​",

      rewardTokens: [addresses[1284].tokens.WELL, addresses[1284].tokens.WGLMR],
    }
  },
  // moonriver
  // 1285: {
  //   Moonwell: {
  //     Comptroller: "​0x0b7a0EAA884849c6Af7a129e899536dDDcA4905E​",
  //     ChainlinkOracle: "​0x892bE716Dcf0A6199677F355f45ba8CC123BAF60​",
  //     Maximillion: "​0x1650C0AD9483158f9e240fd58d0E173807A80CcC​",
  //     EcosystemReserve: "​0xbA17581Bb6d89954B42fB84294e476e97588908B​",
  //     EcosystemReserveController: "​0xD94F826C17e870a6327B7b1de6B43C5a9Ef21044​",
  //     GovernorAlpha: "​0x2BE2e230e89c59c8E20E633C524AD2De246e7370​",
  //     breakGlassGuardian: "​0x5DeD9d1025a158554Ab19540Ae83182d890Bb8DB​",
  //     Timelock: "​0x04e6322D196E0E4cCBb2610dd8B8f2871E160bd7​",
  //     mMOVR: "​0x6a1A771C7826596652daDC9145fEAaE62b1cd07f​",
  //     mxcKSM: "​0xa0d116513bd0b8f3f14e6ea41556c6ec34688e0f​",
  //     mETH: "​0x6503D905338e2ebB550c9eC39Ced525b612E77aE​",
  //     mUSDC: "​0xd0670AEe3698F66e2D4dAf071EB9c690d978BFA8​",
  //     mUSDT: "​0x36918B66F9A3eC7a59d0007D8458DB17bDffBF21​",
  //     mFRAX: "​0x93Ef8B7c6171BaB1C0A51092B2c9da8dc2ba0e9D​",
  //     mWBTC: "​0x6E745367F4Ad2b3da7339aee65dC85d416614D90​",
  //     stkWELL: "​0xCd76e63f3AbFA864c53b4B98F57c1aA6539FDa3a​", // staked WELL (MFAM)
  //     rewardTokens: [addresses[1285].tokens.WELL, addresses[1285].tokens.MOVR], (WELL == MFAM)
  //   }
  // }
} as { [chainId: number]: { [id: string]: any } });
