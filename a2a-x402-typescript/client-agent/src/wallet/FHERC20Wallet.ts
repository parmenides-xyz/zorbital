//
// FHERC20Wallet - Private x402 payments using FHE-encrypted tokens
//
// Licensed under the Apache License, Version 2.0

import { ethers } from 'ethers';
import { cofhejs, Encryptable, FheTypes } from 'cofhejs/node';
import { logger } from '../logger';
import {
  PaymentPayload,
  x402PaymentRequiredResponse,
} from 'a2a-x402';
import { Wallet } from './Wallet';

// FHERC20 ABI - minimal interface for private payments
const FHERC20_ABI = [
  // Operator management
  'function setOperator(address operator, uint48 until) returns (bool)',
  'function isOperator(address owner, address operator) view returns (bool)',

  // Confidential transfers
  'function confidentialTransfer(address to, (bytes32 hash, uint256 securityZone, bytes signature) encryptedAmount) returns (bool)',
  'function confidentialTransferFrom(address from, address to, (bytes32 hash, uint256 securityZone, bytes signature) encryptedAmount) returns (bool)',

  // Balance queries
  'function balanceOf(address account) view returns (uint256)',
  'function confidentialBalanceOf(address account) view returns ((bytes32 hash, uint256 securityZone, bytes signature))',

  // Wrapper functions (for FHERC20Wrapper)
  'function wrap(address to, uint64 value) returns (bool)',
  'function unwrap(address to, (bytes32 hash, uint256 securityZone, bytes signature) encryptedAmount) returns (bool)',

  // Standard ERC20 for underlying token interactions
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
];

// Payment payload for FHE confidential scheme
export interface FHEPaymentPayload {
  encryptedAmount: any; // cofhejs encrypted value
  from: string;
  to: string;
  validAfter: number;
  validBefore: number;
  nonce: string;
}

export class FHERC20Wallet extends Wallet {
  private wallet: ethers.Wallet;
  private provider: ethers.JsonRpcProvider;
  private cofheInitialized: boolean = false;

  constructor(privateKey?: string, rpcUrl?: string) {
    super();

    const key = privateKey || process.env.WALLET_PRIVATE_KEY;
    if (!key) {
      throw new Error('WALLET_PRIVATE_KEY environment variable not set and no privateKey provided');
    }

    const url = rpcUrl ||
                process.env.BASE_SEPOLIA_RPC_URL ||
                'https://sepolia.base.org';

    this.provider = new ethers.JsonRpcProvider(url);
    this.wallet = new ethers.Wallet(key, this.provider);

    logger.log(`FHERC20Wallet initialized: ${this.wallet.address}`);
  }

  /**
   * Initialize cofhejs for FHE operations
   */
  private async initCofhe(): Promise<void> {
    if (this.cofheInitialized) return;

    logger.log('Initializing cofhejs...');

    const result = await cofhejs.initializeWithEthers({
      ethersProvider: this.provider,
      ethersSigner: this.wallet,
      environment: 'TESTNET'
    });

    if (!result.success) {
      throw new Error(`Failed to initialize cofhejs: ${result.error}`);
    }

    this.cofheInitialized = true;
    logger.log('cofhejs initialized');
  }

  /**
   * Ensure the merchant/facilitator is set as operator for the FHERC20 token
   */
  async ensureOperator(
    tokenAddress: string,
    operatorAddress: string
  ): Promise<boolean> {
    try {
      const fherc20 = new ethers.Contract(
        tokenAddress,
        FHERC20_ABI,
        this.wallet
      );

      // Check if already operator
      const isOperator = await fherc20.isOperator(
        this.wallet.address,
        operatorAddress
      );

      logger.log(`Is ${operatorAddress} operator? ${isOperator}`);

      if (isOperator) {
        logger.log('Operator already set');
        return true;
      }

      // Set operator with max duration (uint48 max)
      const until = 2n ** 48n - 1n;

      logger.log(`Setting ${operatorAddress} as operator...`);

      const tx = await fherc20.setOperator(operatorAddress, until, {
        gasLimit: 150000,
      });

      logger.log(`Operator transaction sent: ${tx.hash}`);

      const receipt = await tx.wait();

      if (receipt && receipt.status === 1) {
        logger.log(`Operator set successfully! TX: ${tx.hash}`);
        return true;
      } else {
        logger.error(`Operator transaction failed. TX: ${tx.hash}`);
        return false;
      }

    } catch (error) {
      logger.error('Error setting operator:', error);
      return false;
    }
  }

  /**
   * Get encrypted balance for display (unsealed)
   */
  async getEncryptedBalance(tokenAddress: string): Promise<string> {
    try {
      await this.initCofhe();

      const fherc20 = new ethers.Contract(
        tokenAddress,
        FHERC20_ABI,
        this.wallet
      );

      const encBalance = await fherc20.confidentialBalanceOf(this.wallet.address);

      const result = await cofhejs.unseal(encBalance, FheTypes.Uint64);

      if (result.data !== null) {
        return result.data.toString();
      }

      return '(unable to unseal)';
    } catch (error) {
      logger.error('Error getting encrypted balance:', error);
      return '(error)';
    }
  }

