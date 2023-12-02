import addresses from "../../addresses";
import merge from "lodash/merge";

// cf. https://github.com/hop-protocol/hop/blob/develop/packages/core/src/addresses/mainnet.ts
export default merge(addresses, {
  // op
  10: {
    "Hop.WETH": {
      lp: '0x5C2048094bAaDe483D0b1DA85c3Da6200A88a849', // l2SaddleLpToken
      swap: '0xaa30D6bba6285d0585722e2440Ff89E23EF68864', // l2SaddleSwap
      rewardPools: ['0x95d6A95BECfd98a7032Ed0c7d950ff6e0Fa8d697'], // rewardsContracts
      rewardTokens: [addresses[10].tokens.HOP],
    },
    "Hop.USDC": {
      lp: '0x2e17b8193566345a2Dd467183526dEdc42d2d5A8', // l2SaddleLpToken
      swap: '0x3c0FFAca566fCcfD9Cc95139FEF6CBA143795963', // l2SaddleSwap
      rewardPools: ['0xf587B9309c603feEdf0445aF4D3B21300989e93a'], // rewardsContracts
      rewardTokens: [addresses[10].tokens.HOP],
    },
    "Hop.USDT": {
      lp: '0xF753A50fc755c6622BBCAa0f59F0522f264F006e', // l2SaddleLpToken
      swap: '0xeC4B41Af04cF917b54AEb6Df58c0f8D78895b5Ef', // l2SaddleSwap
      rewardPools: ['0xAeB1b49921E0D2D96FcDBe0D486190B2907B3e0B'], // rewardsContracts
      rewardTokens: [addresses[10].tokens.HOP],
    },
    "Hop.DAI": {
      lp: '0x22D63A26c730d49e5Eab461E4f5De1D8BdF89C92', // l2SaddleLpToken
      swap: '0xF181eD90D6CfaC84B8073FdEA6D34Aa744B41810', // l2SaddleSwap
      rewardPools: ['0x392B9780cFD362bD6951edFA9eBc31e68748b190'], // rewardsContracts
      rewardTokens: [addresses[10].tokens.HOP],
    }
  },
  // xdai
  100: {
    "Hop.WETH": {
      lp: '0xb9cca4Ed3f082a459c0851058D9FBA0B78dD6C7d', // l2SaddleLpToken
      swap: '0x4014DC015641c08788F15bD6eB20dA4c47D936d8', // l2SaddleSwap
      rewardPools: [
        '0xC61bA16e864eFbd06a9fe30Aab39D18B8F63710a', // GNO
        '0x712F0cf37Bdb8299D0666727F73a5cAbA7c1c24c' // HOP
      ],
      rewardTokens: [addresses[100].tokens.HOP],
    },
    "Hop.USDC": {
      lp: '0x9D373d22FD091d7f9A6649EB067557cc12Fb1A0A', // l2SaddleLpToken
      swap: '0x5C32143C8B198F392d01f8446b754c181224ac26', // l2SaddleSwap
      rewardPools: ['0x5D13179c5fa40b87D53Ff67ca26245D3D5B2F872', '0x636A7ee78faCd079DaBC8f81EDA1D09AA9D440A7'], // rewardsContracts
      rewardTokens: [addresses[100].tokens.HOP],
    },
    "Hop.USDT": {
      lp: '0x5b10222f2Ada260AAf6C6fC274bd5810AF9d33c0', // l2SaddleLpToken
      swap: '0x3Aa637D6853f1d9A9354FE4301Ab852A88b237e7', // l2SaddleSwap
      rewardPools: ['0x2C2Ab81Cf235e86374468b387e241DF22459A265', '0x3d4Cc8A61c7528Fd86C55cfe061a78dCBA48EDd1'], // rewardsContracts
      rewardTokens: [addresses[100].tokens.HOP],
    },
    "Hop.DAI": {
      lp: '0x5300648b1cFaa951bbC1d56a4457083D92CFa33F', // l2SaddleLpToken
      swap: '0x24afDcA4653042C6D08fb1A754b2535dAcF6Eb24', // l2SaddleSwap
      rewardPools: ['0x12a3a66720dD925fa93f7C895bC20Ca9560AdFe7', '0xBF7a02d963b23D84313F07a04ad663409CEE5A92'], // rewardsContracts
      rewardTokens: [addresses[100].tokens.HOP],
    }
  },
  // matic
  137: {
    "Hop.WETH": {
      lp: '0x971039bF0A49c8d8A675f839739eE7a42511eC91', // l2SaddleLpToken
      swap: '0x266e2dc3C4c59E42AA07afeE5B09E964cFFe6778', // l2SaddleSwap
      rewardPools: ['0x7bCeDA1Db99D64F25eFA279BB11CE48E15Fda427', '0xAA7b3a4A084e6461D486E53a03CF45004F0963b7'], // rewardsContracts
      rewardTokens: [addresses[137].tokens.HOP],
    },
    "Hop.USDC": {
      lp: '0x9D373d22FD091d7f9A6649EB067557cc12Fb1A0A', // l2SaddleLpToken
      swap: '0x5C32143C8B198F392d01f8446b754c181224ac26', // l2SaddleSwap
      rewardPools: ['0x2C2Ab81Cf235e86374468b387e241DF22459A265', '0x7811737716942967Ae6567B26a5051cC72af550E'], // rewardsContracts
      rewardTokens: [addresses[137].tokens.HOP],
    },
    "Hop.USDT": {
      lp: '0x3cA3218D6c52B640B0857cc19b69Aa9427BC842C', // l2SaddleLpToken
      swap: '0xB2f7d27B21a69a033f85C42d5EB079043BAadC81', // l2SaddleSwap
      rewardPools: ['0x07932e9A5AB8800922B2688FB1FA0DAAd8341772', '0x297E5079DF8173Ae1696899d3eACD708f0aF82Ce'], // rewardsContracts
      rewardTokens: [addresses[137].tokens.HOP],
    },
    "Hop.DAI": {
      lp: '0x8b7aA8f5cc9996216A88D900df8B8a0a3905939A', // l2SaddleLpToken
      swap: '0x25FB92E505F752F730cAD0Bd4fa17ecE4A384266', // l2SaddleSwap
      rewardPools: ['0x4Aeb0B5B1F3e74314A7Fa934dB090af603E8289b', '0xd6dC6F69f81537Fe9DEcc18152b7005B45Dc2eE7'], // rewardsContracts
      rewardTokens: [addresses[137].tokens.HOP],
    }
  },
  // base
  8453: {
    "Hop.WETH": {
      lp: '0xe9605BEc1c5C3E81F974F80b8dA9fBEFF4845d4D', // l2SaddleLpToken
      swap: '0x0ce6c85cF43553DE10FC56cecA0aef6Ff0DD444d', // l2SaddleSwap
      rewardPools: ['0x12e59C59D282D2C00f3166915BED6DC2F5e2B5C7'], // rewardsContracts
      rewardTokens: [addresses[8453].tokens.HOP],
    },
    "Hop.USDC": {
      lp: '0x3b507422EBe64440f03BCbE5EEe4bdF76517f320', // l2SaddleLpToken
      swap: '0x022C5cE6F1Add7423268D41e08Df521D5527C2A0', // l2SaddleSwap
      rewardPools: ['0x7aC115536FE3A185100B2c4DE4cb328bf3A58Ba6'], // rewardsContracts
      rewardTokens: [addresses[8453].tokens.HOP],
    }
  },
  // arbitrum
  42161: {
    "Hop.WETH": {
      lp: '0x59745774Ed5EfF903e615F5A2282Cae03484985a', // l2SaddleLpToken
      swap: '0x652d27c0F72771Ce5C76fd400edD61B406Ac6D97', // l2SaddleSwap
      rewardPools: ['0x755569159598f3702bdD7DFF6233A317C156d3Dd'], // rewardsContracts
      rewardTokens: [addresses[42161].tokens.HOP],
    },
    "Hop.USDCe": {
      lp: '0xB67c014FA700E69681a673876eb8BAFAA36BFf71', // l2SaddleLpToken
      swap: '0x10541b07d8Ad2647Dc6cD67abd4c03575dade261', // l2SaddleSwap
      rewardPools: ['0xb0CabFE930642AD3E7DECdc741884d8C3F7EbC70'], // rewardsContracts
      rewardTokens: [addresses[42161].tokens.HOP],
    },
    "Hop.USDT": {
      lp: '0xCe3B19D820CB8B9ae370E423B0a329c4314335fE', // l2SaddleLpToken
      swap: '0x18f7402B673Ba6Fb5EA4B95768aABb8aaD7ef18a', // l2SaddleSwap
      rewardPools: ['0x9Dd8685463285aD5a94D2c128bda3c5e8a6173c8'], // rewardsContracts
      rewardTokens: [addresses[42161].tokens.HOP],
    },
    "Hop.DAI": {
      lp: '0x68f5d998F00bB2460511021741D098c05721d8fF', // l2SaddleLpToken
      swap: '0xa5A33aB9063395A90CCbEa2D86a62EcCf27B5742', // l2SaddleSwap
      rewardPools: ['0xd4D28588ac1D9EF272aa29d4424e3E2A03789D1E'], // rewardsContracts
      rewardTokens: [addresses[42161].tokens.HOP],
    }
  },
  // linea
  59144: {
    "Hop.WETH": {
      lp: '0x7689674c3EcEC55086b08A3cEA785de2848d8C87', // l2SaddleLpToken
      swap: '0x2935173357c010F8B56c8719a44f9FbdDa90f67c', // l2SaddleSwap
      rewardPools: ['0xa50395bdEaca7062255109fedE012eFE63d6D402'], // rewardsContracts
      rewardTokens: [addresses[59144].tokens.HOP],
    },
  }
} as { [chainId: number]: { [id: string]: any } });
