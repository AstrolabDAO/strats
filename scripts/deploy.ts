import { deployAll } from "@astrolabs/hardhat";

async function main() {
  await deployAll({
    name: "AsAccounting",
    contract: "AsAccounting",
    verify: true,
    address: "0x1761FF905292548fF2254620166eabd988e48718",
    export: false, // do not export abi+deployment json
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
