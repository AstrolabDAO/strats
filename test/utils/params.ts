import { ethers } from "hardhat";

const params: { [key: string]: any } = {
  /////////////////////////////////////////////
  ///// Strategy Params ///////////////////////
  feeAmount: 180,
  ///// HOP - Arbitrum  ///////////////////////
  ///// CVX - Ethereum  ///////////////////////
  CvxpoolPid: 100,
  CvxtokenIndex: 1,
  ///// AURA - Ethereum ////////////////////////
  AuraPid: 65,
  ///// SYN - Optimism
  SynPoolPid: 1,
  SynTokenIndex: 1, // USDC
  SynReceivingChainID: 1, // Ethereum
};

export default params;
