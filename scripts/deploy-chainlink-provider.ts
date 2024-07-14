import { deployAll, ethers, getDeployer, getSalts } from "@astrolabs/hardhat";
import { abiEncode, addressToBytes32 } from "../test/utils";
import oraclesByChainId from "../src/chainlink-oracles.json";
import addressesByChainId from "../src/addresses";

const salts = getSalts();
const baseSymbols = [
  "WETH", "BETH",
  "WBTC", "BTCB",
  "USDC", "USDCe",
  "USDT", "FDUSD",
  "TUSD", "FRAX",
  "DAI", "USDD",
  "MIM", "MAI",
  "LUSD", "PYUSD",
  "USDP", "USDY",
  "SUSD", "GHO",
  "USDB"
];

async function main() {
  const deployer = await getDeployer();
  const chainId = await deployer.getChainId();
  const addresses = addressesByChainId[chainId];
  const oracles = oraclesByChainId[chainId];
  if (addresses.astrolab.Deployer != await deployer.getAddress()) {
    throw new Error("Deployer address is not the same as the one in the registry.");
  }
  const knownAddresses = baseSymbols.map((sym) => addresses.tokens[sym]);
  const knownFeeds = baseSymbols.map((sym) =>
    oracles[`Crypto.${sym}/USD`] ? addressToBytes32(oracles[`Crypto.${sym}/USD`]) : null,
  );

  // keep only the addresses/feeds pairs that are known
  const knwonSymbols = [];
  for (const i in knownAddresses) {
    if (!knownAddresses[i] || !knownFeeds[i]) {
      knownAddresses.splice(Number(i), 1);
      knownFeeds.splice(Number(i), 1);
    } else {
      knwonSymbols.push(baseSymbols[i]);
    }
  }
  console.log(`Removed ${baseSymbols.length - knownAddresses.length} unknown feeds`);
  console.log(`Deploying ChainlinkProvider with ${knownAddresses.length} known feeds:\n${knwonSymbols.join(", ")}`);

  // deploy + verify ChainlinkProvider
  const deployment = await deployAll({
    name: "ChainlinkProvider",
    contract: "ChainlinkProvider",
    verify: true,
    useCreate3: true,
    create3Salt: salts.ChainlinkProvider, // used only if not already deployed
    args: [addresses.astrolab.AccessController],
    // overrides: { gasLimit: 1_200_000 }, // required for gnosis-chain (wrong rpc estimate)
    // address: protocolAddr.ChainlinkProvider, // use if already deployed (eg. to verify)
  });
  if (deployment.units[0].contract !== addresses.astrolab.ChainlinkProvider) {
    throw new Error("Deployed ChainlinkProvider address is not the registry expected one.");
  }
  const cp = await ethers.getContractAt("ChainlinkProvider", addresses.astrolab.ChainlinkProvider);
  await cp.update(
    abiEncode(
      ["(address[],bytes32[],uint256[])"],
      [
        [
          knownAddresses,
          knownFeeds,
          knownAddresses.map((feed) => 3600 * 48), // chainlink default validity (1 day) * 2
        ],
      ],
    ),
  ).then((tx) => tx.wait());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
