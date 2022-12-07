const { ethers, upgrades } = require("hardhat");

const UPGRADEABLE_PROXY = "Insert your proxy contract address here";

async function main() {
  const gas = await ethers.provider.getGasPrice();
  const NFTMarket = await ethers.getContractFactory("NFT_Marketplace");
  console.log("Start Deployment...");

  const upgrade = await upgrades.upgradeProxy(UPGRADEABLE_PROXY, NFTMarket, {
    gasPrice: gas
 });

 console.log("V1 Upgraded to V2");
 console.log("V2 Contract Deployed To:", upgrade.add);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
