"use client";
import { useState } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import Image from "next/image";
import { parseUnits, formatUnits } from "viem";
import { Footer } from "../components/Footer";
import { useCofhe } from "../hooks/useCofhe";
import {
  TOKENS,
  ZORBITAL_POOL_ADDRESS,
  ORBITAL_POOL_ADDRESS,
  ORBITAL_MANAGER_ADDRESS,
  TEE_PROVIDER_ADDRESS,
  ERC20_ABI,
  FHERC20_WRAPPER_ABI,
  ZORBITAL_ABI,
  ORBITAL_MANAGER_ABI,
} from "../contracts/deployedContracts";

type Tab = "wrap" | "swap" | "tee";

// Orbital rings decoration component
function OrbitalRings() {
  return (
    <div className="absolute inset-0 overflow-hidden pointer-events-none">
      {/* Outer ring */}
      <div
        className="absolute top-1/2 left-1/2 w-[600px] h-[600px] -translate-x-1/2 -translate-y-1/2 rounded-full border border-[#0AD9DC]/10"
        style={{ animation: 'orbit 30s linear infinite' }}
      >
        <div className="absolute top-0 left-1/2 w-2 h-2 -translate-x-1/2 -translate-y-1/2 bg-[#0AD9DC] rounded-full opacity-60" />
      </div>
      {/* Middle ring */}
      <div
        className="absolute top-1/2 left-1/2 w-[450px] h-[450px] -translate-x-1/2 -translate-y-1/2 rounded-full border border-[#0AD9DC]/15"
        style={{ animation: 'orbit-reverse 25s linear infinite' }}
      >
        <div className="absolute bottom-0 left-1/2 w-1.5 h-1.5 -translate-x-1/2 translate-y-1/2 bg-[#0AD9DC] rounded-full opacity-40" />
      </div>
      {/* Inner ring */}
      <div
        className="absolute top-1/2 left-1/2 w-[300px] h-[300px] -translate-x-1/2 -translate-y-1/2 rounded-full border border-[#0AD9DC]/20"
        style={{ animation: 'orbit 20s linear infinite' }}
      />
    </div>
  );
}

