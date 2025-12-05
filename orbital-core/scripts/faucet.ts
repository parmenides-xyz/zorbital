import { castSend } from './util/common';
import { tokens, tokenNames } from './util/constants';

async function main() {
    const tokenIndex = process.argv[2] ? parseInt(process.argv[2]) : -1;

    if (tokenIndex >= 0 && tokenIndex < tokens.length) {
        // Faucet single token
        console.log(`Calling faucet for ${tokenNames[tokenIndex]}...`);
        const result = castSend(tokens[tokenIndex], 'faucet()');
        console.log(result);
        console.log(`Got 10,000 ${tokenNames[tokenIndex]}!`);
    } else {
        // Faucet all tokens
        console.log('Calling faucet for all tokens...');
        for (let i = 0; i < tokens.length; i++) {
            console.log(`\n${tokenNames[i]}:`);
            const result = castSend(tokens[i], 'faucet()');
            console.log(result);
        }
        console.log('\nGot 10,000 of each token!');
    }
}

main().catch(console.error);
