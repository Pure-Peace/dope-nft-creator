/* eslint-disable @typescript-eslint/explicit-module-boundary-types */
/* eslint-disable @typescript-eslint/no-var-requires */
import hre from 'hardhat';
import {BigNumber, Contract, ContractTransaction, Signer} from 'ethers';
import {DeployResult} from 'hardhat-deploy/types';
import fs from 'fs';
import path from 'path';

import {GAS_LIMIT} from './constants';
import {getContractForEnvironment} from '../test/utils/getContractForEnvironment';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {NFTCollection} from '../typechain/NFTCollection';

import {
  ContractList,
  IMPL_PREFIX,
  PROXY_CONTRACTS,
  UPBEACON_PREFIX,
  UPGRADEABLE_CONTRACTS,
  ZERO_ADDRESS,
} from './constants';

import NETWORK_DEPLOY_CONFIG, {DeployConfig} from '../deploy.config';

require('dotenv').config();
const prompts = require('prompts');

const {deploy: _dep} = hre.deployments;

const BASE_PATH = `./deployments/${hre.network.name}`;

let __DEPLOY_CONFIG: DeployConfig;
export function deployConfig() {
  if (__DEPLOY_CONFIG) return __DEPLOY_CONFIG;
  __DEPLOY_CONFIG = NETWORK_DEPLOY_CONFIG[hre.network.name];
  if (!__DEPLOY_CONFIG) {
    throw new Error(`Unconfigured network: "${hre.network.name}"`);
  }
  return __DEPLOY_CONFIG;
}

export type DeployFunction = (
  deployName: string,
  contractName: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  args?: string[] | any[]
) => Promise<DeployResult>;
export type Deployments = {[key: string]: DeployResult};

export async function setup(): Promise<{
  accounts: SignerWithAddress[];
  deployer: SignerWithAddress;
  deploy: (
    deployName: string,
    contractName: string,
    args?: any[]
  ) => Promise<DeployResult>;
}> {
  const accounts = await hre.ethers.getSigners();
  const deployer = accounts[0];
  console.log('Network:', hre.network.name);
  console.log('Signer:', deployer.address);
  try {
    console.log(
      'Signer balance:',
      hre.ethers.utils.formatEther(await deployer.getBalance()).toString(),
      'ETH'
    );
  } catch (_) {}

  return {
    accounts,
    deployer,
    deploy: async (
      deployName: string,
      contractName: string,
      args: any[] = []
    ): Promise<DeployResult> => {
      console.log(
        `\n>> Deploying contract "${deployName}" ("${contractName}")...`
      );
      const deployResult = await _dep(deployName, {
        contract: contractName,
        args: args,
        log: true,
        skipIfAlreadyDeployed: false,
        gasLimit: GAS_LIMIT,
        gasPrice: '2500000000',
        from: deployer.address,
      });
      console.log(
        `${
          deployResult.newlyDeployed ? '[New]' : '[Reused]'
        } contract "${deployName}" ("${contractName}") deployed at "${
          deployResult.address
        }" \n - tx: "${deployResult.transactionHash}" \n - gas: ${
          deployResult.receipt?.gasUsed
        } \n - deployer: "${deployer.address}"`
      );
      return deployResult;
    },
  };
}

export function waitContractCall(
  transcation: ContractTransaction
): Promise<void> {
  return new Promise<void>((resolve) => {
    transcation.wait().then((receipt) => {
      console.log(
        `Waiting transcation: "${receipt.transactionHash}" (block: ${receipt.blockNumber} gasUsed: ${receipt.gasUsed})`
      );
      if (receipt.status === 1) {
        return resolve();
      }
    });
  });
}

export async function tryGetContractForEnvironment<T extends Contract>(
  contractName: string,
  deployer: Signer
): Promise<{err: any; contract: T | undefined}> {
  const result: {err: any; contract: T | undefined} = {
    err: undefined,
    contract: undefined,
  };
  try {
    result.contract = (await getContractForEnvironment(
      hre,
      contractName as any,
      deployer
    )) as T;
    return result;
  } catch (err) {
    result.err = err;
  }
  try {
    const deployment = JSON.parse(
      fs.readFileSync(path.join(BASE_PATH, `${contractName}.json`)).toString()
    );
    result.contract = (await hre.ethers.getContractAt(
      deployment.abi,
      deployment.address,
      deployer
    )) as unknown as T;
    return result;
  } catch (err2) {
    result.err = err2;
  }
  return result;
}

export async function getContractAt<T extends Contract>(
  contractName: string,
  address: string,
  signer?: string | Signer | undefined
): Promise<T> {
  const realSigner =
    typeof signer === 'string' ? await hre.ethers.getSigner(signer) : signer;
  try {
    const contract = await hre.deployments.get(contractName);
    return hre.ethers.getContractAt(
      contract.abi,
      address,
      realSigner
    ) as Promise<T>;
  } catch (err) {
    return hre.ethers.getContractAt(
      contractName,
      address,
      realSigner
    ) as Promise<T>;
  }
}

export async function getContractFromEnvOrPrompts<T extends Contract>(
  {
    contractNameEnv,
    contractName,
  }: {contractNameEnv: string; contractName?: string},
  deployer: Signer
): Promise<T> {
  console.log(`\nGetting contract "${contractNameEnv}"...`);
  const {contract, err} = await tryGetContractForEnvironment<T>(
    contractNameEnv,
    deployer
  );
  if (!contract) {
    const {contractAddress} = await prompts({
      type: 'text',
      name: 'contractAddress',
      message:
        'Unable to find the contract from the environment, please enter the address manually:',
    });
    return await getContractAt<T>(
      contractName || contractNameEnv,
      contractAddress,
      deployer
    );
  }
  return contract;
}

