import { getRegistryLatest, getDeploymentInfo, getVerificationInfo } from "@astrolabs/hardhat";

const addr = getRegistryLatest();
const contracts = [
  "DAOCouncil",
  "DAOTreasury",
  "AccessController",
  "ChainlinkProvider",
  // "PythProvider",
  // "API3Provider",
  // "RedstoneProvider",
  "AsAccounting",
  "StrategyV5Agent"
];

async function main() {

  let [depInfo, verifInfo] = [[], []] as [any[], any[]];

  for (const c of contracts) {
    depInfo.push(getDeploymentInfo(addr[c]));
    verifInfo.push(getVerificationInfo(addr[c]));
  }

  depInfo = await Promise.all(depInfo);
  verifInfo = await Promise.all(verifInfo);

  console.log(contracts.map((c, i) =>
    `${c.padEnd(20, ".")} ${depInfo[i].isDeployed ? '📦 Deployed (' + depInfo[i].byteSize.toString().padStart(7, ".") + ' bytes)' : '❌ not deployed'
    } - ${verifInfo[i].isVerified ? '✅ verified (' +
      verifInfo[i].events + ' events, ' +
      verifInfo[i].viewFunctions + ' view, ' +
      verifInfo[i].mutableFunctions + ' mutable functions)' : '❌ not verified'}`));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
