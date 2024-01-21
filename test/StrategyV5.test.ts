import { network } from "hardhat";
import { BigNumber } from "ethers";
import addresses from "src/addresses";
import { IFlow, acceptRoles, compound, deposit, grantRoles, harvest, invest, liquidate, requestRescue, requestWithdraw, rescue, revokeRoles, seedLiquidity, withdraw } from "./flows";
import { signerAddressGetter, signerGetter } from "./utils";

const testFlows: Partial<IFlow>[] = [
    // ERC4626 test
    { fn: seedLiquidity, params: [10], assert: (n: BigNumber) => n.gt(0) },
    { fn: deposit, params: [10000], assert: (n: BigNumber) => n.gt(0) },
    { fn: invest, params: [], assert: (n: BigNumber) => n.gt(0) },
    { fn: liquidate, params: [10], assert: (n: BigNumber) => n.gt(0) },
    { fn: withdraw, params: [9], assert: (n: BigNumber) => n.gt(0) },

    // ERC7540 tests
    { fn: requestWithdraw, params: [18], assert: (n: BigNumber) => n.gt(0) },
    { fn: liquidate, params: [1], assert: (n: BigNumber) => n.gt(0) },
    { fn: withdraw, params: [17], assert: (n: BigNumber) => n.gt(0) },

    // Manageable tests
    { fn: grantRoles, params: [["MANAGER", "KEEPER"], signerAddressGetter(1)] },
    { elapsedSec: 60*60*24*3, fn: acceptRoles, params: [["MANAGER"], signerGetter(1)] },
    { fn: revokeRoles, params: [["KEEPER"], signerAddressGetter(1)] },

    // Rescuable tests
    { fn: requestRescue, params: [addresses[network.config.chainId!].tokens.WELL] },
    { elapsedSec: 60*60*24*3, revertState: true, fn: rescue, params: [addresses[network.config.chainId!].tokens.WELL], assert: (n: BigNumber) => n.gt(0) },

    { fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) },
    { elapsedSec: 30, revertState: true, fn: withdraw, params: [10], assert: (n: BigNumber) => n.gt(0) },
    { elapsedSec: 60*60*24*14, revertState: true, fn: harvest, params: [], assert: (n: BigNumber) => n.gt(0) },
    { elapsedSec: 60*60*24*7, revertState: true, fn: compound, params: [], assert: (n: BigNumber) => n.gt(0) },
];
