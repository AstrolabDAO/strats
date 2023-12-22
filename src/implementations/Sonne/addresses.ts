import addresses from "../../addresses";
import merge from "lodash/merge";

// cf. https://docs.sonne.finance/protocol/contract-addresses
export default merge(addresses, {
  // op
  10: {
    Sonne: {
        Unitroller: "0x60CF091cD3f50420d50fD7f707414d0DF4751C58",
        ComptrollerImplementation: "0xDb0C52f1F3892e179a69b19aa25dA2aECe5006ac",
        TeamVestingClaim: "0xb4bf17210844418f9f2d3b90036e11aa40517971",
        PriceOracle: "0xEFc0495DA3E48c5A55F73706b249FD49d711A502",
        InterestRateModel: "0xbbbd75383f6A61d5EB5b43e94E6372Df6F7f13c6",
        soWETH: "0xf7B5965f5C117Eb1B5450187c9DcFccc3C317e8E",
        soDAI: "0x5569b83de187375d43FBd747598bfe64fC8f6436",
        soUSDC: "0xEC8FEa79026FfEd168cCf5C627c7f486D77b765F",
        soUSDT: "0x5Ff29E4470799b982408130EFAaBdeeAE7f66a10",
        soOP: "0x8cD6b19A07d754bF36AdEEE79EDF4F2134a8F571",
        soSUSD: "0xd14451E0Fa44B18f9a4f65e031af09fced171166",
        uSONNE: "0x41279e29586eb20f9a4f65e031af09fced171166",
        sSONNE: "0xdc05d85069dc4aba65954008ff99f2d73ff12618",
        soSNX: "0xD7dAabd899D1fAbbC3A9ac162568939CEc0393Cc",
        soWBTC: "0x33865E09A572d4F1CC4d75Afc9ABcc5D3d4d867D",
        soLUSD: "0xAFdf91f120DEC93c65fd63DBD5ec372e5dcA5f82",
        sowstETH: "0x26AaB17f27CD1c8d06a0Ad8E4a1Af8B1032171d5",
        soMAI: "0xE7De932d50EfC9ea0a7a409Fc015B4f71443528e",
        Multisig: "0x784B82a27029C9E114b521abcC39D02B3D1DEAf2",
        SONNEUSDC_LP: "0xc899C4D73ED8dF2eAd1543AB915888B0Bf7d57a2", // velodrome LP
        rewardTokens: [addresses[10].tokens.SONNE, addresses[10].tokens.OP],
    }
  },
  // base
  8453: {
    Sonne: {
        Unitroller: "0x1DB2466d9F5e10D7090E7152B68d62703a2245F0",
        ComptrollerImplementation: "0x076c7883e154F6Cc0cA04888288b350d78cf1321",
        Multisig: "0x814ae3e7Bc6B20b4Da64b76A7E66BCa0993F22A8",
        SONNE: "0x22a2488fE295047Ba13BD8cCCdBC8361DBD8cf7c",
        sobWETH: "0x5F5c479fe590cD4442A05aE4a941dd991A633B8E",
        sobDAI: "0xb864BA2aab1f53BC3af7AE49a318202dD3fd54C2",
        sobUSDbC: "0x225886C9beb5eeE254F79d58bbD80cf9F200D4d0",
        sobUSDC: "0xfd68F92B45b633bbe0f475294C1A86aecD62985A",
        rewardTokens: [addresses[8453].tokens.SONNE],
    }
  },
} as { [chainId: number]: { [id: string]: any } });
