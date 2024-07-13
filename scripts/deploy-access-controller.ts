import { deployAll, getRegistryLatest, getSalts } from "@astrolabs/hardhat";

const [protocolAddr, salts] = [getRegistryLatest(), getSalts()];

async function main() {
  await deployAll({
    name: "AccessController",
    contract: "AccessController",
    verify: true,
    useCreate3: true,
    create3Salt: salts.AccessController, // used only if not already deployed
    args: [protocolAddr.DAOCouncil],
    overrides: { gasLimit: 1_200_000 }, // required for gnosis-chain (wrong rpc estimate)
    address: protocolAddr.AccessController, // use if already deployed (eg. to verify)
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
