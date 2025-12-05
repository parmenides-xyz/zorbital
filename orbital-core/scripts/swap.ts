import { castSend } from './util/common';
import { poolAddress, managerAddress, tokens, tokenNames } from './util/constants';

async function main() {
    const tokenInIndex = parseInt(process.argv[2] || '0');
    const tokenOutIndex = parseInt(process.argv[3] || '1');
    const amount = process.argv[4] || '1000000'; // 1 token with 6 decimals

    if (tokenInIndex === tokenOutIndex) {
        console.error('tokenIn and tokenOut must be different');
        process.exit(1);
    }

    const tokenIn = tokens[tokenInIndex];
    const tokenOut = tokens[tokenOutIndex];

    // SwapSingleParams: (address poolAddress, address tokenIn, address tokenOut, uint256 amountIn, uint128 sumReservesLimit)
    const params = `(${poolAddress},${tokenIn},${tokenOut},${amount},0)`;

    console.log(`Swapping ${tokenNames[tokenInIndex]} -> ${tokenNames[tokenOutIndex]}...`);
    console.log(`  Amount: ${amount}`);

    const result = castSend(
        managerAddress,
        'swapSingle((address,address,address,uint256,uint128))',
        [`"${params}"`]
    );
    console.log(result);
    console.log('Swap complete!');
}

main().catch(console.error);
