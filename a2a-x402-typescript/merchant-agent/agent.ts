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
 * x402 TEE Proxy Agent - Private payments for private compute
 *
 * This agent provides access to Phala Network's TEE infrastructure
 * with x402 payment integration. Supports both public (USDC) and
 * private (eUSDC/FHERC20) payments.
 */

import { LlmAgent as Agent } from 'adk-typescript/agents';
import {
  x402PaymentRequiredException,
  PaymentRequirements,
} from 'a2a-x402';
import { PhalaClient, PHALA_MODELS, MODEL_PRICING } from './src/phala/PhalaClient';

// --- Configuration ---

if (!process.env.MERCHANT_WALLET_ADDRESS) {
  console.error('ERROR: MERCHANT_WALLET_ADDRESS is not set in .env file');
  throw new Error('Missing required environment variable: MERCHANT_WALLET_ADDRESS');
}

const WALLET_ADDRESS: string = process.env.MERCHANT_WALLET_ADDRESS;
const NETWORK = process.env.PAYMENT_NETWORK || 'base-sepolia';

// Token addresses - merchant accepts BOTH, client chooses at payment time
const USDC_CONTRACT = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const eUSDC_CONTRACT = '0x0f3521fFe4246fA4285ea989155A7e4607C55f17';

console.log(`TEE Proxy Agent Configuration:
  Wallet: ${WALLET_ADDRESS}
  Network: ${NETWORK}
  Accepts: USDC (public) or eUSDC (private) - client chooses
`);

// Initialize Phala client (lazy)
let phalaClient: PhalaClient | null = null;

function getPhalaClient(): PhalaClient {
  if (!phalaClient) {
    phalaClient = new PhalaClient();
  }
  return phalaClient;
}

// --- Tool Functions ---

/**
 * Request TEE inference - triggers x402 payment flow
 */
async function requestInference(
  params: Record<string, any>,
  context?: any
): Promise<void> {
  const model = params.model || params.modelId || PHALA_MODELS.DEEPSEEK_V3;
  const prompt = params.prompt || params.message || params.text || '';
  const maxTokens = params.max_tokens || params.maxTokens || 512;

  console.log(`\nTEE Inference Request:`);
  console.log(`  Model: ${model}`);
  console.log(`  Prompt: "${prompt.substring(0, 50)}..."`);
  console.log(`  Max tokens: ${maxTokens}`);

  if (!prompt || typeof prompt !== 'string' || prompt.trim() === '') {
    throw new Error('Prompt cannot be empty');
  }

  // Estimate input tokens (rough: 4 chars per token)
  const estimatedInputTokens = Math.ceil(prompt.length / 4);

  // Calculate cost
  const client = getPhalaClient();
  const estimatedCost = client.estimateCost(model, estimatedInputTokens, maxTokens);
  const costUSDC = (Number(estimatedCost) / 1_000_000).toFixed(6);

  console.log(`  Estimated input tokens: ${estimatedInputTokens}`);
  console.log(`  Estimated cost: ${costUSDC} USDC`);

  // Create payment requirements - default to USDC, client can override with eUSDC
  const requirements: PaymentRequirements = {
    scheme: 'exact' as any,
    network: NETWORK as any,
    asset: USDC_CONTRACT,
    payTo: WALLET_ADDRESS,
    maxAmountRequired: estimatedCost.toString(),
    description: `TEE inference: ${model}`,
    resource: `tee://phala/${model}`,
    mimeType: 'application/json',
    maxTimeoutSeconds: 300,
    extra: {
      name: 'USDC',
      version: '2',
      model,
      prompt,
      maxTokens,
      estimatedTokens: estimatedInputTokens + maxTokens,
      // Advertise that private payments are also accepted
      supportsPrivatePayment: true,
      privateAsset: eUSDC_CONTRACT,
      privateScheme: 'fhe.confidential',
    },
  };

  console.log(`  Requesting payment: ${costUSDC} USDC (or eUSDC for private)`);

  throw new x402PaymentRequiredException(
    `Payment of ${costUSDC} USDC required for TEE inference`,
    requirements
  );
}

/**
 * Execute inference after payment (called internally after payment verification)
 */
