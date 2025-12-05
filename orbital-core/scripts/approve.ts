import { castSend } from './util/common';
import { tokens, tokenNames, managerAddress } from './util/constants';

async function main() {
    const tokenIndex = process.argv[2] ? parseInt(process.argv[2]) : -1;
    const amount = process.argv[3] || '1000000000000'; // 1M with 6 decimals

    if (tokenIndex >= 0 && tokenIndex < tokens.length) {
        // Approve single token
        console.log(`Approving ${tokenNames[tokenIndex]} for manager...`);
        const result = castSend(tokens[tokenIndex], 'approve(address,uint256)', [managerAddress, amount]);
        console.log(result);
    } else {
        // Approve all tokens
        console.log('Approving all tokens for manager...');
        for (let i = 0; i < tokens.length; i++) {
            console.log(`\n${tokenNames[i]}:`);
            const result = castSend(tokens[i], 'approve(address,uint256)', [managerAddress, amount]);
            console.log(result);
        }
    }
    console.log('\nApprovals complete!');
}

main().catch(console.error);
