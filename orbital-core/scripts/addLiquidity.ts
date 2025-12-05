import { castSend } from './util/common';
import { poolAddress, managerAddress } from './util/constants';

async function main() {
    const amount = process.argv[2] || '100000000'; // 100 tokens with 6 decimals
    const tick = process.argv[3] || '100'; // boundary tick

    // MintParams struct: (address poolAddress, int24 tick, uint256[] amountsDesired, uint256[] amountsMin)
    const amountsDesired = `[${amount},${amount},${amount}]`;
    const amountsMin = '[0,0,0]';
    const params = `(${poolAddress},${tick},${amountsDesired},${amountsMin})`;

    console.log('Adding liquidity via manager...');
    console.log(`  Pool: ${poolAddress}`);
    console.log(`  Amount per token: ${amount}`);
    console.log(`  Tick: ${tick}`);

    const result = castSend(
        managerAddress,
        'mint((address,int24,uint256[],uint256[]))',
        [`"${params}"`]
    );
    console.log(result);
    console.log('Liquidity added!');
}

main().catch(console.error);
