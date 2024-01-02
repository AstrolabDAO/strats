import { deployAll } from "@astrolabs/hardhat";

async function main() {
  await deployAll({
    name: "AsMaths",
    contract: "AsMaths",
    verify: true,
    address: "0x503301Eb7cfC64162b5ce95cc67B84Fbf6dF5255",
    export: false, // do not export abi+deployment json
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
