import { SafeContract, ethers, loadAbi } from "@astrolabs/hardhat";

async function main() {

  const abi = await loadAbi("StrategyV5");
  const strat = await SafeContract.build(
    "0x8791853a828302cb71a6585e401d3c63754cc1f8", // getRegistryLatest()["apUSD-XVS-A"],
    <[]>abi,
    (await ethers.getSigners())[0]
  );
  const result = await strat.previewSwapAddons(
    [BigInt(1046377194719589747920), 0, 0, 0, 0, 0, 0, 0], false).then(tx => tx.wait());
  console.log(result);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
