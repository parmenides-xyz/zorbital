//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Merchant Server Executor - Production-ready x402 payment executor
 * Supports both public (exact) and private (fhe.confidential) payment schemes
 */

import {
  x402ServerExecutor,
  AgentExecutor,
  PaymentPayload,
  PaymentRequirements,
  VerifyResponse,
  SettleResponse,
  x402ExtensionConfig,
  verifyPayment,
  settlePayment,
  DefaultFacilitatorClient,
  FacilitatorClient,
} from 'a2a-x402';

import { FHERC20FacilitatorClient } from '../facilitator/FHERC20FacilitatorClient';

export class MerchantServerExecutor extends x402ServerExecutor {
  private facilitator?: FacilitatorClient;
  private fherc20Facilitator?: FHERC20FacilitatorClient;

  constructor(
    delegate: AgentExecutor,
    config?: Partial<x402ExtensionConfig>,
    facilitator?: FacilitatorClient
  ) {
    super(delegate, config);

    // Allow custom facilitator injection, otherwise uses library's default
    this.facilitator = facilitator;

    // Initialize FHERC20 facilitator if private key is available
    if (process.env.MERCHANT_PRIVATE_KEY) {
      this.fherc20Facilitator = new FHERC20FacilitatorClient({
        privateKey: process.env.MERCHANT_PRIVATE_KEY,
      });
      console.log('FHERC20 facilitator initialized for private payments');
    }

    if (facilitator) {
      console.log('Using custom facilitator client');
    } else {
      console.log('Using default facilitator (https://x402.org/facilitator)');
    }
  }

  async verifyPayment(
    payload: PaymentPayload,
    requirements: PaymentRequirements
  ): Promise<VerifyResponse> {
    const isPrivate = payload.scheme === 'fhe.confidential';

    console.log('\n=== VERIFYING PAYMENT ===');
    console.log(`Scheme: ${payload.scheme} (${isPrivate ? 'PRIVATE' : 'PUBLIC'})`);
    console.log(`Network: ${requirements.network}`);
    console.log(`Asset: ${requirements.asset}`);
    console.log(`Amount: ${isPrivate ? '[ENCRYPTED]' : requirements.maxAmountRequired}`);
    console.log(`Pay To: ${requirements.payTo}`);

    let response: VerifyResponse;

    if (isPrivate && this.fherc20Facilitator) {
      // Use FHERC20 facilitator for private payments
      response = await this.fherc20Facilitator.verify(payload, requirements);
    } else {
      // Use default facilitator for public payments
      response = await verifyPayment(payload, requirements, this.facilitator);
    }

    if (response.isValid) {
      console.log('Payment Verified Successfully!');
      console.log(`   Payer: ${response.payer}`);
    } else {
      console.log('Payment Verification Failed!');
      console.log(`   Reason: ${response.invalidReason}`);
    }

    return response;
  }

  async settlePayment(
    payload: PaymentPayload,
    requirements: PaymentRequirements
  ): Promise<SettleResponse> {
    const isPrivate = payload.scheme === 'fhe.confidential';

    console.log('\n=== SETTLING PAYMENT ===');
    console.log(`Scheme: ${payload.scheme} (${isPrivate ? 'PRIVATE' : 'PUBLIC'})`);
    console.log(`Network: ${requirements.network}`);
    console.log(`Asset: ${requirements.asset}`);
    console.log(`Amount: ${isPrivate ? '[ENCRYPTED]' : requirements.maxAmountRequired}`);

    let response: SettleResponse;

    if (isPrivate && this.fherc20Facilitator) {
      // Use FHERC20 facilitator for private payments
      response = await this.fherc20Facilitator.settle(payload, requirements);
    } else {
      // Use default facilitator for public payments
      response = await settlePayment(payload, requirements, this.facilitator);
    }

    if (response.success) {
      console.log('Payment Settled Successfully!');
      console.log(`   Transaction: ${response.transaction}`);
      console.log(`   Network: ${response.network}`);
      console.log(`   Payer: ${response.payer}`);
    } else {
      console.log('Payment Settlement Failed!');
      console.log(`   Reason: ${response.errorReason}`);
    }

    return response;
  }
}
