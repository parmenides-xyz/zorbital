import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Deploy zOrbitalFactory
  const ZOrbitalFactory = await ethers.getContractFactory("zOrbitalFactory");
  const factory = await ZOrbitalFactory.deploy();
  await factory.waitForDeployment();

  const factoryAddress = await factory.getAddress();
  console.log("zOrbitalFactory deployed to:", factoryAddress);

  // Deploy test FHERC20 tokens (for demo)
  const HybridFHERC20 = await ethers.getContractFactory("HybridFHERC20");

  console.log("\nDeploying test tokens...");

  const token0 = await HybridFHERC20.deploy("Encrypted USDC", "eUSDC");
  await token0.waitForDeployment();
  console.log("eUSDC deployed to:", await token0.getAddress());

  const token1 = await HybridFHERC20.deploy("Encrypted USDT", "eUSDT");
  await token1.waitForDeployment();
  console.log("eUSDT deployed to:", await token1.getAddress());

  const token2 = await HybridFHERC20.deploy("Encrypted DAI", "eDAI");
  await token2.waitForDeployment();
  console.log("eDAI deployed to:", await token2.getAddress());

  // Create a pool with all 3 tokens
  const tokens = [
    await token0.getAddress(),
    await token1.getAddress(),
    await token2.getAddress()
  ];
  const radius = 1000000n; // 1M units radius

  console.log("\nCreating pool with tokens:", tokens);
  console.log("Radius:", radius.toString());

  const tx = await factory.createPool(tokens, radius);
  const receipt = await tx.wait();

  // Get pool address from event logs
  let poolAddress = "0x0000000000000000000000000000000000000000";
  for (const log of receipt?.logs || []) {
    try {
      const parsed = factory.interface.parseLog({
        topics: log.topics as string[],
        data: log.data
      });
      if (parsed?.name === "PoolCreated") {
        poolAddress = parsed.args[2]; // pool address is 3rd arg
        break;
      }
    } catch {}
  }

  console.log("\nzOrbital pool created at:", poolAddress);

  // Also check allPools
  const poolCount = await factory.allPoolsLength();
  console.log("Total pools created:", poolCount.toString());
  if (poolCount > 0n) {
    const firstPool = await factory.allPools(0);
    console.log("First pool from allPools:", firstPool);
  }

  console.log("\n=== Deployment Summary ===");
  console.log("Factory:", factoryAddress);
  console.log("eUSDC:", await token0.getAddress());
  console.log("eUSDT:", await token1.getAddress());
  console.log("eDAI:", await token2.getAddress());
  console.log("Pool:", poolAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
