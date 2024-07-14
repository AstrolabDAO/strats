import { deployAll, getDeployer, getRegistryLatest, getSalts } from "@astrolabs/hardhat";

const [protocolAddr, salts] = [getRegistryLatest(), getSalts()];

async function main() {
  const deployer = await getDeployer();
  if (protocolAddr.Deployer != await deployer.getAddress()) {
    throw new Error("Deployer address is not the same as the one in the registry.");
  }
  await deployAll({
    name: "AccessController",
    contract: "AccessController",
    verify: true,
    useCreate3: true,
    create3Salt: salts.AccessController, // used only if not already deployed
    args: [protocolAddr.Deployer],
    // overrides: { gasLimit: 1_200_000 }, // required for gnosis-chain (wrong rpc estimate)
    // address: protocolAddr.AccessController, // use if already deployed (eg. to verify)
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
