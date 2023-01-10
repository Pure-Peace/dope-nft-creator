/* eslint-disable @typescript-eslint/no-unused-vars */
import {BigNumber, BigNumberish} from 'ethers';

export type DeployConfig = {
  collectionInitializeData: {
    name: string;
    symbol: string;
    metadataModule: string;
    baseURI: string;
    contractURI: string;
    fundingRecipient: string;
    royaltyBPS: BigNumberish;
    collectionMaxMintableLower: BigNumberish;
    collectionMaxMintableUpper: BigNumberish;
    collectionCutoffTime: BigNumberish;
    flags: BigNumberish;
  };
  feeConfig: {
    feeRecipient: string;
    platformFeeBPS: BigNumberish;
  };
  dopeNFTConfig: {
    shouldDeploy: boolean;
    name: string;
    symbol: string;
    baseURI: string;
    contractURI: string;
  };
};

const toTokenAmount = (amount: BigNumberish, tokenDecimal: BigNumberish) => {
  return BigNumber.from(amount).mul(BigNumber.from(10).pow(tokenDecimal));
};

const config: {[key: string]: DeployConfig} = {
  mainnet: {
    collectionInitializeData: {
      name: 'DopeNFTCollection',
      symbol: 'DOPENFT',
      metadataModule: '0x0000000000000000000000000000000000000000',
      baseURI: 'baseURI',
      contractURI: 'contractURI',
      fundingRecipient: '0x0000000000000000000000000000000000000001',
      royaltyBPS: 0,
      collectionMaxMintableLower: 0,
      collectionMaxMintableUpper: 0,
      collectionCutoffTime: 0,
      flags: 1,
    },
    feeConfig: {
      feeRecipient: 'deployer',
      platformFeeBPS: 500,
    },
    dopeNFTConfig: {
      shouldDeploy: true,
      name: 'Dope',
      symbol: 'DOPE',
      baseURI: '',
      contractURI: '',
    },
  },
  goerli: {
    collectionInitializeData: {
      name: 'DopeNFTCollection',
      symbol: 'DOPENFT',
      metadataModule: '0x0000000000000000000000000000000000000000',
      baseURI: 'baseURI',
      contractURI: 'contractURI',
      fundingRecipient: '0x0000000000000000000000000000000000000001',
      royaltyBPS: 0,
      collectionMaxMintableLower: 0,
      collectionMaxMintableUpper: 0,
      collectionCutoffTime: 0,
      flags: 1,
    },
    feeConfig: {
      feeRecipient: 'deployer',
      platformFeeBPS: 500,
    },
    dopeNFTConfig: {
      shouldDeploy: true,
      name: 'DopeTest',
      symbol: 'DOPETEST',
      baseURI: '',
      contractURI: '',
    },
  },
};

export default config;