async function executeInference(
  params: Record<string, any>,
  context?: any
): Promise<{
  response: string;
  model: string;
  tokens: { prompt: number; completion: number; total: number };
  attestation?: { verified: boolean; tcb_status?: string };
}> {
  const model = params.model || PHALA_MODELS.DEEPSEEK_V3;
  const prompt = params.prompt || '';
  const maxTokens = params.max_tokens || params.maxTokens || 512;

  console.log(`\nExecuting paid TEE inference...`);
  console.log(`  Model: ${model}`);

  const client = getPhalaClient();

  const result = await client.inference({
    model,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: maxTokens,
  });

  const responseText = result.choices[0]?.message?.content || '';

  // Try to get attestation
  let attestation: { verified: boolean; tcb_status?: string } | undefined;
  try {
    const quote = await client.getAttestation(model);
    if (quote) {
      const verification = await client.verifyAttestation(quote);
      attestation = {
        verified: verification.valid,
        tcb_status: verification.tcb_status,
      };
      console.log(`  Attestation: ${verification.valid ? 'VERIFIED' : 'FAILED'}`);
    }
  } catch (e) {
    console.log('  Attestation not available');
  }

  console.log(`  Response length: ${responseText.length} chars`);
  console.log(`  Tokens: ${result.usage.total_tokens}`);

  return {
    response: responseText,
    model: result.model,
    tokens: {
      prompt: result.usage.prompt_tokens,
      completion: result.usage.completion_tokens,
      total: result.usage.total_tokens,
    },
    attestation,
  };
}

/**
 * List available models and pricing
 */
async function listModels(
  params: Record<string, any>,
  context?: any
): Promise<{
  models: Array<{
    id: string;
    pricing: { inputPer1k: string; outputPer1k: string };
  }>;
}> {
  const client = getPhalaClient();
  const models = client.getAvailableModels();

  return {
    models: models.map(id => ({
      id,
      pricing: client.getPricing(id) || { inputPer1k: 'unknown', outputPer1k: 'unknown' },
    })),
  };
}

/**
 * Get a price estimate for a request
 */
async function estimatePrice(
  params: Record<string, any>,
  context?: any
): Promise<{
  model: string;
  estimatedInputTokens: number;
  maxOutputTokens: number;
  estimatedCost: string;
  note: string;
}> {
  const model = params.model || PHALA_MODELS.DEEPSEEK_V3;
  const prompt = params.prompt || '';
  const maxTokens = params.max_tokens || params.maxTokens || 512;

  const estimatedInputTokens = Math.ceil(prompt.length / 4);

  const client = getPhalaClient();
  const cost = client.estimateCost(model, estimatedInputTokens, maxTokens);

  return {
    model,
    estimatedInputTokens,
    maxOutputTokens: maxTokens,
    estimatedCost: (Number(cost) / 1_000_000).toFixed(6),
    note: 'Pay with USDC (public) or eUSDC (private - amount hidden on-chain)',
  };
}

// --- Agent Definition ---

export const merchantAgent = new Agent({
  name: 'x402_merchant_agent',
  model: 'gemini-2.0-flash',
  description: 'A TEE proxy agent providing private compute access via Phala Network with x402 payments.',
  instruction: `You are a TEE (Trusted Execution Environment) proxy agent powered by Phala Network.

**What you provide:**
- Access to LLM inference running in secure TEE hardware (Intel TDX + NVIDIA H100/H200)
- Cryptographic attestation proving code runs in genuine TEE
- Privacy for both payments AND compute

**Available models:**
- phala/deepseek-chat-v3-0324 (DeepSeek V3 - great for reasoning)
- phala/llama-3.3-70b-instruct (Llama 3.3 70B - great for general tasks)

**Payment:** USDC (public) or eUSDC (private - client chooses)

**How to use:**
1. User asks for inference or to run a prompt
2. Use requestInference with their prompt and model choice
3. x402 payment flow triggers automatically
4. After payment, inference runs in TEE
5. Response includes attestation proof

**When users ask about pricing:**
Use estimatePrice to show them the cost before they commit.

**When users ask what models are available:**
Use listModels to show available models and their pricing.

**Why this matters:**
- TEE ensures prompts and responses are encrypted in hardware
- Private payments (eUSDC) hide how much compute you buy
- Attestation proves it ran in a real TEE

**Example interactions:**

User: "What models do you have?"
You: [Use listModels] "I have DeepSeek V3 and Llama 3.3 70B running in TEE..."

User: "How much to ask a question?"
You: [Use estimatePrice] "For a short prompt, approximately..."

User: "Run this: Explain quantum computing"
You: [Use requestInference] -> Payment required -> After payment: "Here's the response..."`,

  tools: [
    requestInference,
    executeInference,
    listModels,
    estimatePrice,
  ],
});

// Export as root agent for ADK
export const rootAgent = merchantAgent;
