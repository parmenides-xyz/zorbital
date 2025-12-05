// Deployed contract addresses on Base Sepolia
export const factoryAddress = '0x7EBcAb7a59d4191EBd7ea52bB387Fb595aC125fF';
export const poolAddress = '0xa513B34e2375ab5dAF2C03FEB79953A8256b304E';

// FHERC20 Wrapper tokens (sorted by address for pool order)
export const eUSDC = '0x0f3521fFe4246fA4285ea989155A7e4607C55f17';
export const eUSDT = '0x7943Eee6ABaD45A583E2aBEeA6Eb9CB18b4b6987';
export const ePYUSD = '0x79Ba1D402d4B6f6334A084A2637B38a89F74a7Bc';

// Pool token order (sorted by address)
export const tokens = [eUSDC, eUSDT, ePYUSD];
export const tokenNames = ['eUSDC', 'eUSDT', 'ePYUSD'];

// Underlying mock stablecoins (from orbital-core)
export const mUSDC = '0x5E364C53fC867b060096bDc48A74401a6ED6b04a';
export const mUSDT = '0xc04669a9c26341F62427b67B813E97426a8670C3';
export const mPYUSD = '0x073285F3Fe2b388A0cf4c2f0DC9ad13197531Cbf';

// Map wrapper -> underlying for wrapping operations
export const underlyingTokens = [mUSDC, mUSDT, mPYUSD];
export const underlyingNames = ['mUSDC', 'mUSDT', 'mPYUSD'];
