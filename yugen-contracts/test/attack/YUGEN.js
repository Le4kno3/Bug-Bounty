const { ethers } = require("hardhat");
const chaiAsPromised = require("chai-as-promised");
const chai = require("chai");
chai.use(chaiAsPromised);
const { BigNumber } = require("@ethersproject/bignumber");
const { assert } = require("chai");

const addressTokenHolder = "0x820De2eb0EE8007Ee237E02aCe3BF2b9cD0DdF1a";

describe("FYGN Contract", function () {
  let minter, deployer, allAccounts;

  before(async function () {
    allAccounts = await ethers.getSigners();
    minter = allAccounts[2];
    deployer = allAccounts[0];

    const YGN = await ethers.getContractFactory("YUGEN");
    this.ygnInstance = await YGN.deploy(addressTokenHolder);
    await this.ygnInstance.deployed();
    console.log("YGN deployed at " + this.ygnInstance.address);
  });

  it("meta transaction check", async function () {
    // call _delegate
    await this.ygnInstance.executeMetaTransaction();
  });

  it("should fail when non-minter tries to mint tokens", async function () {
    const nonMinter = allAccounts[3];
    await chai.assert.isRejected(
      fygnInstance
        .connect(nonMinter)
        .mint(nonMinter.address, BigNumber.from("1000000000000000000000")),
      "User not whitelisted"
    );
  });

  it("should allow whitelisted minter to mint tokens", async function () {
    await fygnInstance.connect(deployer).whitelistMinter(minter.address);

    const isMinter = await fygnInstance.whitelistedMinters(minter.address);

    assert.isTrue(isMinter);

    const user = allAccounts[4];
    const amount = BigNumber.from("1000000000000000000000");

    const userBalanceBeforeMinting = await fygnInstance.balanceOf(user.address);
    await fygnInstance.connect(minter).mint(user.address, amount);

    const userBalanceAfterMinting = await fygnInstance.balanceOf(user.address);

    assert.strictEqual(
      userBalanceAfterMinting.sub(userBalanceBeforeMinting),
      amount,
      `Expected increase in balance for user is ${amount} but got ${userBalanceAfterMinting.sub(
        userBalanceBeforeMinting
      )}`
    );
  });
});
