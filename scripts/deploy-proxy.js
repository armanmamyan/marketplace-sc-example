const { ethers, upgrades } = require("hardhat");

async function main() {
  const gas = await ethers.provider.getGasPrice();

  const NFTMarket = await ethers.getContractFactory("SpectrumMarketPlace");
  console.log("Start Deployment...");

  const marketContract = await upgrades.deployProxy(NFTMarket, [], {
    gasPrice: gas,
    initializer: 'initialvalue'
  });

  await marketContract.deployed();

  console.log("Contract deployed to the account:", marketContract.address); 
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
