import hre, { ethers } from "hardhat";
import { Metadata } from "../typechain-types";
import { cofhejs, Encryptable } from "cofhejs/node";
import { appendMetadata } from "./metadata";
import { expect } from "chai";

describe("Metadata", function () {
  // We define a fixture to reuse the same setup in every test.
  const deployContracts = async () => {
    // Deploy Metadata
    const metadataFactory = await ethers.getContractFactory("Metadata");
    const metadata = (await metadataFactory.deploy()) as Metadata;
    await metadata.waitForDeployment();

    return { metadata };
  };

  async function setupFixture() {
    const [owner, bob, alice, eve] = await ethers.getSigners();
    const { metadata } = await deployContracts();

    await hre.cofhe.initializeWithHardhatSigner(owner);

    return { owner, bob, alice, eve, metadata };
  }

  describe("Typescript Solidity matching", async function () {
    it("euint8", async function () {
      const { metadata } = await setupFixture();

      const [inEuint8] = await hre.cofhe.expectResultSuccess(await cofhejs.encrypt([Encryptable.uint8(5n)]));
      const inEuint8Hash = inEuint8.ctHash;
      await metadata.addEuint8Metadata(inEuint8);

      const inEuint8AppendedHash = await metadata.metaMap(inEuint8Hash);

      const tsAppended = appendMetadata(inEuint8.ctHash, inEuint8.securityZone, inEuint8.utype, false);
      expect(tsAppended).to.equal(inEuint8AppendedHash);
    });
  });
});
