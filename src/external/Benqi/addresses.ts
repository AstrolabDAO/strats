import { addresses } from "@astrolabs/hardhat";
import merge from "lodash/merge";

// cf. https://docs.benqi.fi/resources/contracts/benqi-liquidity-market
export default merge(addresses, {
  43114: {
    Benqi: {
      Comptroller: "0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4",
      qiAVAX: "0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c",
      qisAVAX: "0xF362feA9659cf036792c9cb02f8ff8198E21B4cB",
      qiBTCb: "0x89a415b3D20098E6A6C8f7a59001C67BD3129821",
      qiBTCe: "0xe194c4c5aC32a3C9ffDb358d9Bfd523a0B6d1568",
      qiETH: "0x334AD834Cd4481BB02d09615E7c11a00579A7909",
      qiLINK: "0x4e9f683A27a6BdAD3FC2764003759277e93696e6",
      qiUSDTe: "0xc9e5999b8e75C3fEB117F6f73E664b9f3C8ca65C", // qiUSDT (bridged)
      qiUSDCe: "0xBEb5d47A3f720Ec0a390d04b4d41ED7d9688bC7F", // qiUSDC (bridged)
      qiUSDT: "0xd8fcDa6ec4Bdc547C0827B8804e89aCd817d56EF", // qiUSDTn (native)
      qiUSDC: "0xB715808a78F6041E46d61Cb123C9B4A27056AE9C", // qiUSDCn (native)
      qiDAI: "0x835866d37AFB8CB8F8334dCCdaf66cf01832Ff5D",
      qiBUSD: "0x872670CcAe8C19557cC9443Eff587D7086b8043A",
      qiQI: "0x35Bd6aedA81a7E5FC7A7832490e71F757b0cD9Ce",
      PGL: "0xE530dC2095Ef5653205CF5ea79F8979a7028065c",
      PGLStaking: "0x784DA19e61cf348a8c54547531795ECfee2AfFd1",
      QiErc20Delegate: [
        "0x76145e99d3F4165A313E8219141ae0D26900B710",
        "0xF28043598A1824053097d5C4FedD7CD1cf731E76", // For qiUSDTn, qiUSDCn
      ],
      QiTokenSaleDistributorProxy: "0x77533A0b34cd9Aa135EBE795dc40666Ca295C16D",
      Maximillion: "0xd78DEd803b28A5A9C860c2cc7A4d84F611aA4Ef8",
      JumpRateModel: "0xC436F5BC8A8bD9c9e240A2A83D44705Ec87A9D55",
      LinearRateModel: "0xF805e22C81EF330967EEC52f7eDb0C6B31Fd5cCf",
      rewardTokens: [addresses[43114].tokens.QI, addresses[43114].tokens.WAVAX],
    },
  },
} as { [chainId: number]: { [id: string]: any } });