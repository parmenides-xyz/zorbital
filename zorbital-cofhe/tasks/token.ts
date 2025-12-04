import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { tokens, tokenNames } from './util/constants';
import { Encryptable, FheTypes, cofhejs } from 'cofhejs/node';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { initialiseCofheJs } from './util/common';

task('get-token-balances', 'get user token balances').setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    await initialiseCofheJs(signer);

    const tokenContracts = await getTokenContracts(signer, hre);

    console.log(`\nBalances for ${signer.address}:\n`);

    for (let i = 0; i < tokens.length; i++) {
        const userEncBalance = await tokenContracts[i].encBalances(signer.address);
        const userBalance = await tokenContracts[i].balanceOf(signer.address);

        let encOutput = '(unable to unseal)';
        try {
            const result = await cofhejs.unseal(userEncBalance, FheTypes.Uint128);
            if (result.data !== null) {
                encOutput = result.data.toString();
            }
        } catch (e) {}

        console.log(`${tokenNames[i]}:`);
        console.log(`  public balance    : ${userBalance}`);
        console.log(`  encrypted balance : ${encOutput}`);
        console.log('');
    }
});

task('mint-public', 'mint public tokens to user')
.addParam('token', 'token index (0=eUSDC, 1=eUSDT, 2=eDAI)')
.addParam('amount', 'amount to mint')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    const tokenIndex = parseInt(taskArgs.token);
    const amount = BigInt(taskArgs.amount);

    const tokenContracts = await getTokenContracts(signer, hre);

    console.log(`Minting ${amount} ${tokenNames[tokenIndex]} to ${signer.address}...`);

    const tx = await tokenContracts[tokenIndex].mint(signer.address, amount);
    await tx.wait();

    console.log('Done! TX:', tx.hash);
});

task('mint-encrypted', 'mint encrypted tokens to user')
.addParam('token', 'token index (0=eUSDC, 1=eUSDT, 2=eDAI)')
.addParam('amount', 'amount to mint')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    await initialiseCofheJs(signer);

    const tokenIndex = parseInt(taskArgs.token);
    const amount = BigInt(taskArgs.amount);

    const tokenContracts = await getTokenContracts(signer, hre);

    console.log(`Minting ${amount} encrypted ${tokenNames[tokenIndex]} to ${signer.address}...`);

    const encrypted = await cofhejs.encrypt([Encryptable.uint128(amount)]);

    if (!encrypted.success || encrypted.data === null) {
        console.error(encrypted.error);
        return;
    }

    const tx = await tokenContracts[tokenIndex].mintEncrypted(signer.address, encrypted.data[0]);
    await tx.wait();

    console.log('Done! TX:', tx.hash);
});

task('wrap-tokens', 'wrap public tokens to encrypted')
.addParam('token', 'token index (0=eUSDC, 1=eUSDT, 2=eDAI)')
.addParam('amount', 'amount to wrap')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    const tokenIndex = parseInt(taskArgs.token);
    const amount = BigInt(taskArgs.amount);

    const tokenContracts = await getTokenContracts(signer, hre);

    console.log(`Wrapping ${amount} ${tokenNames[tokenIndex]} to encrypted...`);

    const tx = await tokenContracts[tokenIndex].wrap(signer.address, amount);
    await tx.wait();

    console.log('Done! TX:', tx.hash);
});

const getTokenContracts = async (signer: HardhatEthersSigner, hre: HardhatRuntimeEnvironment) => {
    const contracts = [];
    for (const addr of tokens) {
        const contract = await hre.ethers.getContractAt('HybridFHERC20', addr);
        contracts.push(contract.connect(signer));
    }
    return contracts;
}
