import { execSync } from 'child_process';
import * as dotenv from 'dotenv';

dotenv.config();

const RPC_URL = process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org';
const ACCOUNT = 'deployer';

export function castCall(to: string, sig: string, args: string[] = []): string {
    const argsStr = args.join(' ');
    const cmd = `cast call ${to} "${sig}" ${argsStr} --rpc-url ${RPC_URL}`;
    return execSync(cmd, { encoding: 'utf8' }).trim();
}

export function castSend(to: string, sig: string, args: string[] = []): string {
    const argsStr = args.join(' ');
    const cmd = `cast send ${to} "${sig}" ${argsStr} --rpc-url ${RPC_URL} --account ${ACCOUNT}`;
    console.log(`Executing: ${cmd}`);
    return execSync(cmd, { encoding: 'utf8' }).trim();
}

export function formatUnits(value: bigint, decimals: number): string {
    const divisor = 10n ** BigInt(decimals);
    const intPart = value / divisor;
    const fracPart = value % divisor;
    return `${intPart}.${fracPart.toString().padStart(decimals, '0')}`;
}

export function parseUnits(value: string, decimals: number): bigint {
    const [intPart, fracPart = ''] = value.split('.');
    const paddedFrac = fracPart.padEnd(decimals, '0').slice(0, decimals);
    return BigInt(intPart + paddedFrac);
}
