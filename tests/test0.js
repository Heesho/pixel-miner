const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
const divDec = (amount, decimals = 18) => amount / 10 ** decimals;
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { execPath } = require("process");

const AddressZero = "0x0000000000000000000000000000000000000000";
const AddressDead = "0x000000000000000000000000000000000000dEaD";

let owner, multisig, treasury, user0, user1, user2, user3;
let weth, pixel, miner, multicall;
let auction0, auction1;

describe("local: test0", function () {
  before("Initial set up", async function () {
    console.log("Begin Initialization");

    [owner, multisig, treasury, user0, user1, user2, user3] =
      await ethers.getSigners();

    const wethArtifact = await ethers.getContractFactory("Base");
    weth = await wethArtifact.deploy();
    console.log("- WETH Initialized");

    const pixelArtifact = await ethers.getContractFactory("Pixel");
    pixel = await pixelArtifact.deploy();
    console.log("- Pixel Initialized");

    const minerArtifact = await ethers.getContractFactory("Miner");
    miner = await minerArtifact.deploy(
      weth.address,
      pixel.address,
      treasury.address
    );
    console.log("- Miner Initialized");

    const auctionArtifact = await ethers.getContractFactory("Auction");
    auction0 = await auctionArtifact.deploy(
      convert("0.001", 18),
      pixel.address,
      AddressZero,
      604800,
      convert("1.2", 18),
      convert("0.001", 18)
    );
    console.log("- Auction0 Initialized");
    auction1 = await auctionArtifact.deploy(
      convert("0.001", 18),
      pixel.address,
      AddressDead,
      604800,
      convert("1.2", 18),
      convert("0.001", 18)
    );
    console.log("- Auction1 Initialized");

    const multicallArtifact = await ethers.getContractFactory("Multicall");
    multicall = await multicallArtifact.deploy(miner.address);
    console.log("- Multicall Initialized");

    await multicall.transferOwnership(multisig.address);
    console.log("- ownership transferred to multisig");

    await multicall.connect(multisig).setAuction(auction0.address);
    console.log("- auction0 set to multicall");

    console.log("Initialization Complete");
    console.log();
  });

  it("transfer ownership to multisig", async function () {
    console.log("******************************************************");
    await miner.transferOwnership(multisig.address);
    console.log("- ownership transferred to multisig");
  });
});
