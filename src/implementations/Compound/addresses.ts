import addresses from "../../addresses";
import merge from "lodash/merge";

// cf. https://github.com/compound-finance/comet/tree/main/deployments
export default merge(addresses, {
  // ethereum
  1: {
    Compound: {
      cometRewards: "0x1B0e765F6224C21223AeA2af16c1C46E38885a40",
      USDC: {
        "comptrollerV2": "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b",
        "comet": "0xc3d688B66703497DAA19211EEdff47f25384cdc3",
        "configurator": "0x316f9708bB98af7dA9c68C1C3b5e79039cD336E3",
        "bulker": "0xa397a8C2086C554B531c02E29f3291c9704B00c7",
        "fxRoot": "0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2",
        "arbitrumInbox": "0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f",
        "arbitrumL1GatewayRouter": "0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef",
        "CCTPTokenMessenger": "0xbd3fa81b58ba92a82136038b25adec7066af3155",
        "CCTPMessageTransmitter": "0x0a992d191deec32afe36203ad87d7d289a738f81",
        "baseL1CrossDomainMessenger": "0x866E82a600A1414e583f7F13623F1aC5d58b0Afa",
        "baseL1StandardBridge": "0x3154Cf16ccdb4C6d922629664174b904d80F2C35",
        rewardTokens: [addresses[1].tokens.COMP],
      },
      WETH: {
        "comet": "0xA17581A9E3356d9A858b789D68B4d866e593aE94",
        "configurator": "0x316f9708bB98af7dA9c68C1C3b5e79039cD336E3",
        "bulker": "0xa397a8C2086C554B531c02E29f3291c9704B00c7",
        rewardTokens: [addresses[1].tokens.COMP],
      }
    },
  },
  // op
  10: {
    Compound: {
    },
  },
  // xdai
  100: {
    Compound: {
    },
  },
  137: {
    Compound: {
      USDCe: {
        "comet": "0xF25212E676D1F7F89Cd72fFEe66158f541246445",
        "configurator": "0x83E0F742cAcBE66349E3701B171eE2487a26e738",
        "rewards": "0x45939657d1CA34A8FA39A924B71D28Fe8431e581",
        "bridgeReceiver": "0x18281dfC4d00905DA1aaA6731414EABa843c468A",
        "fxChild": "0x8397259c983751DAf40400790063935a11afa28a",
        "bulker": "0x59e242D352ae13166B4987aE5c990C232f7f7CD6"
      }
    },
  },
  // base
  8453: {
    Compound: {
      cometRewards: "0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1",
      USDC: {
        "comet": "0xb125E6687d4313864e53df431d5425969c15Eb2F",
        "configurator": "0x45939657d1CA34A8FA39A924B71D28Fe8431e581",
        "bridgeReceiver": "0x18281dfC4d00905DA1aaA6731414EABa843c468A",
        "l2CrossDomainMessenger": "0x4200000000000000000000000000000000000007",
        "l2StandardBridge": "0x4200000000000000000000000000000000000010",
        "bulker": "0x78D0677032A35c63D142a48A2037048871212a8C",
        rewardTokens: [addresses[8453].tokens.COMP],
      },
      USDbC: {
        "comet": "0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf",
        "configurator": "0x45939657d1CA34A8FA39A924B71D28Fe8431e581",
        "bridgeReceiver": "0x18281dfC4d00905DA1aaA6731414EABa843c468A",
        "l2CrossDomainMessenger": "0x4200000000000000000000000000000000000007",
        "l2StandardBridge": "0x4200000000000000000000000000000000000010",
        "bulker": "0x78D0677032A35c63D142a48A2037048871212a8C",
        rewardTokens: [addresses[8453].tokens.COMP],
      },
      WETH: {
        "comet": "0x46e6b214b524310239732D51387075E0e70970bf",
        "configurator": "0x45939657d1CA34A8FA39A924B71D28Fe8431e581",
        "bridgeReceiver": "0x18281dfC4d00905DA1aaA6731414EABa843c468A",
        "l2CrossDomainMessenger": "0x4200000000000000000000000000000000000007",
        "l2StandardBridge": "0x4200000000000000000000000000000000000010",
        "bulker": "0x78D0677032A35c63D142a48A2037048871212a8C",
        rewardTokens: [addresses[8453].tokens.COMP],
      }
    },
  },
  // arbitrum
  42161: {
    Compound: {
      cometRewards: "0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae",
      USDCe: {
        "comet": "0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA",
        "configurator": "0xb21b06D71c75973babdE35b49fFDAc3F82Ad3775",
        "bridgeReceiver": "0x42480C37B249e33aABaf4c22B20235656bd38068",
        "bulker": "0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d",
        rewardTokens: [addresses[42161].tokens.COMP],
      },
      USDC: {
        "comet": "0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf",
        "configurator": "0xb21b06D71c75973babdE35b49fFDAc3F82Ad3775",
        "bridgeReceiver": "0x42480C37B249e33aABaf4c22B20235656bd38068",
        "bulker": "0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d",
        "CCTPMessageTransmitter": "0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca",
        rewardTokens: [addresses[42161].tokens.COMP],
      }
    },
  },
  43114: {
    Compound: {
    },
  },
} as { [chainId: number]: { [id: string]: any } });