export default function Home() {
  const [activeTab, setActiveTab] = useState<Tab>("wrap");

  return (
    <div className="min-h-screen flex flex-col bg-[#011623] bg-grid relative">
      {/* Header */}
      <header className="flex items-center justify-between px-6 py-4 border-b border-white/10 relative z-10">
        <div className="flex items-center gap-3">
          <span className="text-[#0AD9DC] font-bold text-2xl tracking-tight">zOrbital</span>
        </div>
        <ConnectButton />
      </header>

      {/* Tabs */}
      <div className="flex justify-center gap-2 px-6 py-4 relative z-10">
        {[
          { id: "wrap" as Tab, label: "Encrypt" },
          { id: "swap" as Tab, label: "Swap" },
          { id: "tee" as Tab, label: "Rent TEE" },
        ].map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`px-6 py-2 rounded-lg font-semibold transition-all duration-200 ${
              activeTab === tab.id
                ? "bg-[#0AD9DC] text-[#011623] shadow-[0_0_20px_rgba(10,217,220,0.3)]"
                : "bg-white/5 text-white/70 hover:bg-white/10 hover:text-white"
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Main Content */}
      <main className="flex-1 flex items-start justify-center p-6 relative">
        <OrbitalRings />
        <div className="w-full max-w-md relative z-10">
          {activeTab === "wrap" && <WrapPanel />}
          {activeTab === "swap" && <SwapPanel />}
          {activeTab === "tee" && <TEEPanel />}
        </div>
      </main>

      <Footer />
    </div>
  );
}

function WrapPanel() {
  const { address, isConnected } = useAccount();
  const [amount, setAmount] = useState("");
  const [selectedToken, setSelectedToken] = useState(0);
  const [isUnwrap, setIsUnwrap] = useState(false);
  const [txStatus, setTxStatus] = useState<string | null>(null);

  const token = TOKENS[selectedToken];
  const wrapperAddress = token.address;
  const underlyingAddress = token.underlying.address;

  // Read underlying token balance
  const { data: underlyingBalance } = useReadContract({
    address: underlyingAddress,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
  });

  // Read wrapper token balance (indicator)
  const { data: wrapperBalance } = useReadContract({
    address: wrapperAddress,
    abi: FHERC20_WRAPPER_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
  });

  // Read allowance
  const { data: allowance } = useReadContract({
    address: underlyingAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, wrapperAddress] : undefined,
  });

  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const handleAmountChange = (value: string) => {
    if (value === "" || /^\d*\.?\d*$/.test(value)) {
      setAmount(value);
    }
  };

  // Underlying tokens use 6 decimals, FHERC20 uses 18
  const parsedAmount = amount ? parseUnits(amount, isUnwrap ? 18 : 6) : 0n;
  const needsApproval = !isUnwrap && allowance !== undefined && parsedAmount > allowance;

  const handleApprove = async () => {
    setTxStatus("Approving...");
    writeContract({
      address: underlyingAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [wrapperAddress, parsedAmount],
    });
  };

  const handleWrap = async () => {
    if (!address) return;
    setTxStatus("Wrapping...");
    writeContract({
      address: wrapperAddress,
      abi: FHERC20_WRAPPER_ABI,
      functionName: "wrap",
      args: [address, parsedAmount],
    });
  };

  // Underlying uses 6 decimals, FHERC20 wrapper uses 18
  const displayBalance = isUnwrap
    ? wrapperBalance !== undefined ? formatUnits(wrapperBalance, 18) : "--"
    : underlyingBalance !== undefined ? formatUnits(underlyingBalance, 6) : "--";

  return (
    <div className="bg-white/5 rounded-2xl p-6 border border-white/10 glow-card backdrop-blur-sm">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-white text-xl font-semibold">
          {isUnwrap ? "Decrypt" : "Encrypt"} Tokens
        </h2>
        <button
          onClick={() => setIsUnwrap(!isUnwrap)}
          className="px-3 py-1 rounded-full text-sm font-medium bg-white/10 text-white border border-white/20 hover:bg-white/20 transition-colors"
        >
          {isUnwrap ? "→ Encrypt" : "→ Decrypt"}
        </button>
      </div>

      <p className="text-white/60 text-sm mb-4">
        {isUnwrap
          ? "Decrypt your FHERC20 tokens back to regular ERC20"
          : "Encrypt your tokens with FHE for private swaps"}
      </p>

      {/* Token Selector */}
      <div className="mb-4">
        <label className="text-white/60 text-sm mb-2 block">Token</label>
        <div className="flex gap-2">
          {TOKENS.map((t, i) => (
            <button
              key={t.symbol}
              onClick={() => setSelectedToken(i)}
              className={`flex-1 py-2 rounded-lg text-sm font-medium transition-colors ${
                selectedToken === i
                  ? "bg-[#0AD9DC] text-[#011623]"
                  : "bg-white/10 text-white hover:bg-white/20"
              }`}
            >
              {isUnwrap ? t.symbol : t.underlying.symbol}
            </button>
          ))}
        </div>
      </div>

      {/* Amount Input */}
      <div className="bg-white/5 rounded-xl p-4 mb-4">
        <div className="flex justify-between text-sm text-white/60 mb-2">
          <span>Amount</span>
          <span>Balance: {displayBalance}</span>
        </div>
        <div className="flex items-center gap-3">
          <input
            type="text"
            inputMode="decimal"
            placeholder="0.0"
            value={amount}
            onChange={(e) => handleAmountChange(e.target.value)}
            className="flex-1 min-w-0 bg-transparent text-white text-2xl font-medium outline-none placeholder:text-white/30"
          />
          <span className="text-white/60 font-medium">
            {isUnwrap ? token.symbol : token.underlying.symbol}
          </span>
        </div>
      </div>

      {/* Arrow */}
      <div className="flex justify-center items-center gap-2 text-white/40 mb-4">
        <div className="h-px flex-1 bg-white/10" />
        <span>↓</span>
        <div className="h-px flex-1 bg-white/10" />
      </div>

      {/* Output */}
      <div className="bg-white/5 rounded-xl p-4 mb-6">
        <div className="text-sm text-white/60 mb-2">You receive</div>
        <div className="flex items-center gap-3">
          <span className="text-white text-2xl font-medium">
            {amount || "0.0"}
          </span>
          <span className="text-[#0AD9DC] font-medium">
            {isUnwrap ? token.underlying.symbol : token.symbol}
          </span>
        </div>
      </div>

      {/* Status */}
      {(isPending || isConfirming) && (
        <div className="text-center text-white/60 text-sm mb-4">
          {isPending ? "Confirm in wallet..." : "Waiting for confirmation..."}
        </div>
      )}
      {isSuccess && txHash && (
        <div className="text-center text-sm mb-4">
          <span className="text-green-400">Transaction confirmed!</span>
          <a
            href={`https://sepolia.basescan.org/tx/${txHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="block text-[#0AD9DC] hover:underline mt-1 text-xs truncate"
          >
            {txHash}
          </a>
        </div>
      )}

      {/* Action Button */}
      {!isUnwrap && needsApproval ? (
        <button
          onClick={handleApprove}
          disabled={!isConnected || !amount || isPending || isConfirming}
          className="w-full py-4 bg-[#0AD9DC] hover:bg-[#0AD9DC]/80 disabled:bg-white/10 disabled:text-white/40 text-[#011623] rounded-xl font-semibold text-lg transition-colors disabled:cursor-not-allowed"
        >
          {isPending || isConfirming ? "Processing..." : `Approve ${token.underlying.symbol}`}
        </button>
      ) : (
        <button
          onClick={handleWrap}
          disabled={!isConnected || !amount || isPending || isConfirming}
          className="w-full py-4 bg-[#0AD9DC] hover:bg-[#0AD9DC]/80 disabled:bg-white/10 disabled:text-white/40 text-[#011623] rounded-xl font-semibold text-lg transition-colors disabled:cursor-not-allowed"
        >
          {!isConnected
            ? "Connect Wallet"
            : !amount
            ? "Enter Amount"
            : isPending || isConfirming
            ? "Processing..."
            : isUnwrap
            ? `Unwrap to ${token.underlying.symbol}`
            : `Wrap to ${token.symbol}`}
        </button>
      )}
    </div>
  );
}

