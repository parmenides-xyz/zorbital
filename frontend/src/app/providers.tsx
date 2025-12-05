"use client";
import { ReactNode } from "react";
import { baseSepolia } from "wagmi/chains";
import { createConfig, WagmiProvider, http } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RainbowKitProvider, getDefaultConfig, darkTheme } from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";

const queryClient = new QueryClient();

export const wagmiConfig = getDefaultConfig({
  appName: "fheniswap",
  projectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || "demo",
  chains: [baseSepolia],
  ssr: true,
});

export function Providers({ children }: { children: ReactNode }) {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={darkTheme({
            accentColor: "#0AD9DC",
            accentColorForeground: "#011623",
            borderRadius: "medium",
          })}
        >
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
