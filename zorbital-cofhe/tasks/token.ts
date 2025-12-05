import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { tokens, tokenNames, underlyingTokens, underlyingNames, poolAddress } from './util/constants';
import { Encryptable, FheTypes, cofhejs } from 'cofhejs/node';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { initialiseCofheJs } from './util/common';

task('get-token-balances', 'get user token balances').setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    await initialiseCofheJs(signer);

    console.log(`\nBalances for ${signer.address}:\n`);

    for (let i = 0; i < tokens.length; i++) {
        // Get underlying mToken balance
        const mToken = await hre.ethers.getContractAt('IERC20', underlyingTokens[i]);
        const underlyingBalance = await mToken.balanceOf(signer.address);

        // Get FHERC20 wrapper balances
        const eToken = await hre.ethers.getContractAt('FHERC20Wrapper', tokens[i]);
        const indicatorBalance = await eToken.balanceOf(signer.address);
        const encBalance = await eToken.confidentialBalanceOf(signer.address);

        let decryptedBalance = '(unable to unseal)';
        try {
            const result = await cofhejs.unseal(encBalance, FheTypes.Uint64);
            if (result.data !== null) {
                decryptedBalance = result.data.toString();
            }
        } catch (e) {}

        console.log(`${tokenNames[i]} / ${underlyingNames[i]}:`);
        console.log(`  underlying (${underlyingNames[i]}) : ${underlyingBalance}`);
        console.log(`  indicator balance        : ${indicatorBalance}`);
        console.log(`  encrypted balance        : ${decryptedBalance}`);
        console.log('');
    }
});

task('approve-wrapper', 'approve FHERC20 wrapper to spend underlying tokens')
.addParam('token', 'token index (0=eUSDC, 1=eUSDT, 2=ePYUSD)')
.addParam('amount', 'amount to approve')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    const tokenIndex = parseInt(taskArgs.token);
    const amount = BigInt(taskArgs.amount);

    const mToken = (await hre.ethers.getContractAt('IERC20', underlyingTokens[tokenIndex])).connect(signer);
    const wrapperAddress = tokens[tokenIndex];

    console.log(`Approving ${tokenNames[tokenIndex]} wrapper to spend ${amount} ${underlyingNames[tokenIndex]}...`);

    const tx = await mToken.approve(wrapperAddress, amount);
    await tx.wait();

    console.log('Approved! TX:', tx.hash);
});

task('wrap-tokens', 'wrap underlying tokens to encrypted FHERC20')
.addParam('token', 'token index (0=eUSDC, 1=eUSDT, 2=ePYUSD)')
.addParam('amount', 'amount to wrap')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    const tokenIndex = parseInt(taskArgs.token);
    const amount = BigInt(taskArgs.amount);

    const eToken = (await hre.ethers.getContractAt('FHERC20Wrapper', tokens[tokenIndex])).connect(signer);

    console.log(`Wrapping ${amount} ${underlyingNames[tokenIndex]} -> ${tokenNames[tokenIndex]}...`);

    const tx = await eToken.wrap(signer.address, amount);
    await tx.wait();

    console.log('Wrapped! TX:', tx.hash);
});

task('set-operator', 'set operator (pool) on FHERC20 token')
.addParam('token', 'token index (0=eUSDC, 1=eUSDT, 2=ePYUSD)')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    const tokenIndex = parseInt(taskArgs.token);

    const eToken = (await hre.ethers.getContractAt('FHERC20Wrapper', tokens[tokenIndex])).connect(signer);

    // Set operator for a long time (max uint48)
    const until = 2n ** 48n - 1n;

    console.log(`Setting pool ${poolAddress} as operator for ${tokenNames[tokenIndex]}...`);

    const tx = await eToken.setOperator(poolAddress, until);
    await tx.wait();

    console.log('Operator set! TX:', tx.hash);
});

task('set-all-operators', 'set pool as operator for all FHERC20 tokens')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    const until = 2n ** 48n - 1n;

    console.log(`Setting pool ${poolAddress} as operator for all tokens...\n`);

    for (let i = 0; i < tokens.length; i++) {
        const eToken = (await hre.ethers.getContractAt('FHERC20Wrapper', tokens[i])).connect(signer);

        console.log(`  ${tokenNames[i]}...`);
        const tx = await eToken.setOperator(poolAddress, until);
        await tx.wait();
        console.log(`    TX: ${tx.hash}`);
    }

    console.log('\nAll operators set!');
});

task('check-operator', 'check if pool is operator for token')
.addParam('token', 'token index (0=eUSDC, 1=eUSDT, 2=ePYUSD)')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    const tokenIndex = parseInt(taskArgs.token);

    const eToken = await hre.ethers.getContractAt('FHERC20Wrapper', tokens[tokenIndex]);
    const isOperator = await eToken.isOperator(signer.address, poolAddress);

    console.log(`\nIs pool operator for ${tokenNames[tokenIndex]}? ${isOperator}`);
});