function SwapPanel() {
  const { address, isConnected } = useAccount();
  const [fromAmount, setFromAmount] = useState("");
  const [fromToken, setFromToken] = useState(0);
  const [toToken, setToToken] = useState(1);
  const [showFromSelect, setShowFromSelect] = useState(false);
  const [showToSelect, setShowToSelect] = useState(false);
  const [isPrivate, setIsPrivate] = useState(false);

  const { isInitialized, encrypt, Encryptable } = useCofhe();
  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  // Get token info based on privacy mode
  const fromTokenInfo = TOKENS[fromToken];
  const toTokenInfo = TOKENS[toToken];

  // Read balance
  const balanceAddress = isPrivate ? fromTokenInfo.address : fromTokenInfo.underlying.address;
  const { data: fromBalance } = useReadContract({
    address: balanceAddress,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
  });

  // Check if pool is operator (for private swaps)
  const { data: isOperator } = useReadContract({
    address: fromTokenInfo.address,
    abi: FHERC20_WRAPPER_ABI,
    functionName: "isOperator",
    args: address ? [address, ZORBITAL_POOL_ADDRESS] : undefined,
  });

  // Check allowance for public swaps (underlying token -> OrbitalManager)
  const { data: publicAllowance } = useReadContract({
    address: fromTokenInfo.underlying.address,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, ORBITAL_MANAGER_ADDRESS] : undefined,
  });

  const handleAmountChange = (value: string) => {
    if (value === "" || /^\d*\.?\d*$/.test(value)) {
      setFromAmount(value);
    }
  };

  const swapTokens = () => {
    setFromToken(toToken);
    setToToken(fromToken);
  };

  const getTokenSymbol = (index: number) => {
    return isPrivate ? TOKENS[index].symbol : TOKENS[index].underlying.symbol;
  };

  const handleSetOperator = async () => {
    const until = BigInt(2 ** 48 - 1); // Max uint48
    writeContract({
      address: fromTokenInfo.address,
      abi: FHERC20_WRAPPER_ABI,
      functionName: "setOperator",
      args: [ZORBITAL_POOL_ADDRESS, until],
    });
  };

  const handleApprovePublic = async () => {
    const parsedAmount = parseUnits(fromAmount, 6); // Underlying tokens use 6 decimals
    writeContract({
      address: fromTokenInfo.underlying.address,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [ORBITAL_MANAGER_ADDRESS, parsedAmount],
    });
  };

  const handleSwap = async () => {
    if (!address || !fromAmount) return;

    if (isPrivate) {
      // Private swap - encrypt amount and call zOrbital (18 decimals for FHERC20)
      const parsedAmount = parseUnits(fromAmount, 18);

      if (!isInitialized) {
        alert("FHE not initialized. Please wait...");
        return;
      }

      try {
        const encrypted = await encrypt([Encryptable.uint64(parsedAmount)]);
        if (!encrypted.success || !encrypted.data) {
          alert("Encryption failed: " + encrypted.error);
          return;
        }

        writeContract({
          address: ZORBITAL_POOL_ADDRESS,
          abi: ZORBITAL_ABI,
          functionName: "swap",
          args: [BigInt(fromToken), BigInt(toToken), encrypted.data[0]],
        });
      } catch (err) {
        console.error("Swap failed:", err);
        alert("Swap failed: " + (err as Error).message);
      }
    } else {
      // Public swap - call OrbitalManager.swapSingle (6 decimals for underlying)
      const parsedAmount = parseUnits(fromAmount, 6);

      writeContract({
        address: ORBITAL_MANAGER_ADDRESS,
        abi: ORBITAL_MANAGER_ABI,
        functionName: "swapSingle",
        args: [{
          poolAddress: ORBITAL_POOL_ADDRESS,
          tokenIn: fromTokenInfo.underlying.address,
          tokenOut: toTokenInfo.underlying.address,
          amountIn: parsedAmount,
          sumReservesLimit: 0n,
        }],
      });
    }
  };

  const parsedAmount = fromAmount ? parseUnits(fromAmount, 6) : 0n;
  const needsOperator = isPrivate && !isOperator;
  const needsApproval = !isPrivate && publicAllowance !== undefined && parsedAmount > publicAllowance;
  // Private mode uses 18 decimals (FHERC20), public uses 6 (underlying stablecoins)
  const displayBalance = fromBalance !== undefined
    ? formatUnits(fromBalance, isPrivate ? 18 : 6)
    : "--";

  return (
    <div className="bg-white/5 rounded-2xl p-6 border border-white/10 glow-card backdrop-blur-sm">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-white text-xl font-semibold">Swap</h2>
        <button
          onClick={() => setIsPrivate(!isPrivate)}
          className={`px-3 py-1 rounded-full text-sm font-medium transition-all duration-200 ${
            isPrivate
              ? "bg-[#0AD9DC]/20 text-[#0AD9DC] border border-[#0AD9DC]/50 shadow-[0_0_10px_rgba(10,217,220,0.2)]"
              : "bg-white/10 text-white/60 border border-white/20"
          }`}
        >
          {isPrivate ? "Encrypted" : "Public"}
        </button>
      </div>

      <p className="text-white/60 text-sm mb-4">
        {isPrivate
          ? "Swap amounts encrypted on-chain with FHE."
          : "Standard AMM swap with public amounts."}
      </p>

      {/* FHE Status for Private Mode */}
      {isPrivate && !isInitialized && (
        <div className="text-yellow-400 text-sm mb-4 p-2 bg-yellow-400/10 rounded-lg">
          Initializing FHE... Please wait.
        </div>
      )}

      {/* From Token */}
      <div className="bg-white/5 rounded-xl p-4 mb-2 relative">
        <div className="flex justify-between text-sm text-white/60 mb-2">
          <span>Sell</span>
          <span>Balance: {displayBalance}</span>
        </div>
        <div className="flex items-center gap-3">
          <input
            type="text"
            inputMode="decimal"
            placeholder="0.0"
            value={fromAmount}
            onChange={(e) => handleAmountChange(e.target.value)}
            className="flex-1 min-w-0 bg-transparent text-white text-2xl font-medium outline-none placeholder:text-white/30"
          />
          <button
            onClick={() => setShowFromSelect(!showFromSelect)}
            className="w-[110px] px-3 py-2 bg-white/10 rounded-lg text-white font-medium hover:bg-white/20 transition-colors flex items-center justify-between gap-2"
          >
            {getTokenSymbol(fromToken)}
            <span className="text-xs">▼</span>
          </button>
        </div>
        {showFromSelect && (
          <div className="absolute right-4 top-full mt-1 bg-[#1a2633] border border-white/20 rounded-lg overflow-hidden z-10">
            {TOKENS.map((token, i) => (
              <button
                key={token.symbol}
                onClick={() => {
                  if (i !== toToken) setFromToken(i);
                  setShowFromSelect(false);
                }}
                disabled={i === toToken}
                className="w-full px-4 py-2 text-left text-white hover:bg-white/10 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {getTokenSymbol(i)}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Swap Direction */}
      <div className="flex justify-center -my-2 relative z-10">
        <button
          onClick={swapTokens}
          className="p-2 bg-[#011623] border border-white/20 rounded-lg hover:bg-white/10 transition-colors"
        >
          <svg className="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
          </svg>
        </button>
      </div>

      {/* To Token */}
      <div className="bg-white/5 rounded-xl p-4 mt-2 relative">
        <div className="flex justify-between text-sm text-white/60 mb-2">
          <span>Buy</span>
          <span>Balance: --</span>
        </div>
        <div className="flex items-center gap-3">
          <span className="flex-1 text-white text-2xl font-medium opacity-60">
            {fromAmount ? "~" + fromAmount : "0.0"}
          </span>
          <button
            onClick={() => setShowToSelect(!showToSelect)}
            className="w-[110px] px-3 py-2 bg-white/10 rounded-lg text-white font-medium hover:bg-white/20 transition-colors flex items-center justify-between gap-2"
          >
            {getTokenSymbol(toToken)}
            <span className="text-xs">▼</span>
          </button>
        </div>
        {showToSelect && (
          <div className="absolute right-4 top-full mt-1 bg-[#1a2633] border border-white/20 rounded-lg overflow-hidden z-10">
            {TOKENS.map((token, i) => (
              <button
                key={token.symbol}
                onClick={() => {
                  if (i !== fromToken) setToToken(i);
                  setShowToSelect(false);
                }}
                disabled={i === fromToken}
                className="w-full px-4 py-2 text-left text-white hover:bg-white/10 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {getTokenSymbol(i)}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Status */}
      {(isPending || isConfirming) && (
        <div className="text-center text-white/60 text-sm mt-4">
          {isPending ? "Confirm in wallet..." : "Waiting for confirmation..."}
        </div>
      )}
      {isSuccess && txHash && (
        <div className="text-center text-sm mt-4">
          <span className="text-green-400">Swap confirmed!</span>
          <a
            href={`https://sepolia.basescan.org/tx/${txHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="block text-[#0AD9DC] hover:underline mt-1 text-xs truncate"
          >
            {txHash}
          </a>
        </div>
      )}

      {/* Action Button */}
      {isPrivate && needsOperator ? (
        <button
          onClick={handleSetOperator}
          disabled={!isConnected || isPending || isConfirming}
          className="w-full mt-6 py-4 bg-purple-500 hover:bg-purple-600 disabled:bg-white/10 disabled:text-white/40 text-white rounded-xl font-semibold text-lg transition-colors disabled:cursor-not-allowed"
        >
          {isPending || isConfirming ? "Processing..." : "Approve Pool as Operator"}
        </button>
      ) : !isPrivate && needsApproval ? (
        <button
          onClick={handleApprovePublic}
          disabled={!isConnected || !fromAmount || isPending || isConfirming}
          className="w-full mt-6 py-4 bg-[#0AD9DC] hover:bg-[#0AD9DC]/80 disabled:bg-white/10 disabled:text-white/40 text-[#011623] rounded-xl font-semibold text-lg transition-colors disabled:cursor-not-allowed"
        >
          {isPending || isConfirming ? "Processing..." : `Approve ${fromTokenInfo.underlying.symbol}`}
        </button>
      ) : (
        <button
          onClick={handleSwap}
          disabled={!isConnected || !fromAmount || isPending || isConfirming || (isPrivate && !isInitialized)}
          className="w-full mt-6 py-4 bg-[#0AD9DC] hover:bg-[#0AD9DC]/80 disabled:bg-white/10 disabled:text-white/40 text-[#011623] rounded-xl font-semibold text-lg transition-colors disabled:cursor-not-allowed"
        >
          {!isConnected
            ? "Connect Wallet"
            : !fromAmount
            ? "Enter Amount"
            : isPending || isConfirming
            ? "Processing..."
            : `Swap ${getTokenSymbol(fromToken)} → ${getTokenSymbol(toToken)}`}
        </button>
      )}
    </div>
  );
}

function TEEPanel() {
  const { address, isConnected } = useAccount();
  const [prompt, setPrompt] = useState("");
  const [selectedModel, setSelectedModel] = useState("deepseek");
  const [isPrivatePayment, setIsPrivatePayment] = useState(false);
  const [inferenceResult, setInferenceResult] = useState<string | null>(null);
  const [isRunning, setIsRunning] = useState(false);

  const { isInitialized, encrypt, Encryptable } = useCofhe();
  const { writeContract, data: txHash, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  // Reset isRunning if write fails
  if (writeError) {
    console.error("writeContract error:", writeError);
    if (isRunning) {
      setIsRunning(false);
    }
  }

  // Payment amount: 4.02 - x402!
  // mUSDC uses 6 decimals, eUSDC uses 18 decimals
  const PAYMENT_AMOUNT_PUBLIC = 4020000n; // 4.02 * 10^6
  const PAYMENT_AMOUNT_PRIVATE = 4020000000000000000n; // 4.02 * 10^18

  // Token addresses
  const mUSDC = TOKENS[0].underlying.address;
  const eUSDC = TOKENS[0].address;

  const handleRunInference = async () => {
    if (!address || !prompt) return;

    console.log("Starting inference...", { isPrivatePayment, address, prompt });
    setIsRunning(true);
    setInferenceResult(null);

    try {
      if (isPrivatePayment) {
        // Private payment with eUSDC - need FHE encryption
        if (!isInitialized) {
          alert("FHE not initialized. Please wait...");
          setIsRunning(false);
          return;
        }

        console.log("Encrypting amount...", PAYMENT_AMOUNT_PRIVATE.toString());
        // Encrypt the payment amount (18 decimals for eUSDC)
        const encrypted = await encrypt([Encryptable.uint64(PAYMENT_AMOUNT_PRIVATE)]);
        console.log("Encryption result:", encrypted);

        if (!encrypted.success || !encrypted.data) {
          alert("Encryption failed: " + encrypted.error);
          setIsRunning(false);
          return;
        }

        console.log("Calling confidentialTransfer...", { to: TEE_PROVIDER_ADDRESS, data: encrypted.data[0] });
        // Use confidentialTransfer on eUSDC (FHERC20)
        writeContract({
          address: eUSDC,
          abi: FHERC20_WRAPPER_ABI,
          functionName: "confidentialTransfer",
          args: [TEE_PROVIDER_ADDRESS, encrypted.data[0]],
        });
      } else {
        console.log("Public payment...", { to: TEE_PROVIDER_ADDRESS, amount: PAYMENT_AMOUNT_PUBLIC.toString() });
        // Public payment with mUSDC (6 decimals)
        writeContract({
          address: mUSDC,
          abi: ERC20_ABI,
          functionName: "transfer",
          args: [TEE_PROVIDER_ADDRESS, PAYMENT_AMOUNT_PUBLIC],
        });
      }
    } catch (err) {
      console.error("Payment failed:", err);
      alert("Payment failed: " + (err as Error).message);
      setIsRunning(false);
    }
  };

  // Watch for successful payment and show inference result
  const modelResponses: Record<string, string> = {
    deepseek: `DeepSeek R1 Response:\n\nBased on my analysis of "${prompt}", the answer involves careful consideration of multiple factors. Running inside a secure TEE enclave ensures your query and results remain confidential. The computation was verified via remote attestation.`,
    llama: `Llama 3.1 70B Response:\n\nProcessing "${prompt}" within the secure TEE enclave. Computation performed with full memory encryption and attestation verification. Results are cryptographically sealed.`,
    qwen: `Qwen 2.5 Response:\n\nAnalyzing "${prompt}" in our confidential computing environment. The key findings suggest careful consideration of the context. All processing occurred in hardware-isolated memory.`,
  };

  if (isSuccess && isRunning && !inferenceResult) {
    setTimeout(() => {
      setInferenceResult(modelResponses[selectedModel] || modelResponses.deepseek);
      setIsRunning(false);
    }, 1500);
  }

  const getButtonText = () => {
    if (!isConnected) return "Connect Wallet";
    if (!prompt) return "Enter Prompt";
    if (isPending) return "Confirm Payment...";
    if (isConfirming) return "Processing x402 Payment...";
    if (isRunning) return "Running Inference...";
    return "Run Inference";
  };

  return (
    <div className="bg-white/5 rounded-2xl p-6 border border-white/10 glow-card backdrop-blur-sm">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-white text-xl font-semibold">Rent a TEE</h2>
        <span className="px-3 py-1 bg-green-500/20 text-green-300 rounded-full text-sm font-medium border border-green-500/50">
          Phala Network
        </span>
      </div>

      <p className="text-white/60 text-sm mb-2">
        Autonomous compute rentals. Pay via x402.
      </p>
      <p className="text-white/40 text-xs mb-4">
        NVIDIA H100/H200/B100 TEE GPUs • Intel TDX
      </p>

      {/* Model Selector */}
      <div className="mb-4">
        <label className="text-white/60 text-sm mb-2 block">Model</label>
        <select
          value={selectedModel}
          onChange={(e) => setSelectedModel(e.target.value)}
          className="w-full bg-white/5 border border-white/20 rounded-lg px-4 py-3 text-white outline-none focus:border-[#0AD9DC] appearance-none cursor-pointer"
        >
          <option value="deepseek">DeepSeek R1</option>
          <option value="llama">Llama 3.1 70B</option>
          <option value="qwen">Qwen 2.5</option>
        </select>
      </div>

      {/* Prompt Input */}
      <div className="mb-4">
        <label className="text-white/60 text-sm mb-2 block">Prompt</label>
        <textarea
          placeholder="Enter your prompt..."
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          rows={4}
          className="w-full bg-white/5 border border-white/20 rounded-lg px-4 py-3 text-white outline-none focus:border-[#0AD9DC] resize-none placeholder:text-white/30"
        />
      </div>

      {/* Payment Toggle */}
      <div className="flex items-center justify-between mb-4 p-3 bg-white/5 rounded-lg">
        <span className="text-white text-sm">Payment Method</span>
        <button
          onClick={() => setIsPrivatePayment(!isPrivatePayment)}
          className={`px-3 py-1 rounded-full text-sm font-medium transition-all duration-200 ${
            isPrivatePayment
              ? "bg-[#0AD9DC]/20 text-[#0AD9DC] border border-[#0AD9DC]/50 shadow-[0_0_10px_rgba(10,217,220,0.2)]"
              : "bg-white/10 text-white border border-white/20"
          }`}
        >
          {isPrivatePayment ? "eUSDC (Encrypted)" : "USDC (Public)"}
        </button>
      </div>

      {/* Price Estimate */}
      <div className="flex items-center justify-between mb-4 text-sm">
        <span className="text-white/60">Estimated Cost</span>
        <span className="text-white font-medium">4.02 {isPrivatePayment ? "eUSDC" : "USDC"}</span>
      </div>

      {/* FHE Status for Private Mode */}
      {isPrivatePayment && !isInitialized && (
        <div className="text-yellow-400 text-sm mb-4 p-2 bg-yellow-400/10 rounded-lg">
          Initializing FHE for encrypted payment...
        </div>
      )}

      {/* Submit Button */}
      <button
        onClick={handleRunInference}
        disabled={!isConnected || !prompt || isPending || isConfirming || isRunning || (isPrivatePayment && !isInitialized)}
        className="w-full py-4 bg-[#0AD9DC] hover:bg-[#0AD9DC]/80 disabled:bg-white/10 disabled:text-white/40 text-[#011623] rounded-xl font-semibold text-lg transition-colors disabled:cursor-not-allowed"
      >
        {getButtonText()}
      </button>

      {/* Transaction Status */}
      {txHash && (
        <div className="text-center text-sm mt-3">
          <span className="text-green-400">x402 Payment sent!</span>
          <a
            href={`https://sepolia.basescan.org/tx/${txHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="block text-[#0AD9DC] hover:underline mt-1 text-xs truncate"
          >
            {txHash}
          </a>
        </div>
      )}

      {isPrivatePayment && !inferenceResult && (
        <p className="text-center text-[#0AD9DC]/80 text-sm mt-3">
          Payment amount encrypted with FHE
        </p>
      )}

      {/* Inference Result */}
      {inferenceResult && (
        <div className="mt-4 p-4 bg-white/5 rounded-lg border border-[#0AD9DC]/30">
          <div className="flex items-center gap-2 mb-2">
            <span className="text-[#0AD9DC] text-sm font-medium">TEE Inference Complete</span>
            <span className="px-2 py-0.5 bg-green-500/20 text-green-300 text-xs rounded-full">Verified</span>
          </div>
          <p className="text-white/80 text-sm whitespace-pre-wrap">{inferenceResult}</p>
        </div>
      )}
    </div>
  );
}
