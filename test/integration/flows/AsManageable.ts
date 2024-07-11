import { TransactionResponse } from "@astrolabs/hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IStrategyDeploymentEnv, MaybeAwaitable } from "../../../src/types";
import { getOverrides, keccak256, resolveMaybe } from "../../utils";

/**
 * Grants roles to a grantee using the provided environment and signer
 * @param env Strategy deployment environment
 * @param roles An array of roles to be granted
 * @param grantee Grantee's address. Defaults to the deployer's address from the environment
 * @param signer Signer. Defaults to the deployer from the environment
 * @returns Boolean indicating whether the roles were successfully granted
 */
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
  const [strat, accessController] = await Promise.all([
    env.deployment!.strat.copy(signer),
    env.deployment!.AccessController.copy(signer)
  ]);

  const roleSignatures = roles.map((role) => keccak256(role));

  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) => accessController.multi.hasRole(role, grantee)),
    );
  const hasBefore = await hasRoles();
  console.log(`${signer.address} roles (before acceptRoles): ${hasBefore}`);

  for (const i in roleSignatures)
    if (!hasBefore[i])
      await accessController
        .grantRole(roleSignatures[i], grantee, getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());

  console.log(
    `${signer.address} roles (after acceptRoles): ${await hasRoles()}`,
  );
  return true;
}

/**
 * Accepts the specified roles for a given environment and signer
 * @param env Strategy deployment environment
 * @param roles Array of roles to accept
 * @param signer Signer with address. Defaults to the deployer/grantee
 * @returns Boolean indicating whether the roles were accepted successfully
 */
export async function acceptRoles(
  env: Partial<IStrategyDeploymentEnv>,
  roles: string[],
  signer: MaybeAwaitable<SignerWithAddress> = env.deployer!, // == grantee
): Promise<boolean> {
  signer = await resolveMaybe(signer);
  const [strat, accessController] = await Promise.all([
    env.deployment!.strat.copy(signer),
    env.deployment!.AccessController.copy(signer)
  ]);
  const roleSignatures = roles.map((role) => keccak256(role));

  // const roleSignatures = await env.multicallProvider!.all(
  //   roles.map((role) => accessController.multi[`${role}_ROLE`]()),
  // );

  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) =>
        accessController.multi.hasRole(role, (signer as SignerWithAddress).address),
      ),
    );
  const has = await hasRoles();
  console.log(`${signer.address} roles (before acceptRoles): ${has}`);
  for (const i in roleSignatures)
    if (!has[i])
      await accessController
        .acceptRole(roleSignatures[i], getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());
  console.log(
    `${signer.address} roles (after acceptRoles): ${await hasRoles()}`,
  );
  return true;
}

/**
 * Revokes the specified roles from a given user
 * @param env Strategy deployment environment
 * @param roles Array of roles to revoke
 * @param deprived Ex-grantee (user) from whom the roles will be revoked
 * @param signer Signer with address. Defaults to the deployer from the environment
 * @returns Boolean indicating whether the roles were successfully revoked
 */
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

  const [strat, accessController] = await Promise.all([
    env.deployment!.strat.copy(signer),
    env.deployment!.AccessController.copy(signer)
  ]);

  const roleSignatures = roles.map((role) => keccak256(role));
  // const roleSignatures = await env.multicallProvider!.all(
  //   roles.map((role) => strat.multi[`${role}_ROLE`]()),
  // );
  const hasRoles = async () =>
    env.multicallProvider!.all(
      roleSignatures.map((role) => accessController.multi.hasRole(role, deprived)),
    );
  const has = await hasRoles();
  console.log(`${signer.address} roles (before revokeRoles): ${has}`);
  for (const i in roleSignatures)
    if (has[i])
      await accessController
        .revokeRole(roleSignatures[i], deprived, getOverrides(env))
        .then((tx: TransactionResponse) => tx.wait());
  console.log(
    `${signer.address} roles (after revokeRoles): ${await hasRoles()}`,
  );
  return true;
}