export function nullOrDeployer(
  address: string | undefined | null,
  deployer: SignerWithAddress
): string {
  if (!address || address === 'deployer') return deployer.address;
  return address;
}

export async function deployImpl(
  deploy: DeployFunction,
  contracts: ContractList
) {
  const results: Deployments = {};
  for (const i of contracts) {
    const key = typeof i !== 'string' ? Object.keys(i)[0] : i;
    const n = `Impl${key}`;
    results[n] = await deploy(n, key);
  }
  return results;
}

export async function deployUpBeacon(
  deploy: DeployFunction,
  contracts: ContractList,
  implDeployments: Deployments
) {
  const results: Deployments = {};
  for (const i of contracts) {
    const key = typeof i !== 'string' ? Object.keys(i)[0] : i;
    if (typeof i !== 'string') {
      for (const child of i[key]) {
        const n = `${UPBEACON_PREFIX}${child}`;
        results[n] = await deploy(n, 'UpgradeableBeacon', [
          implDeployments[`${IMPL_PREFIX}${key}`].address,
        ]);
      }
    } else {
      const n = `${UPBEACON_PREFIX}${key}`;
      results[n] = await deploy(n, 'UpgradeableBeacon', [
        implDeployments[`${IMPL_PREFIX}${key}`].address,
      ]);
    }
  }
  return results;
}

export async function deployBeaconProxy(
  deploy: DeployFunction,
  contracts: ContractList,
  upBeaconDeployments: Deployments
) {
  const results: Deployments = {};
  for (const i of contracts) {
    const key = typeof i !== 'string' ? Object.keys(i)[0] : i;
    if (typeof i !== 'string') {
      for (const child of i[key]) {
        const n = `${child}Proxy`;
        results[n] = await deploy(n, 'BeaconProxy', [
          upBeaconDeployments[`${UPBEACON_PREFIX}${key}`].address,
          [],
        ]);
      }
    } else {
      const n = `${key}Proxy`;
      results[n] = await deploy(n, 'BeaconProxy', [
        upBeaconDeployments[`${UPBEACON_PREFIX}${key}`].address,
        [],
      ]);
    }
  }
  return results;
}

export async function getDeployedContracts(deployer: SignerWithAddress) {
  console.log('\n>>>>>>>>> Getting deployed contracts...\n');

  return {};
}

export async function deployUpgradeableContract(
  deploy: DeployFunction,
  contractName: string,
  rename?: string
) {
  const implReuslt = await deploy(
    `Impl${rename || contractName}`,
    contractName
  );
  const upBeaconResult = await deploy(
    `UpBeacon${rename || contractName}`,
    'UpgradeableBeacon',
    [implReuslt.address]
  );
  const proxyResult = await deploy(
    `${rename || contractName}Proxy`,
    'BeaconProxy',
    [upBeaconResult.address, []]
  );
  return {implReuslt, upBeaconResult, proxyResult};
}

export async function tryInitializeUpgradeableContract<T extends Contract>(
  contract: T,
  initializeArgs: any[]
) {
  try {
    await contract.callStatic.initialize(...initializeArgs);
  } catch (err) {
    console.log('Already initialized or initialize error');
    return;
  }

  console.log('Initializing...');
  await waitContractCall(await contract.initialize(...initializeArgs));
}

export async function getProxies(
  deploy: (
    deployName: string,
    contractName: string,
    args?: any[]
  ) => Promise<DeployResult>,
  marketRegistry: {
    proxies: string[];
    isLibs: boolean[];
  }
) {
  const proxies = [];
  for (const i of marketRegistry.proxies) {
    if (!i.startsWith('0x')) {
      const dep = await deploy(i, i);
      proxies.push(dep.address);
    } else {
      proxies.push(i);
    }
  }
  if (proxies.length != marketRegistry.isLibs.length)
    throw new Error('Invalid marketRegistry config length');

  return proxies;
}

export async function deployAndSetupContracts() {
  const {deployer, deploy} = await setup();

  const {collectionInitializeData, feeConfig} = deployConfig();

  await deploy('NFTCollection', 'NFTCollection', []);

  const NFTColletion = await getContractForEnvironment<NFTCollection>(
    hre,
    'NFTCollection',
    deployer
  );

  await tryInitializeUpgradeableContract(NFTColletion, [
    collectionInitializeData.name,
    collectionInitializeData.symbol,
    collectionInitializeData.metadataModule,
    collectionInitializeData.baseURI,
    collectionInitializeData.contractURI,
    collectionInitializeData.fundingRecipient,
    collectionInitializeData.royaltyBPS,
    collectionInitializeData.collectionMaxMintableLower,
    collectionInitializeData.collectionMaxMintableUpper,
    collectionInitializeData.collectionCutoffTime,
    collectionInitializeData.flags,
  ]);

  await deploy('NFTCreator', 'NFTCreator', [NFTColletion.address]);
  const feeRegistryDep = await deploy('NFTFeeRegistry', 'NFTFeeRegistry', [
    feeConfig.feeRecipient === 'deployer'
      ? deployer.address
      : feeConfig.feeRecipient,
    feeConfig.platformFeeBPS,
  ]);
  await deploy('CollectionMaxMinter', 'CollectionMaxMinter', [
    feeRegistryDep.address,
  ]);
  await deploy('FixedPriceSignatureMinter', 'FixedPriceSignatureMinter', [
    feeRegistryDep.address,
  ]);
  await deploy('MerkleDropMinter', 'MerkleDropMinter', [
    feeRegistryDep.address,
  ]);
  await deploy('RangeCollectionMinter', 'RangeCollectionMinter', [
    feeRegistryDep.address,
  ]);
}
