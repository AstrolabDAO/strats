import { deployAll, getRegistryLatest, getSalts } from "@astrolabs/hardhat";
import { ensureDeployer } from "../test/utils";

const [addr, salts] = [getRegistryLatest(), getSalts()];

async function main() {
  await ensureDeployer(addr.Deployer);
  await deployAll({
    name: "AsAccounting",
    contract: "AsAccounting",
    verify: true,
    useCreate3: true,
    create3Salt: salts.AsAccounting, // used only if not already deployed
    // overrides: { gasLimit: 800_000 }, // required for gnosis-chain (wrong rpc estimate)
    // address: addr.AsAccounting, // use if already deployed (eg. to verify)
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
