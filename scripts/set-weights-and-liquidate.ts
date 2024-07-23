import { getRuntimeEnv } from "../test/utils";
import { liquidate, setInputWeights } from "../test/integration/flows/StrategyV5";

async function main() {
  const env = await getRuntimeEnv("0xc501D3e5e4f4e1199222A75bb996798bF715Bd7F");
  await setInputWeights(env, [0, 0]);
  await liquidate(env, 0);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
