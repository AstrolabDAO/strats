import { deployAll, getDeployer, getRegistryLatest, getSalts } from "@astrolabs/hardhat";
import { ensureDeployer } from "../test/utils";

const [addr, salts] = [getRegistryLatest(), getSalts()];

async function main() {
  await ensureDeployer(addr.Deployer);
  await deployAll({
    name: "AccessController",
    contract: "AccessController",
    verify: true,
    useCreate3: true,
    create3Salt: salts.AccessController, // used only if not already deployed
    args: [addr.Deployer],
    // overrides: { gasLimit: 1_200_000 }, // required for gnosis-chain (wrong rpc estimate)
    // address: addr.AccessController, // use if already deployed (eg. to verify)
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