  /**
   * Signs a payment requirement using FHE encryption
   * Returns an encrypted payment payload instead of EIP-3009 signature
   */
  async signPayment(requirements: x402PaymentRequiredResponse): Promise<PaymentPayload> {
    await this.initCofhe();

    const paymentOption = requirements.accepts[0];
    const tokenAddress = paymentOption.asset;
    const merchantAddress = paymentOption.payTo;
    const amountRequired = BigInt(paymentOption.maxAmountRequired);

    logger.log(`\nPrivate payment requested:`);
    logger.log(`   Amount: ${amountRequired.toString()} (will be encrypted)`);
    logger.log(`   To: ${merchantAddress}`);
    logger.log(`   Token: ${tokenAddress}`);

    // Ensure operator is set for the merchant/facilitator
    const operatorSet = await this.ensureOperator(tokenAddress, merchantAddress);
    if (!operatorSet) {
      throw new Error('Failed to set operator. Private payment cannot proceed.');
    }

    logger.log('Operator confirmed, encrypting payment amount...');

    // Encrypt the payment amount using cofhejs
    const encrypted = await cofhejs.encrypt([Encryptable.uint64(amountRequired)]);

    if (!encrypted.success || encrypted.data === null) {
      throw new Error(`Failed to encrypt amount: ${encrypted.error}`);
    }

    logger.log('Amount encrypted successfully');

    // Generate timestamps and nonce
    const now = Math.floor(Date.now() / 1000);
    const nonce = '0x' + Array.from(
      crypto.getRandomValues(new Uint8Array(32)),
      b => b.toString(16).padStart(2, '0')
    ).join('');

    // Create the FHE payment payload
    const fhePayload: FHEPaymentPayload = {
      encryptedAmount: encrypted.data[0],
      from: this.wallet.address,
      to: merchantAddress,
      validAfter: 0,
      validBefore: now + (paymentOption.maxTimeoutSeconds || 3600),
      nonce: nonce,
    };

    // Sign a commitment to the payment (for verification)
    const commitment = ethers.solidityPackedKeccak256(
      ['address', 'address', 'uint256', 'uint256', 'bytes32'],
      [fhePayload.from, fhePayload.to, fhePayload.validAfter, fhePayload.validBefore, nonce]
    );

    const signature = await this.wallet.signMessage(ethers.getBytes(commitment));

    logger.log('Payment commitment signed');

    return {
      x402Version: 1,
      scheme: 'fhe.confidential', // New scheme for FHE payments
      network: paymentOption.network,
      payload: {
        ...fhePayload,
        commitment,
        signature,
      },
    };
  }

  /**
   * Execute the actual confidential transfer
   * This performs the on-chain FHERC20 transfer with encrypted amount
   */
  async executePayment(
    tokenAddress: string,
    merchantAddress: string,
    encryptedAmount: any
  ): Promise<{ success: boolean; txHash?: string; error?: string }> {
    try {
      await this.initCofhe();

      const fherc20 = new ethers.Contract(
        tokenAddress,
        FHERC20_ABI,
        this.wallet
      );

      logger.log(`\nExecuting private payment transfer...`);
      logger.log(`   From: ${this.wallet.address}`);
      logger.log(`   To: ${merchantAddress}`);
      logger.log(`   Amount: [ENCRYPTED]`);

      // Check indicator balance (not actual balance, just activity indicator)
      const indicatorBalance = await fherc20.balanceOf(this.wallet.address);
      logger.log(`Indicator balance: ${indicatorBalance.toString()}`);

      // Execute the confidential transfer
      const tx = await fherc20.confidentialTransfer(merchantAddress, encryptedAmount, {
        gasLimit: 300000,
      });

      logger.log(`Transfer transaction sent: ${tx.hash}`);
      logger.log('Waiting for confirmation...');

      const receipt = await tx.wait();

      if (receipt && receipt.status === 1) {
        logger.log(`Private transfer successful! TX: ${tx.hash}`);
        logger.log(`Payment completed (amount hidden on-chain)`);
        return { success: true, txHash: tx.hash };
      } else {
        logger.error(`Transfer transaction failed. TX: ${tx.hash}`);
        return { success: false, txHash: tx.hash, error: 'Transaction failed' };
      }

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('Error during private transfer:', errorMessage);
      return { success: false, error: errorMessage };
    }
  }

  /**
   * Get the wallet address
   */
  getAddress(): string {
    return this.wallet.address;
  }

  /**
   * Get the underlying ethers wallet (for advanced use)
   */
  getEthersWallet(): ethers.Wallet {
    return this.wallet;
  }
}
