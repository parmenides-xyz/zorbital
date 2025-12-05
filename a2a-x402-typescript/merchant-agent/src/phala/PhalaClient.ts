//
// PhalaClient - Interface to Phala Network's TEE inference API
//
// Licensed under the Apache License, Version 2.0

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface InferenceRequest {
  model: string;
  messages: ChatMessage[];
  max_tokens?: number;
  temperature?: number;
  stream?: boolean;
}

export interface InferenceResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: {
    index: number;
    message: ChatMessage;
    finish_reason: string;
  }[];
  usage: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

export interface AttestationQuote {
  intel_quote: string;
  app_data: string;
  timestamp: number;
}

export interface VerificationResult {
  valid: boolean;
  tcb_status?: string;
  error?: string;
}

// Phala Network endpoints
const INFERENCE_API = 'https://api.redpill.ai/v1';
const ATTESTATION_VERIFIER = 'https://cloud-api.phala.network/api/v1/attestations/verify';

// Available models in Phala TEE
export const PHALA_MODELS = {
  DEEPSEEK_V3: 'phala/deepseek-chat-v3-0324',
  LLAMA_70B: 'phala/llama-3.3-70b-instruct',
} as const;

// Pricing per 1000 tokens (in USDC atomic units, 6 decimals)
export const MODEL_PRICING: Record<string, { input: bigint; output: bigint }> = {
  [PHALA_MODELS.DEEPSEEK_V3]: {
    input: 140n,      // $0.00014 per 1k input tokens
    output: 280n,     // $0.00028 per 1k output tokens
  },
  [PHALA_MODELS.LLAMA_70B]: {
    input: 350n,      // $0.00035 per 1k input tokens
    output: 400n,     // $0.00040 per 1k output tokens
  },
};

export class PhalaClient {
  private apiKey: string;

  constructor(apiKey?: string) {
    const key = apiKey || process.env.REDPILL_API_KEY;
    if (!key) {
      throw new Error('REDPILL_API_KEY environment variable not set');
    }
    this.apiKey = key;
  }

  /**
   * Estimate cost for an inference request
   * Returns estimated cost in USDC atomic units (6 decimals)
   */
  estimateCost(model: string, estimatedInputTokens: number, maxOutputTokens: number): bigint {
    const pricing = MODEL_PRICING[model] || MODEL_PRICING[PHALA_MODELS.DEEPSEEK_V3];

    const inputCost = (BigInt(estimatedInputTokens) * pricing.input) / 1000n;
    const outputCost = (BigInt(maxOutputTokens) * pricing.output) / 1000n;

    // Add 20% buffer for estimation uncertainty
    const total = inputCost + outputCost;
    const buffer = total / 5n;

    return total + buffer;
  }

  /**
   * Run inference on Phala's TEE infrastructure
   */
  async inference(request: InferenceRequest): Promise<InferenceResponse> {
    console.log(`\nCalling Phala TEE inference...`);
    console.log(`  Model: ${request.model}`);
    console.log(`  Messages: ${request.messages.length}`);

    const response = await fetch(`${INFERENCE_API}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: request.model,
        messages: request.messages,
        max_tokens: request.max_tokens || 1024,
        temperature: request.temperature || 0.7,
        stream: false,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Phala inference failed: ${response.status} - ${error}`);
    }

    const result = await response.json() as InferenceResponse;

    console.log(`  Tokens used: ${result.usage.total_tokens}`);
    console.log(`  Response length: ${result.choices[0]?.message?.content?.length || 0} chars`);

    return result;
  }

  /**
   * Get attestation quote for verification
   */
  async getAttestation(model: string): Promise<AttestationQuote | null> {
    try {
      // Request attestation from the model endpoint
      const response = await fetch(`${INFERENCE_API}/attestation`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({ model }),
      });

      if (!response.ok) {
        console.log('Attestation not available for this request');
        return null;
      }

      return await response.json() as AttestationQuote;
    } catch (error) {
      console.log('Failed to get attestation:', error);
      return null;
    }
  }

  /**
   * Verify a TDX attestation quote via Phala's verification service
   */
  async verifyAttestation(quote: AttestationQuote): Promise<VerificationResult> {
    console.log('\nVerifying TDX attestation...');

    try {
      const response = await fetch(ATTESTATION_VERIFIER, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          hex: quote.intel_quote,
        }),
      });

      if (!response.ok) {
        return {
          valid: false,
          error: `Verification service error: ${response.status}`,
        };
      }

      const result = await response.json() as any;

      console.log(`  TCB Status: ${result.tcb_status || 'unknown'}`);
      console.log(`  Valid: ${result.valid !== false}`);

      return {
        valid: result.valid !== false,
        tcb_status: result.tcb_status,
      };
    } catch (error) {
      return {
        valid: false,
        error: `Verification failed: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }

  /**
   * Get available models
   */
  getAvailableModels(): string[] {
    return Object.values(PHALA_MODELS);
  }

  /**
   * Get pricing info for a model
   */
  getPricing(model: string): { inputPer1k: string; outputPer1k: string } | null {
    const pricing = MODEL_PRICING[model];
    if (!pricing) return null;

    return {
      inputPer1k: `$${(Number(pricing.input) / 1_000_000).toFixed(6)}`,
      outputPer1k: `$${(Number(pricing.output) / 1_000_000).toFixed(6)}`,
    };
  }
}
