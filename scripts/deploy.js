const { ethers } = require("hardhat");
const { utils, BigNumber } = require("ethers");
const hre = require("hardhat");
const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay));
const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
const AddressZero = "0x0000000000000000000000000000000000000000";

/*===================================================================*/
/*===========================  SETTINGS  ============================*/

const MULTISIG_ADDRESS = "0x7a8C895E7826F66e1094532cB435Da725dc3868f"; // Multisig Address
const TREASURY_ADDRESS = "0x7a8C895E7826F66e1094532cB435Da725dc3868f"; // Treasury Address
const ENTROPY_ADDRESS = "0x6E7D74FA7d5c90FEF9F0512987605a6d546181Bb"; // Entropy Address
const WETH_ADDRESS = "0x4200000000000000000000000000000000000006"; // WETH Address
const LP_ADDRESS = "0x0000000000000000000000000000000000000000"; // LP Address
const ADDRESS_DEAD = "0x000000000000000000000000000000000000dEaD";
const AUCTION_PERIOD = 86400; // 1 day
const PRICE_MULTIPLIER = convert("1.2", 18); // 120%
const MIN_INIT_PRICE = convert("1", 18); // 1 LP

/*===========================  END SETTINGS  ========================*/
/*===================================================================*/

// Contract Variables
let pixel, miner, auction, multicall;

/*===================================================================*/
/*===========================  CONTRACT DATA  =======================*/

async function getContracts() {
  pixel = await ethers.getContractAt(
    "contracts/Pixel.sol:Pixel",
    "0xa23952322DaEbcfeE1B953B55bFEA858E50B785b"
  );
  miner = await ethers.getContractAt(
    "contracts/Miner.sol:Miner",
    "0x823dE5874A68c269324e44576fB479Ee5905c6e0"
  );
  multicall = await ethers.getContractAt(
    "contracts/Multicall.sol:Multicall",
    "0xfEaCABeeB2B20C526d0Bb1Db2B32eDCf65360E98"
  );
  // auction = await ethers.getContractAt("contracts/Auction.sol:Auction", "");
  // console.log("Contracts Retrieved");
}

/*===========================  END CONTRACT DATA  ===================*/
/*===================================================================*/

async function deployPixel() {
  console.log("Starting Pixel Deployment");
  const pixelArtifact = await ethers.getContractFactory("Pixel");
  const pixelContract = await pixelArtifact.deploy();
  pixel = await pixelContract.deployed();
  await sleep(5000);
  console.log("Pixel Deployed at:", pixel.address);
}

async function verifyPixel() {
  console.log("Starting Pixel Verification");
  await hre.run("verify:verify", {
    address: pixel.address,
    contract: "contracts/Pixel.sol:Pixel",
  });
  console.log("Pixel Verified");
}
async function deployMiner() {
  console.log("Starting Miner Deployment");
  const minerArtifact = await ethers.getContractFactory("Miner");
  const minerContract = await minerArtifact.deploy(
    WETH_ADDRESS,
    pixel.address,
    ENTROPY_ADDRESS,
    TREASURY_ADDRESS,
    {
      gasPrice: ethers.gasPrice,
    }
  );
  miner = await minerContract.deployed();
  await sleep(5000);
  console.log("Miner Deployed at:", miner.address);
}

async function verifyMiner() {
  console.log("Starting Miner Verification");
  await hre.run("verify:verify", {
    address: miner.address,
    contract: "contracts/Miner.sol:Miner",
    constructorArguments: [
      WETH_ADDRESS,
      pixel.address,
      ENTROPY_ADDRESS,
      TREASURY_ADDRESS,
    ],
  });
  console.log("Miner Verified");
}

async function deployMulticall() {
  console.log("Starting Multicall Deployment");
  const multicallArtifact = await ethers.getContractFactory("Multicall");
  const multicallContract = await multicallArtifact.deploy(miner.address, {
    gasPrice: ethers.gasPrice,
  });
  multicall = await multicallContract.deployed();
  await sleep(5000);
  console.log("Multicall Deployed at:", multicall.address);
}

async function verifyMulticall() {
  console.log("Starting Multicall Verification");
  await hre.run("verify:verify", {
    address: multicall.address,
    contract: "contracts/Multicall.sol:Multicall",
    constructorArguments: [miner.address],
  });
  console.log("Multicall Verified");
}

async function deployAuction() {
  console.log("Starting Auction Deployment");
  const auctionArtifact = await ethers.getContractFactory("Auction");
  const auctionContract = await auctionArtifact.deploy(
    MIN_INIT_PRICE,
    LP_ADDRESS,
    ADDRESS_DEAD,
    AUCTION_PERIOD,
    PRICE_MULTIPLIER,
    MIN_INIT_PRICE,
    {
      gasPrice: ethers.gasPrice,
    }
  );
  auction = await auctionContract.deployed();
  await sleep(5000);
  console.log("Auction Deployed at:", auction.address);
}

async function verifyAuction() {
  console.log("Starting Auction Verification");
  await hre.run("verify:verify", {
    address: auction.address,
    contract: "contracts/Auction.sol:Auction",
    constructorArguments: [
      MIN_INIT_PRICE,
      LP_ADDRESS,
      ADDRESS_DEAD,
      AUCTION_PERIOD,
      PRICE_MULTIPLIER,
      MIN_INIT_PRICE,
    ],
  });
  console.log("Auction Verified");
}

async function printDeployment() {
  console.log("**************************************************************");
  console.log("Pixel: ", pixel.address);
  console.log("Miner: ", miner.address);
  console.log("Multicall: ", multicall.address);
  // console.log("Auction: ", auction.address);
  console.log("**************************************************************");
}

async function main() {
  const [wallet] = await ethers.getSigners();
  console.log("Using wallet: ", wallet.address);

  await getContracts();

  //===================================================================
  // Deploy System
  //===================================================================

  // console.log("Starting System Deployment");
  // await deployPixel();
  // await deployMiner();
  // await deployAuction();
  // await deployMulticall();
  // await printDeployment();

  /*********** UPDATE getContracts() with new addresses *************/

  //===================================================================
  // Verify System
  //===================================================================

  // console.log("Starting System Verification");
  // await verifyPixel();
  // await sleep(5000);
  // await verifyMiner();
  // await sleep(5000);
  // await verifyMulticall();
  // await sleep(5000);
  // await verifyAuction();
  // await sleep(5000);

  //===================================================================
  // Transactions
  //===================================================================

  // set auction on multicall
  // await multicall.setAuction(auction.address);
  // console.log("Auction set on Multicall");

  // set treasury on miner to auction
  // await miner.setTreasury(auction.address);
  // console.log("Treasury set on Miner to Auction");

  // set ownership of miner to multisig
  // await miner.transferOwnership(MULTISIG_ADDRESS);
  // console.log("Ownership of Miner transferred to Multisig");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
