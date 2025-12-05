//
// FHERC20 Facilitator Client - Handles fhe.confidential scheme payments
//
// Licensed under the Apache License, Version 2.0

import { ethers } from 'ethers';
import {
  FacilitatorClient,
  PaymentPayload,
  PaymentRequirements,
  VerifyResponse,
  SettleResponse,
} from 'a2a-x402';

// FHERC20 ABI for confidential transfers
const FHERC20_ABI = [
  'function confidentialTransferFrom(address from, address to, (bytes32 hash, uint256 securityZone, bytes signature) encryptedAmount) returns (bool)',
  'function isOperator(address owner, address operator) view returns (bool)',
  'function balanceOf(address account) view returns (uint256)',
];

export interface FHERC20FacilitatorConfig {
  privateKey: string;
  rpcUrl?: string;
}

export class FHERC20FacilitatorClient implements FacilitatorClient {
  private wallet: ethers.Wallet;
  private provider: ethers.JsonRpcProvider;

  constructor(config: FHERC20FacilitatorConfig) {
    const url = config.rpcUrl ||
                process.env.BASE_SEPOLIA_RPC_URL ||
                'https://sepolia.base.org';

    this.provider = new ethers.JsonRpcProvider(url);
    this.wallet = new ethers.Wallet(config.privateKey, this.provider);

    console.log(`FHERC20 Facilitator initialized: ${this.wallet.address}`);
  }

  /**
   * Verify the FHE payment payload
   * Checks: signature validity, operator status, timestamp validity
   */
  async verify(
    payload: PaymentPayload,
    requirements: PaymentRequirements
  ): Promise<VerifyResponse> {
    console.log('--- FHERC20 FACILITATOR: VERIFY ---');

    try {
      // Check scheme
      if (payload.scheme !== 'fhe.confidential') {
        return {
          isValid: false,
          invalidReason: `Invalid scheme: expected fhe.confidential, got ${payload.scheme}`,
        };
      }

      const fhePayload = payload.payload as any;

      // Verify timestamp validity
      const now = Math.floor(Date.now() / 1000);
      if (now < fhePayload.validAfter) {
        return {
          isValid: false,
          invalidReason: 'Payment not yet valid (validAfter not reached)',
        };
      }
      if (now > fhePayload.validBefore) {
        return {
          isValid: false,
          invalidReason: 'Payment expired (validBefore passed)',
        };
      }

      // Verify the commitment signature
      const commitment = ethers.solidityPackedKeccak256(
        ['address', 'address', 'uint256', 'uint256', 'bytes32'],
        [fhePayload.from, fhePayload.to, fhePayload.validAfter, fhePayload.validBefore, fhePayload.nonce]
      );

      const recoveredAddress = ethers.verifyMessage(
        ethers.getBytes(commitment),
        fhePayload.signature
      );

      if (recoveredAddress.toLowerCase() !== fhePayload.from.toLowerCase()) {
        return {
          isValid: false,
          invalidReason: `Signature verification failed: expected ${fhePayload.from}, got ${recoveredAddress}`,
        };
      }

      // Check that merchant is operator for the payer's tokens
      const fherc20 = new ethers.Contract(
        requirements.asset,
        FHERC20_ABI,
        this.provider
      );

      const isOperator = await fherc20.isOperator(fhePayload.from, requirements.payTo);
      if (!isOperator) {
        return {
          isValid: false,
          invalidReason: `Merchant is not operator for payer's ${requirements.asset}`,
        };
      }

      console.log('Payment verified successfully');
      console.log(`  Payer: ${fhePayload.from}`);
      console.log(`  Merchant: ${fhePayload.to}`);
      console.log(`  Amount: [ENCRYPTED]`);

      return {
        isValid: true,
        payer: fhePayload.from,
      };

    } catch (error) {
      console.error('Verification error:', error);
      return {
        isValid: false,
        invalidReason: `Verification error: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }

  /**
   * Settle the FHE payment by executing confidentialTransferFrom
   */
  async settle(
    payload: PaymentPayload,
    requirements: PaymentRequirements
  ): Promise<SettleResponse> {
    console.log('--- FHERC20 FACILITATOR: SETTLE ---');

    try {
      const fhePayload = payload.payload as any;

      const fherc20 = new ethers.Contract(
        requirements.asset,
        FHERC20_ABI,
        this.wallet
      );

      console.log('Executing confidential transfer...');
      console.log(`  From: ${fhePayload.from}`);
      console.log(`  To: ${requirements.payTo}`);
      console.log(`  Amount: [ENCRYPTED]`);

      // Execute the confidential transfer
      const tx = await fherc20.confidentialTransferFrom(
        fhePayload.from,
        requirements.payTo,
        fhePayload.encryptedAmount,
        { gasLimit: 500000 }
      );

      console.log(`Transaction sent: ${tx.hash}`);

      const receipt = await tx.wait();

      if (receipt && receipt.status === 1) {
        console.log(`Settlement successful! TX: ${tx.hash}`);
        return {
          success: true,
          transaction: tx.hash,
          network: requirements.network,
          payer: fhePayload.from,
        };
      } else {
        console.error(`Settlement transaction failed: ${tx.hash}`);
        return {
          success: false,
          transaction: tx.hash,
          network: requirements.network,
          errorReason: 'Transaction reverted',
        };
      }

    } catch (error) {
      console.error('Settlement error:', error);
      return {
        success: false,
        network: requirements.network,
        errorReason: `Settlement error: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }
}
