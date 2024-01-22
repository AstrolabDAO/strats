import { TransactionResponse } from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IStrategyDeploymentEnv, MaybeAwaitable } from "../../src/types";
import { getOverrides, resolveMaybe } from "../utils";

export async function grantRoles(
  env: Partial<IStrategyDeploymentEnv>,
  roles: string[],
  grantee: MaybeAwaitable<string> = env.deployer!.address,
  signer: MaybeAwaitable<SignerWithAddress> = env.deployer!,
): Promise<boolean> {
  [signer, grantee] = await Promise.all([
    resolveMaybe(signer),
    resolveMaybe(grantee),
  ]);
  const strat = await env.deployment!.strat.copy(signer);
  const rolesSignatureCalls = roles.map(
    (role) => strat.multi[`${role}_ROLE`]?.(),
  );

  for (const i in rolesSignatureCalls)
    if (!rolesSignatureCalls[i])
      throw new Error(
        `Function ${roles[i]}_ROLE does not exist on strat.multi`,
      );
  const roleSignatures = await env.multicallProvider!.all(rolesSignatureCalls);

  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) => strat.multi.hasRole(role, grantee)),
    );
  const hasBefore = await hasRoles();
  console.log(`${signer.address} roles (before acceptRoles): ${hasBefore}`);

  for (const i in roleSignatures)
    if (!hasBefore[i])
      await strat
        .grantRole(roleSignatures[i], grantee, getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());

  console.log(
    `${signer.address} roles (after acceptRoles): ${await hasRoles()}`,
  );
  return true;
}

export async function acceptRoles(
  env: Partial<IStrategyDeploymentEnv>,
  roles: string[],
  signer: MaybeAwaitable<SignerWithAddress> = env.deployer!, // == grantee
): Promise<boolean> {
  signer = await resolveMaybe(signer);
  const strat = await env.deployment!.strat.copy(signer);
  // const roleSignatures = roles.map((role) => ethers.utils.id(role));
  const roleSignatures = await env.multicallProvider!.all(
    roles.map((role) => strat.multi[`${role}_ROLE`]()),
  );

  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) =>
        strat.multi.hasRole(role, (signer as SignerWithAddress).address),
      ),
    );
  const has = await hasRoles();
  console.log(`${signer.address} roles (before acceptRoles): ${has}`);
  for (const i in roleSignatures)
    if (!has[i])
      await strat
        .acceptRole(roleSignatures[i], getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());
  console.log(
    `${signer.address} roles (after acceptRoles): ${await hasRoles()}`,
  );
  return true;
}

export async function revokeRoles(
  env: Partial<IStrategyDeploymentEnv>,
  roles: string[],
  deprived: MaybeAwaitable<string>, // == ex-grantee
  signer: MaybeAwaitable<SignerWithAddress> = env.deployer!,
): Promise<boolean> {
  [signer, deprived] = await Promise.all([
    resolveMaybe(signer),
    resolveMaybe(deprived),
  ]);
  const strat = await env.deployment!.strat.copy(signer);
  // const roleSignatures = roles.map((role) => ethers.utils.id(role));
  const roleSignatures = await env.multicallProvider!.all(
    roles.map((role) => strat.multi[`${role}_ROLE`]()),
  );
  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) => strat.multi.hasRole(role, deprived)),
    );
  const has = await hasRoles();
  console.log(`${signer.address} roles (before revokeRoles): ${has}`);
  for (const i in roleSignatures)
    if (has[i])
      await strat
        .revokeRole(roleSignatures[i], deprived, getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());
  console.log(
    `${signer.address} roles (after revokeRoles): ${await hasRoles()}`,
  );
  return true;
}
