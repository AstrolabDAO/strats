import { getRegistryLatest, verifyContract } from "@astrolabs/hardhat";

async function main() {
  await verifyContract({
    name: "Astrolab Primitive: Venus Arbitrage USD",
    contract: "VenusArbitrage",
    address: getRegistryLatest()["apUSD-XVS-A"], // 0x0000A7E215cDca647946B29554108C2A330FAAA4
    verify: true,
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
