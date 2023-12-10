import addresses from "../../addresses";
import merge from "lodash/merge";

// cf. https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
export default merge(addresses, {
  // ethereum
  1: {
    Stargate: {
      Router: "0x8731d54E9D02c286767d56ac03e8037C07e01e98",
      RouterETH: "0x150f94B44927F078737562f0fcF3C95c01Cc2376", // front-end
      RouterETH2: "0xb1b2eeF380f21747944f46d28f683cD1FBB4d03c", // can swap with payload
      Bridge: "0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97",
      Factory: "0x06D538690AF257Da524f25D0CD52fFd85b1c2173E",
      StargateToken: "0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6",
      StargateFeeLibraryV07: "0x8C3085D9a554884124C998CDB7f6d7219E9C1e6F",
      StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
      WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
      Pool: {
        ETH: "0x101816545F6bd2b1076434B54383a1E633390A2E",
        USDC: "0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56",
        USDT: "0x38EA452219524Bb87e18dE1C24D3bB59510BD783",
        USDD: "0x692953e758c3669290cb1677180c64183cEe374e",
        DAI: "0x0Faf1d2d3CED330824de3B8200fc8dc6E397850d",
        FRAX: "0xfA0F307783AC21C39E939ACFF795e27b650F6e68",
        sUSD: "0x590d4f8A68583639f215f675F3a259Ed84790580",
        LUSD: "0xE8F55368C82D38bbbbDb5533e7F56AfC2E978CC2",
        MAI: "0x9cef9a0b1bE0D289ac9f4a98ff317c33EAA84eb8",
        METIS: "0xd8772edBF88bBa2667ed011542343b0eDDaCDa47",
        mUSDT: "0x430Ebff5E3E80A6C58E7e6ADA1d90F5c28AA116d", // metis USDT
      },
      LPStaking: "0xB0D502E938ed5f4df2E681fE6E419ff29631d62b",
      LPStakingTimeMetis: "0x1c3000b8f475A958b87c73a5cc5780Ab763122FC",
    },
  },
  // bsc
  56: {
    Stargate: {
      Router: "0x4a364f8c717cAAD9A442737Eb7b8A55cc6cf18D8",
      Bridge: "0x6694340fc020c5E6B96567843da2df01b2CE1eb6",
      Factory: "0xe7Ec689f432f29383f217e36e680B5C855051f25",
      StargateToken: "0xB0D502E938ed5f4df2E681fE6E419ff29631d62b",
      StargateFeeLibraryV07: "0xCA6522116e8611A346D53Cc2005AC4192e3fc2BC",
      StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
      WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
      Pool: {
        USDT: "0x9aA83081AA06AF7208Dcc7A4cB72C94d057D2cda",
        BUSD: "0x98a5737749490856b401DB5Dc27F522fC314A4e1",
        USDD: "0x4e145a589e4c03cBe3d28520e4BF3089834289Df",
        MAI: "0x7BfD7f2498C4796f10b6C611D9db393D3052510C",
        METIS: "0xD4CEc732b3B135eC52a3c0bc8Ce4b8cFb9dacE46",
        mUSDT: "0x68C6c27fB0e02285829e69240BE16f32C5f8bEFe", // metis USDT
      },
      LPStaking: "0x3052A0F6ab15b4AE1df39962d5DdEFacA86DaB47",
      LPStakingTimeMetis: "0x2c6dcEd426D265045737Ff55C2D746C11b2F457a",
    },
  },
  // avalanche
  43114: {
    Stargate: {
      Router: "0x45A01E4e04F14f7A4a6702c74187c5F6222033cd",
      Bridge: "0x9d1B1669c73b033DFe47ae5a0164Ab96df25B944",
      Factory: "0x808d7c71ad2ba3FA531b068a2417C63106BC0949",
      StargateToken: "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590",
      StargateFeeLibraryV07: "0x5E8eC15ACB5Aa94D5f0589E54441b31c5e0B992d",
      StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
      WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
      Pool: {
        USDC: "0x1205f31718499dBf1fCa446663B532Ef87481fe1",
        USDT: "0x29e38769f23701A2e4A8Ef0492e19dA4604Be62c",
        FRAX: "0x1c272232Df0bb6225dA87f4dEcD9d37c32f63Eea",
        MAI: "0x8736f92646B2542B3e5F3c63590cA7Fe313e283B",
        mUSDT: "0xEAe5c2F6B25933deB62f754f239111413A0A25ef", // metis USDT
      },
      LPStaking: "0x8731d54E9D02c286767d56ac03e8037C07e01e98",
    },
  },
  // metis
  1088: {
    Stargate: {
      Router: "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590",
      Bridge: "0x45f1A95A4D3f3836523F5c83673c797f4d4d263B",
      Factory: "0xAF54BE5B6eEc24d6BFACf1cce4eaF680A8239398",
      StargateToken: "N/A",
      StargateFeeLibraryV07: "0x55bDb4164D28FBaF0898e0eF14a589ac09Ac9970",
      StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
      WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
      Pool: {
        METIS: "0xAad094F6A75A14417d39f04E690fC216f080A41a",
        mUSDT: "0x2b60473a7C41Deb80EDdaafD5560e963440eb632", // metis USDT
      },
      LPStakingTimeMetis: "0x45A01E4e04F14f7A4a6702c74187c5F6222033cd",
    },
  },
  // polygon
  137: {
    Stargate: {
      Router: "0x45A01E4e04F14f7A4a6702c74187c5F6222033cd",
      Bridge: "0x9d1B1669c73b033DFe47ae5a0164Ab96df25B944",
      Factory: "0x808d7c71ad2ba3FA531b068a2417C63106BC0949",
      StargateToken: "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590",
      StargateFeeLibraryV07: "0xb279b324Ea5648bE6402ABc727173A225383494C",
      StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
      WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
      Pool: {
        USDCe: "0x1205f31718499dBf1fCa446663B532Ef87481fe1",
        USDT: "0x29e38769f23701A2e4A8Ef0492e19dA4604Be62c",
        DAI: "0x1c272232Df0bb6225dA87f4dEcD9d37c32f63Eea",
        MAI: "0x8736f92646B2542B3e5F3c63590cA7Fe313e283B",
      },
      LPStaking: "0x8731d54E9D02c286767d56ac03e8037C07e01e98",
    },
  },
  // arbitrum
  42161: {
    Stargate: {
      Router: "0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614",
      RouterETH: "0xbf22f0f184bCcbeA268dF387a49fF5238dD23E40", // front-end
      RouterETH2: "0xb1b2eeF380f21747944f46d28f683cD1FBB4d03c", // can swap with payload
      Bridge: "0x352d8275AAE3e0c2404d9f68f6cEE084B5bEB3DD",
      Factory: "0x55bDb4164D28FBaF0898e0eF14a589ac09Ac9970",
      StargateToken: "0x6694340fc020c5E6B96567843da2df01b2CE1eb6",
      StargateFeeLibraryV07: "0x1cF31666c06ac3401ed0C1c6346C4A9425dd7De4",
      StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
      WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
      Pool: {
        ETH: "0x915A55e36A01285A14f05dE6e81ED9cE89772f8e",
        USDCe: "0x892785f33CdeE22A30AEF750F285E18c18040c3e",
        USDT: "0xB6CfcF89a7B22988bfC96632aC2A9D6daB60d641",
        FRAX: "0xaa4BF442F024820B2C28Cd0FD72b82c63e66F56C",
        MAI: "0xF39B7Be294cB36dE8c510e267B82bb588705d977",
        LUSD: "0x600E576F9d853c95d58029093A16EE49646F3ca5",
      },
      LPStakingTime: "0x9774558534036Ff2E236331546691b4eB70594b1",
    },
  },
  // optimism
  10: {
    Stargate: {
      Router: "0xB0D502E938ed5f4df2E681fE6E419ff29631d62b",
      RouterETH: "0xB49c4e680174E331CB0A7fF3Ab58afC9738d5F8b", // front-end
      RouterETH2: "0xb1b2eeF380f21747944f46d28f683cD1FBB4d03c", // can swap with payload
      Bridge: "0x701a95707A0290AC8B90b3719e8EE5b210360883",
      Factory: "0xE3B53AF74a4BF62Ae5511055290838050bf764Df",
      StargateToken: "0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97",
      StargateFeeLibraryV07: "0x505eCDF2f14Cd4f1f413d04624b009A449D38D7E",
      StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
      WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
      Pool: {
        ETH: "0xd22363e3762cA7339569F3d33EADe20127D5F98C",
        USDCe: "0xDecC0c09c3B5f6e92EF4184125D5648a66E35298",
        DAI: "0x165137624F1f692e69659f944BF69DE02874ee27",
        FRAX: "0x368605D9C6243A80903b9e326f1Cddde088B8924",
        sUSD: "0x2F8bC9081c7FCFeC25b9f41a50d97EaA592058ae",
        LUSD: "0x3533F5e279bDBf550272a199a223dA798D9eff78",
        MAI: "0x5421FA1A48f9FF81e4580557E86C7C0D24C18036",
      },
      LPStakingTime: "0x4DeA9e918c6289a52cd469cAC652727B7b412Cd2",
    },
    // base
    8453: {
      Stargate: {
        Router: "0x45f1A95A4D3f3836523F5c83673c797f4d4d263B",
        RouterETH: "0x50B6EbC2103BFEc165949CC946d739d5650d7ae4",
        Bridge: "0xAF54BE5B6eEc24d6BFACf1cce4eaF680A8239398",
        Factory: "0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6",
        StargateToken: "0xE3B53AF74a4BF62Ae5511055290838050bf764Df",
        StargateFeeLibraryV07: "0x9d1b1669c73b033dfe47ae5a0164ab96df25b944",
        StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
        WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
        Pool: {
          SGETH: "0x28fc411f9e1c480AD312b3d9C60c22b965015c6B",
          USDC: "0x4c80E24119CFB836cdF0a6b53dc23F04F7e652CA",
        },
        LPStakingTime: "0x06Eb48763f117c7Be887296CDcdfad2E4092739C",
      },
    },
    // fantom
    250: {
      Stargate: {
        Router: "0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6",
        Bridge: "0x45A01E4e04F14f7A4a6702c74187c5F6222033cd",
        Factory: "0x9d1B1669c73b033DFe47ae5a0164Ab96df25B944",
        StargateToken: "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590",
        StargateFeeLibraryV07: "0x616a68BD6DAd19e066661C7278611487d4072839",
        StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
        WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
        Pool: {
          SGUSDC: "0xc647ce76ec30033aa319d472ae9f4462068f2ad7",
        },
        LPStaking: "0x224D8Fd7aB6AD4c6eb4611Ce56EF35Dec2277F03",
      },
    },
    // linea
    59144: {
      Stargate: {
        Router: "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590",
        RouterETH: "0x8731d54E9D02c286767d56ac03e8037C07e01e98",
        Bridge: "0x45f1A95A4D3f3836523F5c83673c797f4d4d263B",
        Factory: "0xaf54be5b6eec24d6bfacf1cce4eaf680a8239398",
        StargateToken: "0x808d7c71ad2ba3FA531b068a2417C63106BC0949",
        StargateFeeLibraryV07: "0x45A01E4e04F14f7A4a6702c74187c5F6222033cd",
        StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
        WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
        Pool: {
          WETH: "0xAad094F6A75A14417d39f04E690fC216f080A41a",
        },
        LPStakingTime: "0x4a364f8c717cAAD9A442737Eb7b8A55cc6cf18D8",
      },
    },
    // kava
    // 2222: {
    //   Stargate: {
    //     Router: "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590",
    //     Bridge: "0x45f1A95A4D3f3836523F5c83673c797f4d4d263B",
    //     Factory: "0xAF54BE5B6eEc24d6BFACf1cce4eaF680A8239398",
    //     StargateToken: "0x83c30eb8bc9ad7C56532895840039E62659896ea",
    //     StargateFeeLibraryV07: "0x45a01e4e04f14f7a4a6702c74187c5f6222033cd",
    //     StargateComposer: "0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9",
    //     WidgetSwap: "0x10d16248bED1E0D0c7cF94fFD99A50c336c7Bcdc",
    //     Pool: {
    //       USDT: "0xAad094F6A75A14417d39f04E690fC216f080A41a",
    //     },
    //     LPStakingTime: "0x35F78Adf283Fe87732AbC9747d9f6630dF33276C",
    //   },
    // },
    // mantle
    5000: {
      Stargate: {
        Router: "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590",
        Bridge: "0x45f1A95A4D3f3836523F5c83673c797f4d4d263B",
        Factory: "0xAF54BE5B6eEc24d6BFACf1cce4eaF680A8239398",
        StargateToken: "0x8731d54E9D02c286767d56ac03e8037C07e01e98",
        StargateFeeLibraryV07: "0x45A01E4e04F14f7A4a6702c74187c5F6222033cd",
        StargateComposer: "0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97",
        WidgetSwap: "0x06D538690AF257Da524f25D0CD52fD85b1c2173E",
        Pool: {
          USDC: "0xAad094F6A75A14417d39f04E690fC216f080A41a",
          USDT: "0x2b60473a7C41Deb80EDdaafD5560e963440eb632",
        },
        LPStakingTime: "0x352d8275AAE3e0c2404d9f68f6cEE084B5bEB3DD",
      },
    },
  }
} as { [chainId: number]: { [id: string]: any } });
