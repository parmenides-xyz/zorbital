import { castCall, formatUnits } from './util/common';
import { tokens, tokenNames, poolAddress } from './util/constants';

async function main() {
    const address = process.argv[2];

    if (!address) {
        console.log('Usage: npx ts-node scripts/balances.ts <address>');
        console.log('Example: npx ts-node scripts/balances.ts 0x28c9f69f39a08f59a782bF6dc413D4536c05Be84');
        process.exit(1);
    }

    console.log(`\nBalances for ${address}:\n`);

    for (let i = 0; i < tokens.length; i++) {
        const balance = castCall(tokens[i], 'balanceOf(address)(uint256)', [address]);
        const formatted = formatUnits(BigInt(balance), 6);
        console.log(`${tokenNames[i]}: ${formatted}`);
    }

    console.log(`\n--- Pool balances (${poolAddress}) ---\n`);

    for (let i = 0; i < tokens.length; i++) {
        const balance = castCall(tokens[i], 'balanceOf(address)(uint256)', [poolAddress]);
        const formatted = formatUnits(BigInt(balance), 6);
        console.log(`${tokenNames[i]}: ${formatted}`);
    }
}

main().catch(console.error);
