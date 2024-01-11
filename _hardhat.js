"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.verifyContract = exports.generateContractName = exports.saveDeploymentUnit = exports.writeLightRegistry = exports.writeRegistry = exports.saveLightDeployment = exports.saveDeployment = exports.getDeployedAddress = exports.getDeployedContract = exports.loadDeploymentUnit = exports.loadAbi = exports.loadDeployment = exports.deploy = exports.exportAbi = exports.getAbiFromArtifacts = exports.getArtifactSource = exports.isContractLocal = exports.getArtifacts = exports.deployAll = exports.resetLocalNetwork = exports.setBalances = exports.revertNetwork = exports.getDeployer = exports.changeNetwork = void 0;
const ethers_1 = require("ethers");
const experimental_1 = require("@ethersproject/experimental");
const hardhat_1 = require("hardhat");
const hardhat_tenderly_1 = require("@tenderly/hardhat-tenderly");
const hardhat_config_1 = require("../hardhat.config");
const networks_1 = require("../networks");
const format_1 = require("./format");
const fs_1 = require("./fs");
const construction_1 = require("hardhat/internal/core/providers/construction");
const ethers_provider_wrapper_1 = require("@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper");
/// Create 3
const { BigNumber } = ethers;
const Create3Deployer = require('@axelar-network/axelar-gmp-sdk-solidity/artifacts/contracts/deploy/Create3Deployer.sol/Create3Deployer.json');
const LodestarMultiStake = require('../../../../../artifacts/src/implementations/Lodestar/LodestarMultiStake.sol/LodestarMultiStake.json');
///
const providers = {};
const getProvider = async (name) => {
    if (!providers[name]) {
        providers[name] = await (0, construction_1.createProvider)(hardhat_config_1.config, name, hardhat_1.artifacts);
    }
    return providers[name];
};
async function changeNetwork(slug, blockNumber) {
    if (slug.includes("local"))
        return await resetLocalNetwork(slug, "hardhat", blockNumber);
    if (!hardhat_config_1.config.networks[slug])
        throw new Error(`changeNetwork: Couldn't find network '${slug}'`);
    if (!providers[hardhat_1.network.name])
        providers[hardhat_1.network.name] = hardhat_1.network.provider;
    hardhat_1.network.name = slug;
    hardhat_1.network.config = hardhat_config_1.config.networks[slug];
    hardhat_1.network.provider = await getProvider(slug);
    hardhat_1.ethers.provider = new ethers_provider_wrapper_1.EthersProviderWrapper(hardhat_1.network.provider);
    if (slug.includes("tenderly"))
        (0, hardhat_tenderly_1.setup)();
}
exports.changeNetwork = changeNetwork;
const getDeployer = async () => (await hardhat_1.ethers.getSigners())[0];
exports.getDeployer = getDeployer;
const revertNetwork = async (snapshotId) => await hardhat_1.network.provider.send("evm_revert", [snapshotId]);
exports.revertNetwork = revertNetwork;
const setBalances = async (amount, ...addresses) => {
    const hexAmount = hardhat_1.ethers.utils.hexValue(ethers_1.BigNumber.from(amount));
    hardhat_1.network.name.includes("tenderly")
        ? await hardhat_1.ethers.provider.send("tenderly_setBalance", [addresses, hexAmount])
        : await Promise.all(addresses.map((a) => hardhat_1.ethers.provider.send("hardhat_setBalance", [a, hexAmount])));
};
exports.setBalances = setBalances;
async function resetLocalNetwork(slug, name = "hardhat", blockNumber) {
    const target = hardhat_config_1.config.networks[slug];
    if (!target)
        throw new Error(`resetLocalNetwork: Couldn't find network '${slug}'`);
    await hardhat_1.network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                network: name,
                url: target.url,
                port: process.env.HARDHAT_PORT ?? 8545,
                chainId: Number(hardhat_1.network.config.chainId),
                // accounts,
                forking: {
                    jsonRpcUrl: target.url,
                    networkId: target.chainId,
                    ...(blockNumber && { blockNumber }), // <-- latest by default
                },
            },
        ],
    });
}
exports.resetLocalNetwork = resetLocalNetwork;
async function deployAll(d, update = false) {
    if (!d.name)
        throw new Error(`Missing name for deployment`);
    if (!d.units || !Object.values(d.units).length) {
        return await deployAll({
            name: `${d.name}-standalone`,
            contract: d.contract,
            units: { [d.name]: d },
        }, update);
    }
    // only export if any unit is missing an address >> actual deployment
    d.export ?? (d.export = Object.values(d.units).some((u) => !u.address));
    for (const u of Object.values(d.units)) {
        u.deployer ?? (u.deployer = d.deployer ?? d.provider);
        u.chainId ?? (u.chainId = d.chainId);
        u.local ?? (u.local = d.local);
        const contract = await deploy(u);
    }
    for (const attr of ["verified", "exported", "deployed"])
        if (Object.values(d.units).every((u) => u[attr]))
            d[attr] = true;
    if (!d.deployer)
        d.deployer = Object.values(d.units)[0].deployer;
    if (d.export) {
        (0, exports.saveDeployment)(d, update);
        (0, exports.saveLightDeployment)(d, update);
    }
    return d;
}
exports.deployAll = deployAll;
const getArtifacts = async (d) => {
    // const basename = path.split("/").pop();
    // return loadJson(`${config.paths!.artifacts}/${path}.sol/${basename}.json`);
    const contract = typeof d === "string" ? d : d.contract;
    return await hardhat_1.artifacts.readArtifact(contract);
};
exports.getArtifacts = getArtifacts;
const isContractLocal = async (d) => /^(src|\.\/src|contracts|\.\/contracts)/.test(await (0, exports.getArtifactSource)(d));
exports.isContractLocal = isContractLocal;
const getArtifactSource = async (d) => (await (0, exports.getArtifacts)(d))?.sourceName ?? "";
exports.getArtifactSource = getArtifactSource;
const getAbiFromArtifacts = async (path) => (await (0, exports.getArtifacts)(path))?.abi;
exports.getAbiFromArtifacts = getAbiFromArtifacts;
const exportAbi = async (d) => {
    const outputPath = `abis/${d.contract}.json`;
    const proxyAbi = await (0, exports.getAbiFromArtifacts)(d.contract);
    if (!proxyAbi) {
        console.error(`Failed to export ABI found for ${d.name} [${d.contract}.sol]: ABI not found in artifacts`);
        return false;
    }
    const abiSignatures = new Set(proxyAbi.map(format_1.abiFragmentSignature));
    if (d.proxied?.length) {
        for (const p of d.proxied) {
            const implAbi = (0, exports.loadAbi)(p);
            if (!implAbi) {
                console.error(`Proxy ABI error: ${p} implementation ABI not found - skipping`);
                continue;
            }
            for (const fragment of implAbi) {
                const signature = (0, format_1.abiFragmentSignature)(fragment);
                if (!abiSignatures.has(signature)) {
                    abiSignatures.add(signature);
                    proxyAbi.push(fragment);
                }
            }
        }
    }
    if ((0, fs_1.saveJson)(`${hardhat_config_1.config.paths.registry}/${outputPath}`, { abi: proxyAbi })) {
        console.log(`Exported ABI for ${d.name} [${d.contract}.sol] to ${hardhat_config_1.config.paths.registry}/${outputPath}`);
        return true;
    }
    console.error(`Failed to export ABI for ${d.name} [${d.contract}.sol] to ${hardhat_config_1.config.paths.registry}/${outputPath}`);
    return false;
};
exports.exportAbi = exportAbi;
async function deploy(d) {
    var _a, _b;
    d.deployer ?? (d.deployer = (await hardhat_1.ethers.getSigners())[0]);
    d.chainId ?? (d.chainId = hardhat_1.network.config.chainId);
    let contract;
    if (d.address)
        d.deployed = true;
    if (d.deployed) {
        if (!d.address)
            throw new Error(`Deployment of ${d.name} rejected: marked deployed but no address provided`);
        console.log(`Skipping deployment of ${d.name} [${d.contract}.sol]: already deployed at ${d.chainId}:${d.address ?? "???"}`);
        contract = new ethers_1.Contract(d.address, (0, exports.loadAbi)(d.contract) ?? [], d.deployer);
    }
    else {
        const chainSlug = hardhat_1.network.name;
        d.name || (d.name = (0, exports.generateContractName)(d.contract, [], d.chainId));
        console.log(`Deploying ${d.name} [${d.contract}.sol] on ${chainSlug}...`);
        const params = { deployer: d.deployer };
        if (d.libraries)
            params.libraries = d.libraries;
        try {
            const overrides = d.overrides ?? {};
            if (overrides.nonce) {
                const nonceManager = d.deployer instanceof experimental_1.NonceManager
                    ? d.deployer
                    : new experimental_1.NonceManager(d.deployer);
                const txCount = await nonceManager.getTransactionCount();
                // NB: setTransactionCount() does not affect the nonce
                nonceManager.incrementTransactionCount(Number(overrides.nonce.toString()) - txCount);
                params.signer = nonceManager;
            }
            /// Create 3
            const CREATE_3_DEPLOYER = '0x6513Aedb4D1593BA12e50644401D976aebDc90d8';
            const currentTimestampInSeconds = Math.round(Date.now() / 1000);
            const unlockTime = currentTimestampInSeconds + 60;
            const deployerContract = new ethers.Contract(CREATE_3_DEPLOYER, Create3Deployer.abi, d.deployer);
            const salt = ethers.utils.hexZeroPad(BigNumber.from(101), 32);
            // const creationCode = ethers.utils.solidityPack( ['bytes', 'bytes'], [LodestarMultiStake.bytecode, ethers.utils.defaultAbiCoder.encode(['uint256'], [unlockTime])]);
            const bytecode = LodestarMultiStake.bytecode;
            const encodedUnlockTime = ethers.utils.defaultAbiCoder.encode(['uint256'], [unlockTime]);
            console.log('Bytecode:', LodestarMultiStake.bytecode);
            console.log('Bytecode Length:', LodestarMultiStake.bytecode.length);
            console.log('Encoded Unlock Time:', ethers.utils.defaultAbiCoder.encode(['uint256'], [unlockTime]));
            const creationCode = ethers.utils.solidityPack(['bytes', 'bytes'], [bytecode, encodedUnlockTime]);
            // SIMPLE TEST
            // const simpleBytecode = '0x608060405234801561001057600080fd5b5060405161011e38038061011e8339818101604052602081101561003357600080fd5b5051600055600080600081905550506100de806100556000396000f3fe6080604052600436106100275760003560e01c80630c55699c1461002c578063c3ebe8ed1461004b575b600080fd5b34801561003857600080fd5b50610041610047565b005b34801561005757600080fd5b50610041610066565b6040519081526020015b60405180910390f35b60005481565b60008190556000809054906101000a90046001600160a01b03168256fea2646970667358221220a970a4c0b638c74b1a8b8bde05b9a2b80b32c524307b9566b9b5d9f9b1b011e864736f6c63430008090033';
            // try {
            //     const testCreationCode = ethers.utils.solidityPack(
            //         ['bytes', 'bytes'],
            //         [simpleBytecode, ethers.utils.defaultAbiCoder.encode(['uint256'], [unlockTime])]
            //     );
            //     console.log('Test Creation Code:', testCreationCode);
            // } catch (error) {
            //     console.error('Error in test solidityPack:', error.message);
            // }
            // const creationCode = ethers.utils.solidityPack(['bytes', 'bytes'], [bytecode, encodedUnlockTime]);
            const deployedAddress = await deployerContract.callStatic.deploy(creationCode, salt);
            console.log(`address deployed using CREATE3: ${deployedAddress}`);
            ///
            const f = await hardhat_1.ethers.getContractFactory(d.contract, params);
            const args = d.args
                ? d.args instanceof Array
                    ? d.args
                    : [d.args]
                : undefined;
            contract = (await (args
                ? f.deploy(...args, overrides)
                : f.deploy(overrides)));
            await contract.deployed?.();
            (_a = contract).target ?? (_a.target = contract.address);
            (_b = contract).address ?? (_b.address = contract.target); // ethers v6 polyfill
            d.address = contract.address;
            if (!d.address)
                throw new Error(`no address returned`);
            d.tx = contract.deployTransaction.hash;
            d.export ?? (d.export = true);
            const isLocal = await (0, exports.isContractLocal)(d);
            if (!isLocal)
                console.log(`${d.name} is a foreign contract - not exporting ABI`);
            if (d.export && isLocal)
                d.exported = await (0, exports.exportAbi)(d);
        }
        catch (e) {
            d.deployed = false;
            console.error(`Deployment of ${d.name} failed: ${e}`);
            throw e;
        }
    }
    d.verify ?? (d.verify = true);
    if (d.verify && !d.local) {
        try {
            const ok = await verifyContract(d);
            d.verified = true;
        }
        catch (e) {
            d.verified = false;
            console.log(`Verification failed for ${d.name}: ${e}`);
        }
    }
    d.deployed = true;
    return contract;
}
exports.deploy = deploy;
const loadDeployment = (d) => (0, fs_1.loadLatestJson)(hardhat_config_1.config.paths.registry, d.name);
exports.loadDeployment = loadDeployment;
const loadAbi = (name) => (0, fs_1.loadJson)(`${hardhat_config_1.config.paths.registry}/abis/${name}.json`)?.abi;
exports.loadAbi = loadAbi;
// loads a single contract deployment unit
const loadDeploymentUnit = (d, name) => (0, exports.loadDeployment)(d)?.units?.[name];
exports.loadDeploymentUnit = loadDeploymentUnit;
const getDeployedContract = (d, name) => {
    const u = (0, exports.loadDeploymentUnit)(d, name);
    if (!u?.contract)
        throw new Error(`${d.slug}[${u.slug}] missing contract`);
    const deployer = u.deployer ?? u.provider ?? d.deployer ?? d.provider;
    if (!u.address || !deployer)
        throw new Error(`${d.slug}[${u.slug}] missing address, contract, abi or deployer`);
    const abi = (0, exports.loadAbi)(u.contract);
    if (!abi)
        throw new Error(`${d.slug}[${u.slug}] missing ABI`);
    return new ethers_1.Contract(u.address, abi, deployer);
};
exports.getDeployedContract = getDeployedContract;
const getDeployedAddress = (d, name) => (0, exports.loadDeploymentUnit)(d, name)?.address;
exports.getDeployedAddress = getDeployedAddress;
const saveDeployment = (d, update = true, light = false) => {
    const basename = (0, format_1.slugify)(d.name) + (light ? "-light" : "");
    const prevFilename = update
        ? (0, fs_1.getLatestFileName)(`${hardhat_config_1.config.paths.registry}/deployments`, basename)
        : undefined;
    const filename = prevFilename ?? `${basename}-${(0, format_1.nowEpochUtc)()}.json`;
    const path = `${hardhat_config_1.config.paths.registry}/deployments/${filename}`;
    const toSave = {
        name: d.name,
        version: d.version,
        chainId: d.chainId,
        units: {},
        ...(!light && {
            slug: d.slug ?? (0, format_1.slugify)(d.name),
            verified: d.verified,
            exported: d.exported,
            local: d.local,
            deployer: d.deployer.address,
        }),
    };
    if (d.units) {
        for (const k of Object.keys(d.units)) {
            const u = d.units[k];
            toSave.units[k] = {
                contract: u.contract,
                address: u.address,
                chainId: u.chainId ?? d.chainId,
                ...(!light && {
                    slug: u.slug ?? (0, format_1.slugify)(u.name),
                    local: u.local ?? d.local,
                    tx: u.tx,
                    deployer: (u.deployer ?? d.deployer).address,
                    exported: u.exported,
                    verified: u.verified,
                    args: u.args,
                    libraries: u.libraries,
                }),
            };
        }
    }
    (0, fs_1.saveJson)(path, toSave);
    console.log(`${prevFilename ? "Updated" : "Saved"} ${light ? "light " : ""}deployment ${hardhat_config_1.config.paths.registry}/deployments/${filename}`);
};
exports.saveDeployment = saveDeployment;
const saveLightDeployment = (d, update = true) => (0, exports.saveDeployment)(d, update, true);
exports.saveLightDeployment = saveLightDeployment;
exports.writeRegistry = exports.saveDeployment;
exports.writeLightRegistry = exports.saveLightDeployment;
const saveDeploymentUnit = (d, u, update = true) => {
    const deployment = (0, exports.loadDeployment)(d);
    if (deployment.units) {
        deployment.units[u.name] = u;
    }
    else {
        deployment.units = { [u.name]: u };
    }
    (0, exports.saveDeployment)(deployment, update);
    (0, exports.saveLightDeployment)(deployment, update);
};
exports.saveDeploymentUnit = saveDeploymentUnit;
const generateContractName = (contract, assets, chainId) => `${contract} ${assets.join("-")}${chainId ? ` ${networks_1.networkById[chainId].name}` : ""}`;
exports.generateContractName = generateContractName;
async function verifyContract(d) {
    if (!d?.address)
        throw new Error(`Cannot verify contract ${d?.name ?? "?"}: no address provided - check if contract was deployed`);
    if (d.local) {
        console.log("Skipping verification for local deployment");
        return;
    }
    // if (d.verified || await isAlreadyVerified(d)) {
    //   console.log(`Skipping verification for ${d.name}: already verified`);
    //   return;
    // }
    const args = {
        name: d.contract,
        address: d.address,
    };
    if (d.args)
        args.constructorArguments = d.args;
    if (d.libraries) {
        const libraries = {};
        // replace solc-style library paths with names for verification
        for (const [path, address] of Object.entries(d.libraries)) {
            const tokens = path.split(":");
            const name = tokens[tokens.length - 1];
            libraries[name] = address;
        }
        args.libraries = libraries;
    }
    if (hardhat_1.network.name.includes("tenderly")) {
        await hardhat_1.tenderly.verify(args);
        console.log("Contract verified on Tenderly ✅");
    }
    else {
        if (!networks_1.networkById[d.chainId].explorerApi)
            throw new Error(`Cannot verify contract ${d.name}: no explorer API provided for network ${d.chainId}`);
        console.log(`Verifying ${d.name} on ${networks_1.networkById[d.chainId].explorerApi}...`);
        await (0, hardhat_1.run)("verify:verify", args);
        console.log("Contract verified on explorer ✅");
    }
    d.verified = true;
    return true;
}
exports.verifyContract = verifyContract;
