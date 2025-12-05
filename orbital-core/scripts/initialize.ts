import { castSend } from './util/common';
import { poolAddress } from './util/constants';

async function main() {
    const initialSumReserves = process.argv[2] || '1000000000000'; // 1M with 6 decimals
    const tick = process.argv[3] || '0';

    console.log(`Initializing pool at ${poolAddress}...`);
    console.log(`  initialSumReserves: ${initialSumReserves}`);
    console.log(`  tick: ${tick}`);

    const result = castSend(poolAddress, 'initialize(uint128,int24)', [initialSumReserves, tick]);
    console.log(result);
    console.log('Pool initialized!');
}

main().catch(console.error);
