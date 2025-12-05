import { task } from 'hardhat/config';
import { cofhejs, Encryptable, FheTypes } from 'cofhejs/node';
import { poolAddress, tokens, tokenNames } from './util/constants';
import { initialiseCofheJs } from './util/common';

task('get-pool-info', 'get zOrbital pool information').setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    const pool = (await hre.ethers.getContractAt('zOrbital', poolAddress)).connect(signer);

    const tokenCount = await pool.getTokenCount();
    const factory = await pool.factory();

    console.log('\n-- zOrbital Pool Info --');
    console.log('Pool address  :', poolAddress);
    console.log('Factory       :', factory);
    console.log('Token count   :', tokenCount.toString());
    console.log('');

    for (let i = 0; i < tokenCount; i++) {
        const tokenAddr = await pool.getToken(i);
        console.log(`Token ${i}: ${tokenNames[i]} (${tokenAddr})`);
    }
});

task('add-liquidity', 'add liquidity to zOrbital pool')
.addParam('amount', 'amount of each token to add')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    await initialiseCofheJs(signer);

    const pool = (await hre.ethers.getContractAt('zOrbital', poolAddress)).connect(signer);
    const amount = BigInt(taskArgs.amount);

    console.log(`\nAdding ${amount} of each token as liquidity...`);

    // Encrypt amounts for each token (using uint64 for FHERC20)
    const encAmounts = [];
    for (let i = 0; i < tokens.length; i++) {
        const encrypted = await cofhejs.encrypt([Encryptable.uint64(amount)]);
        if (!encrypted.success || encrypted.data === null) {
            console.error('Encryption failed:', encrypted.error);
            return;
        }
        encAmounts.push(encrypted.data[0]);
    }

    const tx = await pool.addLiquidity(encAmounts);
    await tx.wait();

    console.log('Liquidity added successfully!');
    console.log('Transaction hash:', tx.hash);
});

task('swap', 'swap tokens on zOrbital pool')
.addParam('tokenin', 'index of token to sell (0=eUSDC, 1=eUSDT, 2=ePYUSD)')
.addParam('tokenout', 'index of token to buy (0=eUSDC, 1=eUSDT, 2=ePYUSD)')
.addParam('amount', 'amount to swap')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    await initialiseCofheJs(signer);

    const pool = (await hre.ethers.getContractAt('zOrbital', poolAddress)).connect(signer);

    const tokenInIndex = parseInt(taskArgs.tokenin);
    const tokenOutIndex = parseInt(taskArgs.tokenout);
    const amount = BigInt(taskArgs.amount);

    console.log(`\nSwapping ${amount} ${tokenNames[tokenInIndex]} -> ${tokenNames[tokenOutIndex]}...`);

    // Encrypt the swap amount (using uint64 for FHERC20)
    const encrypted = await cofhejs.encrypt([Encryptable.uint64(amount)]);
    if (!encrypted.success || encrypted.data === null) {
        console.error('Encryption failed:', encrypted.error);
        return;
    }

    const tx = await pool.swap(tokenInIndex, tokenOutIndex, encrypted.data[0]);
    await tx.wait();

    console.log('Swap executed successfully!');
    console.log('Transaction hash:', tx.hash);
});
