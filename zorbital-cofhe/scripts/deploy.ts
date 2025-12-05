import { ethers } from "hardhat";

// Mock stablecoins from orbital-core (Base Sepolia)
const MOCK_USDC = "0x5E364C53fC867b060096bDc48A74401a6ED6b04a";
const MOCK_USDT = "0xc04669a9c26341F62427b67B813E97426a8670C3";
const MOCK_PYUSD = "0x073285F3Fe2b388A0cf4c2f0DC9ad13197531Cbf";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Deploy FHERC20Wrapper contracts for each mock stablecoin
  const FHERC20Wrapper = await ethers.getContractFactory("FHERC20Wrapper");

  console.log("\nDeploying FHERC20 Wrapper tokens...");

  // eUSDC - wraps mUSDC
  const eUSDC = await FHERC20Wrapper.deploy(MOCK_USDC, "eUSDC");
  await eUSDC.waitForDeployment();
  console.log("eUSDC (wrapper) deployed to:", await eUSDC.getAddress());

  // eUSDT - wraps mUSDT
  const eUSDT = await FHERC20Wrapper.deploy(MOCK_USDT, "eUSDT");
  await eUSDT.waitForDeployment();
  console.log("eUSDT (wrapper) deployed to:", await eUSDT.getAddress());

  // ePYUSD - wraps mPYUSD
  const ePYUSD = await FHERC20Wrapper.deploy(MOCK_PYUSD, "ePYUSD");
  await ePYUSD.waitForDeployment();
  console.log("ePYUSD (wrapper) deployed to:", await ePYUSD.getAddress());

  // Deploy zOrbitalFactory
  const ZOrbitalFactory = await ethers.getContractFactory("zOrbitalFactory");
  const factory = await ZOrbitalFactory.deploy();
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("\nzOrbitalFactory deployed to:", factoryAddress);

  // Create a pool with the wrapped tokens
  const tokens = [
    await eUSDC.getAddress(),
    await eUSDT.getAddress(),
    await ePYUSD.getAddress()
  ];
  const radius = 1000000n; // 1M units radius (uint64)

  console.log("\nCreating zOrbital pool with wrapped tokens:", tokens);
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

  console.log("\n=== Deployment Summary ===");
  console.log("--- Mock Stablecoins (orbital-core) ---");
  console.log("mUSDC:", MOCK_USDC);
  console.log("mUSDT:", MOCK_USDT);
  console.log("mPYUSD:", MOCK_PYUSD);
  console.log("\n--- FHERC20 Wrappers ---");
  console.log("eUSDC:", await eUSDC.getAddress());
  console.log("eUSDT:", await eUSDT.getAddress());
  console.log("ePYUSD:", await ePYUSD.getAddress());
  console.log("\n--- zOrbital ---");
  console.log("Factory:", factoryAddress);
  console.log("Pool:", poolAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
