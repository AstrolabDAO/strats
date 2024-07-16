import { deployAll, getRegistryLatest, getSalts } from "@astrolabs/hardhat";
import { ensureDeployer } from "../test/utils";

const [addr, salts] = [getRegistryLatest(), getSalts()];

async function main() {
  await ensureDeployer(addr.Deployer);
  await deployAll({
    name: "StrategyV5Agent",
    contract: "StrategyV5Agent",
    verify: true,
    useCreate3: true,
    create3Salt: salts.StrategyV5Agent, // used only if not already deployed
    args: [addr.AccessController],
    libraries: { AsAccounting: addr.AsAccounting },
    // overrides: { gasLimit: 5_800_000 }, // required for gnosis-chain (wrong rpc estimate)
    // address: addr.StrategyV5Agent, // use if already deployed (eg. to verify)
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
