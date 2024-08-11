import { addresses } from "@astrolabs/hardhat";
import merge from "lodash/merge";

// cf. https://agavedev.notion.site/Deployed-Contracts-d6ec9d23c8d341ba9fa7c1fd7fd4535e
export default merge(addresses, {
  // xdai
  100: {
    Agave: {
        LendingPoolAddressesProvider: "0x3673C22153E363B1da69732c4E0aA71872Bbb87F",
        LendingPoolAddressesProviderRegistry: "0x4BaacD04B13523D5e81f398510238E7444E11744",
        LendingPool: "0x5E15d5E33d318dCEd84Bfe3F4EACe07909bE6d9c",
        LendingPoolCollateralManager: "0xD7E6500dFB81A5B2553b7604cB55305aA7db949f",
        LendingPoolConfigurator: "0x4a1ac23dC8df045524cf8b59B25D1ccAe2eA62F5",
        LendingRateOracle: "0xc7313D0a5BF166c984B3e818B59432513D2D4938",
        AgaveOracle: "0x062B9D1D3F5357Ef399948067E93B81F4B85db7a",
        ProtocolDataProvider: "0xe6729389dea76d47b5bcb0ba5c080821c3b51329",
        WETHGateway: "0x36A644cC38Ae257136EEca5919800f364d73FeFC",
        PoolAdmin: "0xb4c575308221CAA398e0DD2cDEB6B2f10d7b000A",
        EmergencyAdmin: "0x70225281599Ba586039E7BD52736681DFf6c2Fc4",
        IncentivesController: "0xfa255f5104f129B78f477e9a6D050a02f31A5D86",
        BulkClaimer: "0xABb5c11A26081d1f285454190f28FdABb1C2E0F9",
        BaseIncentivesImplementation: "0x501e282847e87245e3d7a25515c69b7ae8b4031a",
        ReserveLogic: "0xE4229B4ffa50Ee58fAd85b26f92918631f3344ca",
        GenericLogic: "0xEDfd8c6d5DDBe96dBD2507aA9E415787E84EB774",
        ValidationLogic: "0x383aC6bCd11ef56A12E45Bd24AB1fe3fa9f56E31",
        StableAndVariableTokensHelper: "0x279b2f090c16E0c34a2E61e153bA5B7EB8d31Cc0",
        ATokensAndRatesHelper: "0x87CCbfB35bA8dBF25445a2Fb6D4B69DD3743e2Ab",
        WalletBalanceProvider: "0xc83259C1A02d7105A400706c3e1aDc054C5A1B87",
        AToken: "0x107302c78c9e7d5EB8e1Ec2Ed130D5344Ac52F40",
        StableDebtToken: "0x630de666651FBAfeBe3f0e3a552635b915519639",
        VariableDebtToken: "0x119ae25CA062c75f358267e657f512EfEC488de3",
        DefaultReserveInterestRateStrategy: "0x8a1606fbF2B809104b85F79730e0724D45b211a4",
        agGNO: "0xa26783ead6c1f4744685c14079950622674ae8a8",
        agWETH: "0x44932e3b1e662adde2f7bac6d5081c5adab908c6",
        agWXDAI: "0xd4e420bbf00b0f409188b338c5d87df761d6c894",
        agUSDC: "0x291b5957c9cbe9ca6f0b98281594b4eb495f4ec1",
        agUSDT: "0x5b4ef67c63d091083ec4d30cfc4ac685ef051046",
        agWBTC: "0x4863cfaf3392f20531aa72ce19e5783f489817d6",
        EURAe: "0xeb20b07a9abe765252e6b45e8292b12cb553cca6",
        agsDAI: "0xe1cf0d5a56c993c3c2a0442dd645386aeff1fc9a",
        // AGVEGNO_LP: "0xba12222222228d8ba445958a75a0704d566bf2c8",
        // AGVEsDAI_LP: "0x4b1a99467a284cc690e3237bc69105956816f762",
        BalancerVault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        RewardPoolId: "0x388cae2f7d3704c937313d990298ba67d70a3709000200000000000000000026", // GNO/AGVE
        rewardTokens: [addresses[100].tokens.GNO, addresses[100].tokens.AGVE],
    }
  },
} as { [chainId: number]: { [id: string]: any } });
