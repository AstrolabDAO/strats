import { deployAll, getRegistryLatest, getSalts } from "@astrolabs/hardhat";

const [protocolAddr, salts] = [getRegistryLatest(), getSalts()];
const baseFeeds = ["ETH", "BTC", "USDC", "USDT", "FDUSD", "TUSD", "FRAX", "DAI", "USDD", "MIM", "MAI", "LUSD", "PYUSD", "USDP", "USDY", "SUSD", "GHO", "USDB"];

async function main() {
  await deployAll({
    name: "ChainlinkProvider",
    contract: "ChainlinkProvider",
    verify: true,
    useCreate3: true,
    create3Salt: salts.ChainlinkProvider, // used only if not already deployed
    args: [protocolAddr.DAOCouncil],
    overrides: { gasLimit: 1_200_000 }, // required for gnosis-chain (wrong rpc estimate)
    address: protocolAddr.ChainlinkProvider, // use if already deployed (eg. to verify)
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
