# zOrbital

Privacy-preserving, *n*-dimensional AMM + x402 with encrypted swaps using Fully Homomorphic Encryption.

## Table of Contents

- [Problem](#problem)
- [Solution](#solution)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Setup](#setup)
- [Local Development](#local-development)
- [Deployment](#deployment)

## Problem

The 402 HTTP status code “Payment Required” has existed for decades, waiting for a proper micropayment layer to make it real.

Base’s x402 changes that.

Want to read an article? The server responds with “402 Payment Required: $0.50” and you pay directly.

There’s just one problem: every payment is public + USDC-opinionated.

## Solution

zOrbital reimagines Paradigm's [Orbital](https://www.paradigm.xyz/2025/06/orbital) with Fully Homomorphic Encryption (FHE). Swap any stablecoin for USDC in one pool (a feature-rich implementation of Paradigm's design, now with opt-in FHE for confidential swaps), and pay for goods/services both publicly/privately. By leveraging Fhenix's FHE Coprocessor (recently live on Base!), the AMM computes valid swaps over ciphertext without ever decrypting the data.

Key properties:
- **Encrypted reserves**: Pool state is never revealed
- **Private swaps**: Trade amounts computed homomorphically
- **MEV resistant**: Bots cannot extract value from encrypted transactions
- **Dual-mode**: Public swaps available for users who don't need privacy

### Layer 2 Advantages

Deployed on Base Sepolia:
- Low gas costs make FHE operations economically viable
- EVM compatibility with existing tooling! FHE operations work natively on EVM-compatible blockchains.

Access a live deployment on Phala Cloud (verifiable cloud computing for private AI) [here](https://7ab039f3f4336135607bd2fdf50f1bbe9f524c18-3000.dstack-pha-prod7.phala.network/).

## Architecture

```
+------------------+     +-------------------+     +------------------+
|    Frontend      |     |   Smart Contracts |     |  FHE Coprocessor |
|  (Next.js/wagmi) |<--->|   (Base Sepolia)  |<--->|    (Fhenix)      |
+------------------+     +-------------------+     +------------------+
        |                        |
        v                        v
+------------------+     +-------------------+
|   cofhejs SDK    |     |    FHERC20        |
| (client encrypt) |     | (encrypted ERC20) |
+------------------+     +-------------------+
```

### Components

| Directory | Description |
|-----------|-------------|
| `frontend/` | Next.js web app with wallet integration |
| `zorbital-cofhe/` | Private AMM using FHE (zOrbital.sol) |
| `orbital-core/` | Public AMM for non-private swaps |
| `fhenix-confidential-contracts/` | FHERC20 token standard |
| `a2a-x402-typescript/` | Agent-to-agent x402 payments |

### Contract Flow

1. User wraps ERC20 into FHERC20 (encrypted token)
2. Frontend encrypts swap amount using cofhejs
3. zOrbital.swap() computes output homomorphically
4. User receives encrypted FHERC20 balance
5. Optional: unwrap back to public ERC20

## Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | Next.js 15, React 19, TypeScript |
| Wallet | RainbowKit, wagmi, viem |
| Encryption | cofhejs (Fhenix FHE SDK) |
| Contracts | Solidity 0.8.25, Foundry |
| L2 | Base Sepolia |
| Deployment | Docker, Phala Cloud |

## Deployed Contracts

All contracts deployed on Base Sepolia.

### Pools

| Contract | Address |
|----------|---------|
| zOrbital (Private) | `0xa513B34e2375ab5dAF2C03FEB79953A8256b304E` |
| Orbital (Public) | `0xe077aD60fa6487594514B014e5294B542E92a1c7` |
| OrbitalManager | `0xf8753dE4d99a88FbcA0F5403838E01bCa5C11e78` |

### FHERC20 Tokens

| Token | Encrypted | Underlying |
|-------|-----------|------------|
| USDC | `0x0f3521fFe4246fA4285ea989155A7e4607C55f17` | `0x5E364C53fC867b060096bDc48A74401a6ED6b04a` |
| USDT | `0x7943Eee6ABaD45A583E2aBEeA6Eb9CB18b4b6987` | `0xc04669a9c26341F62427b67B813E97426a8670C3` |
| PYUSD | `0x79Ba1D402d4B6f6334A084A2637B38a89F74a7Bc` | `0x073285F3Fe2b388A0cf4c2f0DC9ad13197531Cbf` |

## Setup

### Prerequisites

- Node.js 20+
- Docker (for deployment)
- Foundry (for contracts)

### Install Dependencies

```bash
# Frontend
cd frontend
npm install

# Contracts
cd ../orbital-core
forge install

cd ../zorbital-cofhe
npm install
```

### Environment Variables

Create `frontend/.env.local`:

```
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=your_project_id
```

## Local Development

### Run Frontend

```bash
cd frontend
npm run dev
```

Open http://localhost:3000

### Compile Contracts

```bash
# Public AMM
cd orbital-core
forge build

# Private AMM
cd ../zorbital-cofhe
npx hardhat compile
```

### Run Tests

```bash
cd orbital-core
forge test

cd ../fhenix-confidential-contracts
npx hardhat test
```

## Deployment

### Docker Build

```bash
cd frontend
docker build --platform linux/amd64 -t yourusername/zorbital:latest .
docker push yourusername/zorbital:latest
```

### Phala Cloud

1. Push image to Docker Hub
2. Upload `docker-compose.yml` to Phala dashboard
3. Set port 3000
4. Deploy

### Contract Deployment

Contracts are deployed to Base Sepolia. Addresses configured in:

```
frontend/src/contracts/deployedContracts.ts
```
