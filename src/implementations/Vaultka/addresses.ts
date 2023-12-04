import addresses from "../../addresses";
import merge from "lodash/merge";

// cf. https://www.vaultka.com/app/vaults
export default merge(addresses, {
  // arbitrum
  42161: {
    "Vaultka.GM-Leverage": {
      lp: "0x59745774Ed5EfF903e615F5A2282Cae03484985a", // Vodkav1
      rewardTokens: [addresses[42161].tokens.ARB],
    },
    "Vaultka.HLP-Leverage": {
      lp: "0x739fe1BE8CbBeaeA96fEA55c4052Cd87796c0a89", // Rum
    },
    "Vaultka.VLP-Leverage": {
      lp: "0xc53A53552191BeE184557A15f114a87a757e5b6F", // Sake
    },
  },
} as { [chainId: number]: { [id: string]: any } });
