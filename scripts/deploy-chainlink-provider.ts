import { abiEncode, addresses, addressToBytes32, deployAll, ethers, getChainlinkFeedsByChainId, getDeployer, getSalts, NetworkAddresses, provider } from "@astrolabs/hardhat";
import { ensureDeployer } from "../test/utils";

const salts = getSalts();
const baseSymbols = [
  // flagships
  "WETH", "BETH", "WBTC", "BTCB", "BTCb",
  // stables
  "WXDAI", "WBNB", "WFTM", "WAVAX", "WMATIC", "WCELO", "WKAVA", "WMNT",
  "USDC", "USDCe", "USDT", "FDUSD", "TUSD", "FRAX", "DAI", "USDD", "XDAI",
  "MIM", "MAI", "LUSD", "PYUSD", "USDP", "USDY", "SUSD", "crvUSD", "GHO", "USDB",
  "USDCe", "USDTe", "DAIe", "FDUSDe", "TUSDe", "FRAXe",
  "USDCb", "USDTb", "DAIb", "FDUSDb", "TUSDb", "FRAXb",
  "fUSDC", "fUSDT", "fDAI", "fFDUSD", "fTUSD", "fFRAX",
  "axlUSDC", "lzUSDC", "whUSDC", "axlUSDT", "lzUSDT", "whUSDT", "axlDAI", "lzDAI", "whDAI",	"axlFRAX", "lzFRAX", "whFRAX",
  "axlETH", "lzETH", "whETH", "axlBTC", "lzBTC", "whBTC",
  "xcUSDC", "xcUSDT", "xcDAI", "xcFRAX", "xcETH", "xcBTC",
  "USDbC", "DOLA",
  // lst+lrt
  "stETH", "wstETH", "rETH", "mETH", "cbETH", "BETH", "WBETH", "weETH", "frxETH", "sfrxETH", "ETHx", "ankrETH",
  "xBNB", "ankrBNB", "sAVAX",
  // alts
  "ARB", "OP", "BLAST", "ETH", "MNT", "ZK", "MATIC", "POLY", "CELO", "KAVA", "AVAX", "BNB", "FTM", "GNO",
  "HOP", "STG", "XVS", "AAVE", "COMP", "CAKE", "CRV", "UNI", "LINK",
];

async function main() {
  const chainId = await provider.getNetwork().then((n) => n.chainId);
  const addr = addresses[chainId] as NetworkAddresses;
  await ensureDeployer(addr.astrolab.Deployer);
  const oracles = getChainlinkFeedsByChainId()[chainId];

  const knownSymbols = baseSymbols.filter((sym) =>
    !!addr.tokens[sym] && !!oracles[`Crypto.${sym}/USD`]); // filter out unknown addresses/feeds

  const knownAddresses = knownSymbols.map((sym) => addr.tokens[sym]);
  const knownFeeds = knownSymbols.map((sym) => addressToBytes32(oracles[`Crypto.${sym}/USD`]));

  console.log(`Removed ${baseSymbols.length - knownSymbols.length} unknown feeds`);
  console.log(`Deploying ChainlinkProvider with ${knownSymbols.length} known feeds:\n${knownSymbols.join(", ")}`);

  // deploy + verify ChainlinkProvider (optimized for existing or new deployment)
  // const deployed = await isDeployed({}, addresses.astrolab.ChainlinkProvider);
  const deployment = await deployAll({
    name: "ChainlinkProvider",
    contract: "ChainlinkProvider",
    verify: true,
    useCreate3: true,
    create3Salt: salts.ChainlinkProvider,
    args: [addr.astrolab.AccessController],
    // overrides: { gasLimit: 2_000_000 }, // required for gnosis-chain (wrong rpc estimate)
    // address: addr.astrolab.ChainlinkProvider, // use if already deployed (eg. to verify)
  });

  if (deployment.units.ChainlinkProvider.address!.toLowerCase() !== addr.astrolab.ChainlinkProvider.toLowerCase()) {
    throw new Error("Deployed ChainlinkProvider address is not the registry expected one.");
  }

  const cp = await ethers.getContractAt("ChainlinkProvider", addr.astrolab.ChainlinkProvider);

  console.log("Initializing oracle feeds...");
  await cp.update(
    abiEncode(
      ["(address[],bytes32[],uint256[])"],
      [
        [
          knownAddresses,
          knownFeeds,
          knownAddresses.map((feed) => 3600 * 48), // chainlink default validity (2 days)
        ],
      ],
    ),
  ).then((tx) => tx.wait());
  console.log(`ChainlinkProvider initialized with ${knownSymbols.length} feeds: ${knownSymbols.join(", ")}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
