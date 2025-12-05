// Contract addresses on Base Sepolia

// TEE Provider address for x402 payments (demo - using a valid checksummed address)
export const TEE_PROVIDER_ADDRESS = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" as const;

// zOrbital (Private/Encrypted pool)
export const ZORBITAL_POOL_ADDRESS = "0xa513B34e2375ab5dAF2C03FEB79953A8256b304E" as const;

// Orbital (Public pool)
export const ORBITAL_POOL_ADDRESS = "0xe077aD60fa6487594514B014e5294B542E92a1c7" as const;
export const ORBITAL_MANAGER_ADDRESS = "0xf8753dE4d99a88FbcA0F5403838E01bCa5C11e78" as const;

// FHERC20 Wrapper tokens
export const TOKENS = [
  {
    symbol: "eUSDC",
    name: "Encrypted USDC",
    address: "0x0f3521fFe4246fA4285ea989155A7e4607C55f17" as const,
    underlying: {
      symbol: "mUSDC",
      name: "Mock USDC",
      address: "0x5E364C53fC867b060096bDc48A74401a6ED6b04a" as const,
    }
  },
  {
    symbol: "eUSDT",
    name: "Encrypted USDT",
    address: "0x7943Eee6ABaD45A583E2aBEeA6Eb9CB18b4b6987" as const,
    underlying: {
      symbol: "mUSDT",
      name: "Mock USDT",
      address: "0xc04669a9c26341F62427b67B813E97426a8670C3" as const,
    }
  },
  {
    symbol: "ePYUSD",
    name: "Encrypted PYUSD",
    address: "0x79Ba1D402d4B6f6334A084A2637B38a89F74a7Bc" as const,
    underlying: {
      symbol: "mPYUSD",
      name: "Mock PYUSD",
      address: "0x073285F3Fe2b388A0cf4c2f0DC9ad13197531Cbf" as const,
    }
  },
] as const;

// ERC20 ABI (for approve, balanceOf, transfer)
export const ERC20_ABI = [
  {
    inputs: [{ name: "owner", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "transfer",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

// FHERC20Wrapper ABI (for wrap/unwrap/transfer)
export const FHERC20_WRAPPER_ABI = [
  {
    inputs: [
      { name: "to", type: "address" },
      { name: "value", type: "uint64" },
    ],
    name: "wrap",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "operator", type: "address" },
      { name: "until", type: "uint48" },
    ],
    name: "setOperator",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "operator", type: "address" },
    ],
    name: "isOperator",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "owner", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "owner", type: "address" }],
    name: "confidentialBalanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "to", type: "address" },
      {
        components: [
          { name: "ctHash", type: "uint256" },
          { name: "securityZone", type: "uint8" },
          { name: "utype", type: "uint8" },
          { name: "signature", type: "bytes" },
        ],
        name: "inValue",
        type: "tuple",
      },
    ],
    name: "confidentialTransfer",
    outputs: [{ name: "transferred", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

// zOrbital Pool ABI (for private swap)
export const ZORBITAL_ABI = [
  {
    inputs: [
      { name: "tokenInIndex", type: "uint256" },
      { name: "tokenOutIndex", type: "uint256" },
      {
        components: [
          { name: "ctHash", type: "uint256" },
          { name: "securityZone", type: "uint8" },
          { name: "utype", type: "uint8" },
          { name: "signature", type: "bytes" },
        ],
        name: "sellAmountIn",
        type: "tuple",
      },
    ],
    name: "swap",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "getTokenCount",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "index", type: "uint256" }],
    name: "getToken",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

// OrbitalManager ABI (for public swap)
export const ORBITAL_MANAGER_ABI = [
  {
    inputs: [
      {
        components: [
          { name: "poolAddress", type: "address" },
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "sumReservesLimit", type: "uint128" },
        ],
        name: "params",
        type: "tuple",
      },
    ],
    name: "swapSingle",
    outputs: [{ name: "amountOut", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;
